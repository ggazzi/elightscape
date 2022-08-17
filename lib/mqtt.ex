defmodule Mqtt do
  use Connection
  require Logger
  alias Mqtt.SubscriptionTable, as: Table
  alias Mqtt.Topic, as: Topic

  ## Public API

  def start(config, opts) do
    Connection.start(__MODULE__, config, opts)
  end

  def start_link(config, opts) do
    Connection.start_link(__MODULE__, config, opts)
  end

  @spec subscribe(term, String.t()) :: term
  def subscribe(server, filter) do
    Connection.call(server, {:subscribe, filter})
  end

  @spec unsubscribe(term, String.t()) :: term
  def unsubscribe(server, filter) do
    Connection.call(server, {:unsubscribe, filter})
  end

  ## Connection Callbacks

  defstruct [:config, :subscriptions, :subscribers, :conn_pid]

  @type config :: term
  @type state :: %__MODULE__{
          config: config,
          subscriptions: Table.t(),
          subscribers: %{pid => {reference, MapSet.t(String.t())}},
          conn_pid: nil | pid
        }

  @impl true
  def init(config) do
    Logger.debug("init")

    state = %__MODULE__{
      config: config,
      subscriptions: Table.new(),
      subscribers: %{},
      conn_pid: nil
    }

    {:connect, :init, state}
  end

  @impl true
  def connect(_, %{config: config, subscriptions: subscriptions} = state) do
    case :emqtt.start_link(config) do
      {:error, reason} ->
        Logger.warn(fn -> "Unable to open emqtt socket: #{inspect(reason)}" end)
        {:backoff, 1000, state}

      {:ok, conn_pid} ->
        Process.unlink(conn_pid)
        Process.monitor(conn_pid)
        Logger.debug(fn -> "Opened emqtt socket, pid: #{inspect(conn_pid)}" end)

        case :emqtt.connect(conn_pid) do
          {:error, reason} ->
            Logger.warn(fn -> "Unable to connect to mqtt: #{inspect(reason)}" end)
            {:backoff, 1000, state}

          {:ok, props} ->
            Logger.debug(fn -> "Connected to mqtt, properties: #{inspect(props)}" end)

            case resubscribe_all(conn_pid, subscriptions) do
              :ok ->
                {:ok, %{state | conn_pid: conn_pid}}

              :error ->
                {:backoff, 1000, state}
            end
        end
    end
  end

  defp resubscribe_all(conn_pid, subscriptions) do
    filters = Table.subscribed_filters(subscriptions)

    if Enum.empty?(filters) do
      :ok
    else
      filters =
        for filter <- Table.subscribed_filters(subscriptions),
            do: {Topic.to_string(filter), []}

      case :emqtt.subscribe(conn_pid, %{}, filters) do
        {:error, reason} ->
          Logger.warn(fn ->
            "Failed to resubscribe with new mqtt connection: #{inspect(reason)}"
          end)

          :error

        {:ok, _props, _reason_codes} ->
          :ok
      end
    end
  end

  @impl true
  @spec disconnect(term, state) :: {:connect, :reconnect, state}
  def disconnect(_info, %{conn_pid: conn_pid} = state) do
    :emqtt.disconnect(conn_pid)
    {:connect, :reconnect, %{state | conn_pid: nil}}
  end

  @impl true
  @spec handle_info(term, state) :: {:connect, term, state}
  def handle_info({:disconnect, reason_code, props}, state) do
    {:connect, {:mqtt_disconnected, reason_code, props}, %{state | conn_pid: nil}}
    nil
  end

  def handle_info({:DOWN, _ref, :process, pid, reason}, %{conn_pid: conn_pid} = state)
      when pid == conn_pid do
    {:connect, {:emqtt_down, reason}, %{state | conn_pid: nil}}
  end

  def handle_info(
        {:publish, %{topic: topic, payload: payload}},
        %{subscriptions: subscriptions} = state
      ) do
    Logger.debug(fn -> "Recv a PUBLISH packet - topic=#{topic} payload=#{payload}" end)

    for subscriber <- Table.lookup(subscriptions, topic) do
      Logger.debug(fn -> "Sending to #{inspect(subscriber)}" end)
      send(subscriber, {:mqtt, topic, payload})
    end

    {:noreply, state}
  end

  def handle_info({:puback, {packet_id, reason_code, properties}}, state) do
    Logger.warn(fn ->
      "Recv a PUBACK packet - packet_id=#{packet_id} reason_code=#{reason_code} properties=#{properties}"
    end)

    {:noreply, state}
  end

  def handle_info(
        {:DOWN, _ref, :process, pid, _reason},
        %{subscriptions: subscriptions, subscribers: subscribers} = state
      ) do
    case subscribers[pid] do
      nil ->
        {:noreply, state}

      {_ref, filters} ->
        {subscriptions, to_unsubscribe} =
          for raw_filter <- filters, reduce: {subscriptions, []} do
            {subs, unsubs} ->
              filter = Topic.parse(raw_filter)
              subs = Table.unsubscribe(subs, pid, filter)

              # Collect filters that no longer have any subscriber
              unsubs =
                if not Table.contains_filter?(subs, filter),
                  do: [raw_filter | unsubs],
                  else: unsubs

              {subs, unsubs}
          end

        Task.start(fn -> :emqtt.unsubscribe(state.conn_pid, %{}, to_unsubscribe) end)

        subscribers = Map.delete(subscribers, pid)
        {:noreply, %{state | subscribers: subscribers, subscriptions: subscriptions}}
    end
  end

  @spec handle_call(term, GenServer.from(), state) :: {:reply, :ok, state}
  @impl true
  def handle_call(
        {:subscribe, filter},
        {from, _id},
        %{subscriptions: subscriptions, subscribers: subscribers} = state
      ) do
    case ensure_subscribed(state, filter) do
      {:error, reason} ->
        {:reply, {:error, reason}, state}

      {:ok, parsed_filter} ->
        # Ensure we are monitoring the subscriber to clean up if they die
        subscribers =
          case subscribers[from] do
            nil ->
              ref = Process.monitor(from)
              Map.put(subscribers, from, {ref, MapSet.new([filter])})

            {ref, filters} ->
              Map.put(subscribers, from, {ref, MapSet.put(filters, filter)})
          end

        subscriptions = Table.subscribe(subscriptions, from, parsed_filter)
        {:reply, :ok, %{state | subscriptions: subscriptions, subscribers: subscribers}}
    end
  end

  def handle_call(
        {:unsubscribe, raw_filter},
        {from, _id},
        %{subscriptions: subscriptions, subscribers: subscribers} = state
      ) do
    filter = Topic.parse(raw_filter)
    subscriptions = Table.unsubscribe(subscriptions, from, filter)

    # Unsubscribe to schema if no other subscribers are left
    unless Table.contains_filter?(subscriptions, filter) do
      Task.start(fn -> :emqtt.unsubscribe(state.conn_pid, %{}, [raw_filter]) end)
    end

    # Deregister subscriber if no other subscriptions are left
    subscribers =
      case subscribers[from] do
        nil ->
          subscribers

        {ref, filters} ->
          filters = MapSet.delete(filters, raw_filter)

          if Enum.empty?(filters) do
            Process.demonitor(ref)
            Map.delete(subscribers, from)
          else
            %{subscribers | from => {ref, filters}}
          end
      end

    {:reply, :ok, %{state | subscribers: subscribers, subscriptions: subscriptions}}
  end

  defp ensure_subscribed(%{subscriptions: subs, conn_pid: conn_pid}, filter) do
    parsed_filter = Topic.parse(filter)

    cond do
      Table.contains_filter?(subs, parsed_filter) ->
        {:ok, parsed_filter}

      conn_pid == nil ->
        {:error, :disconnected}

      true ->
        case :emqtt.subscribe(conn_pid, %{}, [{filter, []}]) do
          {:error, reason} -> {:error, reason}
          {:ok, _props, _reason_codes} -> {:ok, parsed_filter}
        end
    end
  end
end
