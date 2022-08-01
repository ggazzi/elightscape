defmodule Hass.Connection do
  use GenServer
  require Logger

  ## Client API

  def start(config, opts) do
    GenServer.start(__MODULE__, config, opts)
  end

  def start_link(config, opts) do
    GenServer.start_link(__MODULE__, config, opts)
  end

  def get_state(conn, entity_id) do
    rest_get(conn, "states/#{entity_id}")
  end

  defp rest_get(conn, endpoint) do
    {host, port, path, headers} = GenServer.call(conn, {:rest, endpoint})
    headers = Map.put(headers, "Content-Type", "application/json")

    task =
      Task.async(fn ->
        {:ok, conn_pid} = :gun.open(host, port, %{transport: :tcp})
        {:ok, :http} = :gun.await_up(conn_pid)
        conn_ref = Process.monitor(conn_pid)

        stream_ref = :gun.get(conn_pid, path, headers)

        case receive_http_response(conn_pid, conn_ref, stream_ref) do
          {:ok, data} -> JSON.decode(data)
          {:error, _, _} = error -> error
        end
      end)

    Task.await(task)
  end

  defp receive_http_response(conn_pid, conn_ref, stream_ref) do
    receive do
      {:gun_response, ^conn_pid, ^stream_ref, :fin, status, _headers} ->
        if status == 200 do
          {:ok, nil}
        else
          {:error, status, nil}
        end

      {:gun_response, ^conn_pid, ^stream_ref, :nofin, status, _headers} ->
        case receive_http_data(conn_pid, conn_ref, stream_ref, []) do
          {:error, _, _} = error ->
            error

          {:ok, data} ->
            if status == 200 do
              {:ok, data}
            else
              {:error, status, data}
            end
        end

      {:DOWN, ^conn_ref, :process, ^conn_pid, reason} ->
        {:error, :disconnected, reason}
    end
  end

  defp receive_http_data(conn_pid, conn_ref, stream_ref, data) do
    receive do
      {:gun_data, ^conn_pid, ^stream_ref, :nofin, new_data} ->
        receive_http_data(conn_pid, conn_ref, stream_ref, [new_data | data])

      {:gun_data, ^conn_pid, ^stream_ref, :fin, new_data} ->
        {:ok, [new_data | data] |> Enum.reverse() |> Enum.join()}

      {:DOWN, ^conn_ref, :process, ^conn_pid, reason} ->
        {:error, :disconnected, reason}
    end
  end

  def get_states(conn, relevant_ids \\ nil) do
    id = GenServer.call(conn, {:ws, :command, %{type: :get_states}})

    receive do
      {:hass, ^id, {:ok, states}} ->
        {:ok,
         if relevant_ids do
           for state <- states, state["entity_id"] in relevant_ids, into: %{} do
             Map.pop(state, "entity_id")
           end
         else
           states
         end}

      {:hass, ^id, {:error, reason}} ->
        {:error, reason}
    after
      5000 -> {:error, :timeout}
    end
  end

  @spec call_service(atom | pid | {atom, any} | {:via, atom, any}, any, any, keyword) :: any
  def call_service(conn, domain, service, opts) do
    id =
      GenServer.call(
        conn,
        {:ws, :command,
         %{
           type: :call_service,
           domain: domain,
           service: service,
           service_data: Keyword.get(opts, :data, %{}),
           target: Keyword.get(opts, :target, %{})
         }}
      )

    receive do
      {:hass, ^id, result} -> result
    after
      5000 -> {:error, :timeout}
    end
  end

  def subscribe_events(conn, event_type) do
    id =
      GenServer.call(
        conn,
        {:ws, :subscription,
         %{
           type: :subscribe_events,
           event_type: event_type
         }}
      )

    receive do
      {:hass, ^id, {:ok, _}} -> {:ok, id}
      {:hass, ^id, {:error, e}} -> {:error, e}
    after
      5000 -> {:error, :timeout}
    end
  end

  def subscribe_trigger(conn, trigger) do
    id = GenServer.call(conn, {:ws, :subscription, %{type: :subscribe_trigger, trigger: trigger}})

    receive do
      {:hass, ^id, {:ok, _}} -> {:ok, id}
      {:hass, ^id, {:error, e}} -> {:error, e}
    end
  end

  ## GenServer Callbacks

  defmodule State do
    defstruct [:ws_conn, :ws_monitor, :http_conn, :http_monitor, :last_id, :handlers]
    @type handler_type :: :command
    @type handler :: {handler_type, pid}
    @type t :: %State{
            ws_conn: {pid, reference},
            ws_monitor: reference,
            http_conn: pid,
            http_monitor: reference,
            last_id: non_neg_integer,
            handlers: Handler.t()
          }
  end

  def child_spec([config | opts]) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, [config, opts]}}
  end

  @impl true
  def init(config) do
    case open_websocket(config) do
      {:error, reason} ->
        {:stop, reason}

      {:ok, {ws_conn_pid, ws_monitor_ref, ws_stream_ref}} ->
        ws_conn = {ws_conn_pid, ws_stream_ref}

        case auth(ws_conn, config) do
          {:error, reason} ->
            {:stop, reason}

          {:ok, _version} ->
            {:ok,
             {config,
              %State{
                ws_conn: ws_conn,
                ws_monitor: ws_monitor_ref,
                last_id: 0,
                handlers: %{}
              }}}
        end
    end
  end

  defp open_http_socket(config) do
    {host, port} = get_host_port(config)
    Logger.debug(fn -> "Opening connection to home assistant on #{inspect(host)}:#{port}" end)

    case :gun.open(host, port, %{transport: :tcp}) do
      {:error, e} ->
        {:error, {:cannot_open, {host, port}, e}}

      {:ok, conn_pid} ->
        conn_ref = Process.monitor(conn_pid)

        case :gun.await_up(conn_pid) do
          {:error, e} ->
            {:error, {:cannot_open, {host, port}, e}}

          {:ok, :http} ->
            {:ok, {conn_pid, conn_ref}}
        end
    end
  end

  defp open_websocket(config) do
    case open_http_socket(config) do
      {:error, reason} ->
        {:error, reason}

      {:ok, {conn_pid, conn_ref}} ->
        Logger.debug(fn ->
          "Upgrading Hass connection to websocket"
        end)

        path = request_path(config, "websocket")
        stream_ref = :gun.ws_upgrade(conn_pid, path)

        receive do
          {:gun_upgrade, ^conn_pid, ^stream_ref, ["websocket"], _headers} ->
            {:ok, {conn_pid, conn_ref, stream_ref}}

          {:gun_response, ^conn_pid, _, _, status, headers} ->
            {host, port} = get_host_port(config)
            {:error, {:ws_upgrade_failed, {host, port, path}, {:http, status, headers}}}

          {:gun_error, ^conn_pid, ^stream_ref, reason} ->
            {host, port} = get_host_port(config)
            {:error, {:ws_upgrade_failed, {host, port, path}, reason}}
        after
          1_000 -> {:error, :timeout}
        end
    end
  end

  defp auth({conn_pid, stream_ref}, config) do
    token = get_auth_token(config)

    Logger.debug("Waiting for auth_required message from home assistant")

    case receive_auth_required({conn_pid, stream_ref}) do
      :ok ->
        Logger.debug("Sending auth message to home assistant")
        auth_msg = JSON.encode!(%{"type" => "auth", "access_token" => token})
        :gun.ws_send(conn_pid, stream_ref, {:text, auth_msg})

        receive do
          {:gun_ws, ^conn_pid, ^stream_ref, {:text, data}} ->
            {:ok, data} = JSON.decode(data)

            case data["type"] do
              "auth_ok" ->
                Logger.debug("Authentication to home assistant complete")
                {:ok, data["ha_version"]}

              "auth_invalid" ->
                {:error, {:auth_invalid, data["message"]}}

              _ ->
                {:error,
                 {:unexpected_message_type, "expected auth_ok or auth_invalid", data["type"]}}
            end
        after
          5_000 -> {:error, :timeout}
        end

      error ->
        error
    end
  end

  defp receive_auth_required({conn_pid, stream_ref}) do
    receive do
      {:gun_ws, ^conn_pid, ^stream_ref, {:text, data}} ->
        case JSON.decode(data) do
          {:ok, %{"type" => "auth_required"}} ->
            :ok

          {:ok, data} ->
            {:error, {:unexpected_message_type, "expected auth_required", data["type"]}}

          {:error, e} ->
            {:error, {:malformed_message, e}}
        end
    after
      5_000 -> {:error, :timeout}
    end
  end

  @impl true
  def handle_call({:ws, hdl_type, msg}, {pid, _}, {config, state}) do
    id = state.last_id + 1
    msg = JSON.encode!(Map.put(msg, :id, id))
    Logger.debug(fn -> "Sending: #{msg}" end)

    {conn_pid, stream_ref} = state.ws_conn
    :gun.ws_send(conn_pid, stream_ref, {:text, msg})

    handlers = Map.put(state.handlers, id, {hdl_type, pid})
    state = %{state | last_id: id, handlers: handlers}
    {:reply, id, {config, state}}
  end

  def handle_call({:rest, endpoint}, _target, {config, state}) do
    {host, port} = get_host_port(config)
    path = request_path(config, endpoint)
    headers = %{"Authorization" => "Bearer #{get_auth_token(config)}"}
    {:reply, {host, port, path, headers}, {config, state}}
  end

  @impl true
  def handle_info({:gun_ws, pid, ref, {:text, data}}, {config, state})
      when {pid, ref} == state.ws_conn do
    Logger.debug(fn -> "received: #{data}" end)
    msg = JSON.decode!(data)
    id = msg["id"]

    state =
      case state.handlers[id] do
        nil ->
          Logger.warn(fn -> "Unknown handler for message: #{inspect(msg)}" end)
          state

        {:command, pid} ->
          send(pid, {:hass, id, process_msg(msg)})
          %{state | handlers: Map.drop(state.handlers, [id])}

        {:subscription, pid} ->
          send(pid, {:hass, id, process_msg(msg)})
          state
      end

    {:noreply, {config, state}}
  end

  def handle_info({:gun_ws, pid, ref, {:close, n, text}}, {_config, state})
      when {pid, ref} == state.ws_conn do
    {:stop, {:websocket_closed, n, text}}
  end

  def handle_info({:gun_ws, pid, ref, {:close, text}}, {_config, state})
      when {pid, ref} == state.ws_conn do
    {:stop, {:websocket_closed, text}}
  end

  def handle_info({:gun_down, pid, _protocol, reason, _killed_streams}, {_config, state})
      when pid == elem(state.ws_conn, 0) do
    {:stop, {:websocket_closed, reason}}
  end

  def handle_info({:DOWN, ref, :process, pid, reason}, {_config, state})
      when ref == state.ws_monitor and pid == elem(state.ws_conn, 0) do
    {:stop, {:websocket_closed, reason}}
  end

  def handle_info(unexpected, {config, state}) do
    Logger.warn(fn -> "Unexpected message: #{inspect(unexpected)}" end)
    {:noreply, {config, state}}
  end

  def process_msg(msg) do
    case msg do
      %{"type" => "event", "event" => event} ->
        {:event, event}

      %{"type" => "result", "error" => error} ->
        {:error, error}

      %{"type" => "result", "success" => false} ->
        {:error, Map.delete(msg, "id")}

      %{"type" => "result", "success" => true} ->
        {:ok, msg["result"]}

      msg ->
        Map.delete(msg, ["id"])
    end
  end

  defp get_host_port(config) do
    if config[:plugin] do
      {"supervisor", 80}
    else
      {config[:host], config[:port]}
    end
  end

  defp get_auth_token(config) do
    if config[:plugin] do
      System.get_env("SUPERVISOR_TOKEN")
    else
      config[:token]
    end
  end

  defp request_path(config, endpoint) do
    if config[:plugin] do
      "/core/#{endpoint}"
    else
      "/api/#{endpoint}"
    end
  end
end
