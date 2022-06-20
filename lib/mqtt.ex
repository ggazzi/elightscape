defmodule Mqtt do
  use GenServer
  require Logger
  alias Mqtt.SubscriptionTable, as: Table

  ## Client API

  def start(config, opts) do
    GenServer.start(__MODULE__, config, opts)
  end

  def start_link(config, opts) do
    GenServer.start_link(__MODULE__, config, opts)
  end

  def subscribe(server, subscriptions) do
    GenServer.call(server, {:subscribe, %{}, subscriptions})
  end

  def unsubscribe(server, subscriptions) do
    GenServer.call(server, {:unsubscribe, %{}, subscriptions})
  end

  ## GenServer Callbacks

  defstruct [:pid, :props, :subs]

  def child_spec([config | opts]) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, [config, opts]}}
  end

  @impl true
  def init(config) do
    case :emqtt.start_link(config) do
      {:error, reason} ->
        {:stop, reason}

      {:ok, pid} ->
        case :emqtt.connect(pid) do
          {:error, reason} -> {:stop, reason}
          {:ok, properties} -> {:ok, %__MODULE__{pid: pid, props: properties, subs: Table.new()}}
        end
    end
  end

  @impl true
  def handle_info({:disconnect, reason_code, props}, state) do
    {:stop, {:mqtt_disconnected, reason_code, props}, state}
  end

  def handle_info({:publish, %{topic: topic, payload: payload}}, state) do
    Logger.debug(fn -> "Recv a PUBLISH packet - topic=#{topic} payload=#{payload}" end)

    for subscriber <- Table.lookup(state.subs, parse_topic(topic)) do
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

  @impl true
  def handle_call({:subscribe, properties, topics}, {from, _id}, state) do
    case :emqtt.subscribe(state.pid, properties, topics) do
      {:error, reason} ->
        {:reply, {:error, reason}, state}

      {:ok, props, reason_codes} ->
        subs =
          for {topic, _subopt} <- topics, into: state.subs do
            {from, parse_topic(topic)}
          end

        {:reply, {:ok, props, reason_codes}, %{state | subs: subs}}
    end
  end

  @impl true
  def handle_call({:unsubscribe, properties, topics}, from, state) do
    case :emqtt.subscribe(state.pid, properties, topics) do
      {:error, reason} ->
        {:reply, {:error, reason}, state}

      {:ok, props, reason_codes} ->
        subs =
          for {topic, _subopt} <- topics, reduce: state.subs do
            subs -> Table.unsubscribe(subs, from, parse_topic(topic))
          end

        {:reply, {:ok, props, reason_codes}, %{state | subs: subs}}
    end
  end

  defp parse_topic(topic) do
    for fragment <- String.split(topic, ~r"/") do
      case fragment do
        "#" -> :any_deep
        "+" -> :any
        _ -> fragment
      end
    end
  end
end
