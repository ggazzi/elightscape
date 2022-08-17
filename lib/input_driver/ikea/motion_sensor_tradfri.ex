defmodule InputDriver.Ikea.MotionSensorTradfri do
  use InputDriver.Mqtt
  require Logger

  ## Client API

  def start(opts) do
    InputDriver.Mqtt.start(__MODULE__, opts)
  end

  def start_link(opts) do
    InputDriver.Mqtt.start_link(__MODULE__, opts)
  end

  def child_spec(opts) do
    # FIXME: remove hardcoded MQTT topic prefix
    opts = Keyword.put(opts, :topic, "zigbee/#{opts[:entity_id]}")
    InputDriver.Mqtt.child_spec(__MODULE__, opts)
  end

  ## InputDriver.Mqtt Callbacks

  @impl InputDriver.Mqtt
  def init_inner(opts) do
    {:ok, opts[:entity_id]}
  end

  @impl InputDriver.Mqtt
  def handle_payload(payload, %{inner: entity_id} = state) do
    if payload["occupancy"] do
      Logger.debug(fn -> "[#{entity_id}] detected motion" end)
      InputDriver.send_input(state, :sensor_active)
    end

    {:noreply, entity_id}
  end
end
