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

  def call_service(conn, domain, service, opts) do
    id =
      GenServer.call(
        conn,
        {:command, self(),
         %{
           type: :call_service,
           domain: domain,
           service: service,
           service_data: Keyword.get(opts, :data, %{}),
           target: Keyword.get(opts, :target, %{})
         }}
      )

    receive do
      {:hass, ^id, {:ok, result}} -> {:ok, result}
      {:hass, ^id, {:error, e}} -> {:error, e}
    after
      5000 -> {:error, :timeout}
    end
  end

  def subscribe_events(conn, event_type) do
    id =
      GenServer.call(
        conn,
        {:subscription, self(),
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
    id =
      GenServer.call(conn, {:subscription, self(), %{type: :subscribe_trigger, trigger: trigger}})

    receive do
      {:hass, ^id, {:ok, _}} -> {:ok, id}
      {:hass, ^id, {:error, e}} -> {:error, e}
    end
  end

  ## GenServer Callbacks

  defmodule State do
    defstruct [:connection, :last_id, :handlers]
    @type handler_type :: :command
    @type handler :: {handler_type, pid}
    @type t :: %State{
            connection: {pid, reference},
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
      {:error, e} ->
        {:stop, e}

      {:ok, {conn_pid, stream_ref}} ->
        case auth({conn_pid, stream_ref}, config) do
          {:error, e} ->
            {:stop, e}

          {:ok, _version} ->
            {:ok, %State{connection: {conn_pid, stream_ref}, last_id: 0, handlers: %{}}}
        end
    end
  end

  defp open_websocket(config) do
    {host, port, path} =
      if config[:plugin] do
        {"supervisor", 80, "/core/websocket"}
      else
        {config[:host], config[:port], "/api/websocket"}
      end

    Logger.debug(fn -> "Opening connection to home assistant on #{inspect(host)}:#{port}" end)

    case :gun.open(host, port, %{transport: :tcp}) do
      {:error, e} ->
        {:error, {:cannot_open, {host, port}, e}}

      {:ok, conn_pid} ->
        case :gun.await_up(conn_pid) do
          {:error, e} ->
            {:error, {:cannot_open, {host, port}, e}}

          {:ok, protocol} ->
            Logger.debug(fn ->
              "Upgrading to websocket at #{inspect(protocol)}://#{inspect(host)}:#{port}#{path}"
            end)

            stream_ref = :gun.ws_upgrade(conn_pid, path)

            receive do
              {:gun_upgrade, ^conn_pid, ^stream_ref, ["websocket"], _headers} ->
                {:ok, {conn_pid, stream_ref}}

              {:gun_response, ^conn_pid, _, _, status, headers} ->
                {:error, {:ws_upgrade_failed, {host, port, path}, {:http, status, headers}}}

              {:gun_error, ^conn_pid, ^stream_ref, reason} ->
                {:error, {:ws_upgrade_failed, {host, port, path}, reason}}
            after
              1_000 -> {:error, :timeout}
            end
        end
    end
  end

  defp auth({conn_pid, stream_ref}, config) do
    token =
      if config[:plugin] do
        System.get_env("SUPERVISOR_TOKEN")
      else
        config[:token]
      end

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
  def handle_call({hdl_type, pid, msg}, _target, state) do
    id = state.last_id + 1
    msg = JSON.encode!(Map.put(msg, :id, id))
    Logger.debug(fn -> "Sending: #{msg}" end)

    {conn_pid, stream_ref} = state.connection
    :gun.ws_send(conn_pid, stream_ref, {:text, msg})

    handlers = Map.put(state.handlers, id, {hdl_type, pid})
    {:reply, id, %{state | last_id: id, handlers: handlers}}
  end

  @impl true
  def handle_info({:gun_ws, pid, ref, {:text, data}}, state)
      when {pid, ref} == state.connection do
    Logger.debug(fn -> "received: #{data}" end)
    msg = JSON.decode!(data)
    id = msg["id"]

    case state.handlers[id] do
      nil ->
        Logger.warn(fn -> "Unknown handler for message: #{inspect(msg)}" end)
        {:noreply, state}

      {:command, pid} ->
        send(pid, {:hass, id, process_msg(msg)})
        {:noreply, %{state | handlers: Map.drop(state.handlers, [id])}}

      {:subscription, pid} ->
        send(pid, {:hass, id, process_msg(msg)})
        {:noreply, state}
    end
  end

  def handle_info({:gun_ws, pid, ref, {:close, n, text}}, state)
      when {pid, ref} == state.connection do
    {:stop, {:websocket_closed, n, text}}
  end

  def handle_info({:gun_ws, pid, ref, {:close, text}}, state)
      when {pid, ref} == state.connection do
    {:stop, {:websocket_closed, text}}
  end

  def handle_info({:gun_down, pid, _protocol, reason, _killed_streams}, state)
      when pid == elem(state.connection, 0) do
    {:stop, {:websocket_closed, reason}}
  end

  def handle_info(unexpected, state) do
    Logger.warn(fn -> "Unexpected message: #{inspect(unexpected)}" end)
    {:noreply, state}
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
end
