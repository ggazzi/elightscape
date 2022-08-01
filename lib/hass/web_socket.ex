defmodule Hass.WebSocket do
  use GenServer
  require Logger

  @ws_upgrade_timeout 1_000

  #############################################################################
  ## Public API

  def start(opts) do
    GenServer.start(__MODULE__, :ok, opts)
  end

  def start_link(opts) do
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  @spec call_service(proc, String.t() | atom, String.t() | atom, keyword) ::
          {:ok, any} | {:error, any}
        when proc: atom | pid | {atom, any} | {:via, atom, any}
  def call_service(conn, domain, service, opts) do
    id =
      GenServer.call(
        conn,
        {:command,
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

  def subscribe_trigger(conn, trigger) do
    id =
      GenServer.call(
        conn,
        {{:subscribe, :trigger}, %{type: :subscribe_trigger, trigger: trigger}}
      )

    receive do
      {:hass, ^id, :subscribed} -> {:ok, id}
      {:hass, ^id, {:error, _} = error} -> error
    end
  end

  def unsubscribe(conn, sub_id) do
    case GenServer.call(conn, {:unsubscribe, sub_id}) do
      {:error, _} = error ->
        error

      {:ok, unsub_id} ->
        receive do
          {:hass, ^unsub_id, :unsubscribed} -> :ok
          {:hass, ^unsub_id, {:error, _} = error} -> error
        end
    end
  end

  #############################################################################
  ## GenServer callbacks

  defstruct [:conn_pid, :stream_ref, :monitor_ref, :last_id, :handlers, :callers]

  @type handler_type :: :command
  @type handler :: {handler_type, pid}
  @type msg_id :: non_neg_integer()
  @type state :: %__MODULE__{
          conn_pid: pid,
          stream_ref: reference,
          monitor_ref: reference,
          last_id: msg_id,
          handlers: %{msg_id => handler},
          callers: %{pid => MapSet.t(msg_id())}
        }

  @impl true
  def init(:ok) do
    case Hass.open_http_socket() do
      {:error, _} = error ->
        error

      {:ok, {conn_pid, conn_ref}} ->
        case upgrade_to_websocket(conn_pid) do
          {:error, _} = error ->
            error

          {:ok, stream_ref} ->
            case auth(conn_pid, stream_ref) do
              {:error, _} = error ->
                error

              {:ok, _version} ->
                {:ok,
                 %__MODULE__{
                   conn_pid: conn_pid,
                   stream_ref: stream_ref,
                   monitor_ref: conn_ref,
                   last_id: 0,
                   handlers: %{},
                   callers: %{}
                 }}
            end
        end
    end
  end

  defp upgrade_to_websocket(conn_pid) do
    path = Hass.endpoint_path("websocket")
    stream_ref = :gun.ws_upgrade(conn_pid, path)

    receive do
      {:gun_upgrade, ^conn_pid, ^stream_ref, ["websocket"], _headers} ->
        {:ok, stream_ref}

      {:gun_response, ^conn_pid, _, _, status, headers} ->
        {host, port} = Hass.get_host_port()
        {:error, {:ws_upgrade_failed, {host, port, path}, {:http, status, headers}}}

      {:gun_error, ^conn_pid, ^stream_ref, reason} ->
        {host, port} = Hass.get_host_port()
        {:error, {:ws_upgrade_failed, {host, port, path}, reason}}
    after
      @ws_upgrade_timeout -> {:error, :timeout}
    end
  end

  @impl true
  def handle_call({:unsubscribe, sub_id}, {caller, _}, state) do
    case state.handlers[sub_id] do
      {{:subscription, kind}, subscriber} ->
        {unsub_id, state} =
          send_message_with_handler(
            unsubscription_message(sub_id, kind),
            {:unsubscribe, sub_id, subscriber},
            caller,
            state
          )

        {:reply, {:ok, unsub_id}, state}

      _ ->
        {:reply, {:error, :no_subscription}, state}
    end
  end

  def handle_call({hdl_type, msg}, {caller, _}, state) do
    {id, state} = send_message_with_handler(msg, hdl_type, caller, state)
    {:reply, id, state}
  end

  defp send_message_with_handler(
         msg,
         hdl_type,
         caller,
         %{conn_pid: conn_pid, stream_ref: stream_ref} = state
       ) do
    id = state.last_id + 1
    send_message(conn_pid, stream_ref, id, msg)
    handlers = Map.put(state.handlers, id, {hdl_type, caller})

    {:ok, callers} =
      Map.get_and_update(state.callers, caller, fn
        nil -> {:ok, {Process.monitor(caller), MapSet.new([id])}}
        {monitor_ref, ids} -> {:ok, {monitor_ref, MapSet.put(ids, id)}}
      end)

    {id, %{state | last_id: id, handlers: handlers, callers: callers}}
  end

  defp send_message(conn_pid, stream_ref, id, msg) do
    msg = JSON.encode!(Map.put(msg, :id, id))
    Logger.debug(fn -> "Sending: #{msg}" end)
    :gun.ws_send(conn_pid, stream_ref, {:text, msg})
  end

  @impl true
  def handle_info(
        {:gun_ws, pid, ref, {:text, data}},
        %{conn_pid: conn_pid, stream_ref: stream_ref, handlers: handlers} = state
      )
      when pid == conn_pid and ref == stream_ref do
    Logger.debug(fn -> "received: #{data}" end)

    msg = JSON.decode!(data)
    id = msg["id"]
    Logger.debug(inspect(handlers))
    state = apply_response_handler(id, msg, handlers[id], state)
    {:noreply, state}
  end

  def handle_info({:gun_ws, pid, ref, {:close, n, text}}, %{
        conn_pid: conn_pid,
        stream_ref: stream_ref
      })
      when pid == conn_pid and ref == stream_ref do
    {:stop, {:websocket_closed, n, text}}
  end

  def handle_info({:gun_ws, pid, ref, {:close, text}}, %{
        conn_pid: conn_pid,
        stream_ref: stream_ref
      })
      when pid == conn_pid and ref == stream_ref do
    {:stop, {:websocket_closed, text}}
  end

  def handle_info({:gun_down, pid, _protocol, reason, _killed_streams}, %{conn_pid: conn_pid})
      when pid == conn_pid do
    {:stop, {:websocket_closed, reason}}
  end

  def handle_info({:DOWN, ref, :process, pid, reason}, %{
        conn_pid: conn_pid,
        monitor_ref: monitor_ref
      })
      when pid == conn_pid and ref == monitor_ref do
    {:stop, {:websocket_closed, reason}}
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    {{_, ids}, callers} = Map.pop(state.callers, pid, {nil, []})

    Logger.debug(fn ->
      "Process #{inspect(pid)} down, discarding its pending handlers: #{ids |> Enum.map(&inspect/1) |> Enum.join(", ")}"
    end)

    {handlers, last_id} =
      for id <- ids, reduce: {state.handlers, state.last_id} do
        {handlers, last_id} ->
          case Map.pop!(handlers, id) do
            {{{:subscription, kind}, _}, handlers} ->
              unsub_id = last_id + 1

              Task.start(fn ->
                send_message(
                  state.conn_pid,
                  state.stream_ref,
                  unsub_id,
                  unsubscription_message(id, kind)
                )
              end)

              {handlers, unsub_id}

            {_, handlers} ->
              {handlers, last_id}
          end
      end

    {:noreply, %{state | callers: callers, handlers: handlers, last_id: last_id}}
  end

  defp unsubscription_message(sub_id, :trigger) do
    %{type: :unsubscribe_events, subscription: sub_id}
  end

  defp apply_response_handler(_id, msg, nil, state) do
    Logger.warn(fn -> "Unknown handler for message: #{inspect(msg)}" end)
    state
  end

  defp apply_response_handler(id, msg, {:command, caller}, state) do
    send(caller, {:hass, id, handle_command_response(msg)})
    unregister_handler(id, caller, state)
  end

  defp apply_response_handler(id, msg, {{:subscribe, kind}, caller}, state) do
    case handle_command_response(msg) do
      {:ok, _} ->
        send(caller, {:hass, id, :subscribed})
        %{state | handlers: %{state.handlers | id => {{:subscription, kind}, caller}}}

      {:error, _} = error ->
        send(caller, {:hass, id, error})
        unregister_handler(id, caller, state)
    end
  end

  defp apply_response_handler(id, msg, {{:subscription, :trigger}, caller}, state) do
    response =
      case msg do
        %{"type" => "event", "event" => %{"variables" => %{"trigger" => trigger}}} ->
          {:trigger, trigger}

        _ ->
          {:error, {:malformed_response, msg}}
      end

    send(caller, {:hass, id, response})
    state
  end

  defp apply_response_handler(id, msg, {{:unsubscribe, sub_id, subscriber}, caller}, state) do
    response =
      case handle_command_response(msg) do
        {:ok, _} -> :unsubscribed
        {:error, _} = error -> error
      end

    send(caller, {:hass, id, response})
    unregister_handler(sub_id, subscriber, unregister_handler(id, caller, state))
  end

  defp unregister_handler(id, caller, %{handlers: handlers, callers: callers} = state) do
    {_, callers} =
      Map.get_and_update!(callers, caller, fn {monitor_ref, ids} ->
        ids = MapSet.delete(ids, id)

        if Enum.empty?(ids) do
          Process.demonitor(monitor_ref)
          :pop
        else
          {:ok, ids}
        end
      end)

    %{state | handlers: Map.delete(handlers, id), callers: callers}
  end

  defp handle_command_response(msg) do
    case msg do
      %{"type" => "result", "error" => error} ->
        {:error, error}

      %{"type" => "result", "success" => false} ->
        {:error, Map.delete(msg, "id")}

      %{"type" => "result", "success" => true} ->
        {:ok, msg["result"]}

      _ ->
        {:error, {:malformed_response, msg}}
    end
  end

  #############################################################################
  ## Authentication

  defp auth(conn_pid, stream_ref) do
    Logger.debug("Waiting for auth_required message from home assistant")

    case receive_auth_required(conn_pid, stream_ref) do
      :ok ->
        Logger.debug("Sending auth message to home assistant")
        auth_msg = JSON.encode!(%{"type" => "auth", "access_token" => Hass.auth_token()})
        :gun.ws_send(conn_pid, stream_ref, {:text, auth_msg})

        receive do
          {:gun_ws, ^conn_pid, ^stream_ref, {:text, data}} ->
            data = JSON.decode!(data)

            case data["type"] do
              "auth_ok" ->
                Logger.debug("Authentication to home assistant complete")
                Logger.debug(inspect(data))
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

  defp receive_auth_required(conn_pid, stream_ref) do
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
end
