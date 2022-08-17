defmodule InputDriver.Ikea.RemoteStyrbar do
  use InputDriver.MqttButtons, payload_type: :string

  ## Client API

  def start(opts) do
    InputDriver.MqttButtons.start(__MODULE__, opts)
  end

  def start_link(opts) do
    InputDriver.MqttButtons.start_link(__MODULE__, opts)
  end

  def child_spec(opts) do
    # FIXME: remove hardcoded MQTT topic prefix
    opts = Keyword.put(opts, :topic, "zigbee/#{opts[:entity_id]}/action")
    InputDriver.MqttButtons.child_spec(__MODULE__, opts)
  end

  ## GenServer Callbacks

  @impl InputDriver.MqttButtons
  @spec decode_action(String.t()) :: InputDriver.MqttButtons.action()
  def decode_action(action) do
    case action do
      "on" -> {:on, :click}
      "off" -> {:off, :click}
      "arrow_right_click" -> {:arrow_right, :click}
      "arrow_right_hold" -> {:arrow_right, :hold}
      "arrow_right_release" -> {:arrow_right, :release}
      "arrow_left_click" -> {:arrow_left, :click}
      "arrow_left_hold" -> {:arrow_left, :hold}
      "arrow_left_release" -> {:arrow_left, :release}
      "brightness_move_up" -> {{:brightness, :up}, :hold}
      "brightness_move_down" -> {{:brightness, :down}, :hold}
      "brightness_stop" -> :release
    end
  end
end
