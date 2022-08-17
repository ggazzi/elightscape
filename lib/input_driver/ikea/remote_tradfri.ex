defmodule InputDriver.Ikea.RemoteTradfri do
  use InputDriver.MqttButtons,
    click_cooldown: 200,
    fire_click_immediately: false,
    payload_type: :string

  require Logger

  ## Client API

  def start(opts) do
    InputDriver.MqttButtons.start(__MODULE__, opts)
  end

  def start_link(opts) do
    InputDriver.MqttButtons.start_link(__MODULE__, opts)
  end

  ## GenServer Callbacks

  def child_spec(opts) do
    # FIXME: remove hardcoded MQTT topic prefix
    opts = Keyword.put(opts, :topic, "zigbee/#{opts[:entity_id]}/action")
    InputDriver.MqttButtons.child_spec(__MODULE__, opts)
  end

  @impl InputDriver.MqttButtons
  @spec decode_action(String.t()) :: InputDriver.MqttButtons.action()
  def decode_action(action) do
    case action do
      "toggle" -> {:toggle, :click}
      "toggle_hold" -> {:toggle, :hold}
      "arrow_right_click" -> {:arrow_right, :click}
      "arrow_right_hold" -> {:arrow_right, :hold}
      "arrow_right_release" -> {:arrow_right, :release}
      "arrow_left_click" -> {:arrow_left, :click}
      "arrow_left_hold" -> {:arrow_left, :hold}
      "arrow_left_release" -> {:arrow_left, :release}
      "brightness_up_click" -> {{:brightness, :up}, :click}
      "brightness_up_hold" -> {{:brightness, :up}, :hold}
      "brightness_up_release" -> {{:brightness, :up}, :release}
      "brightness_down_click" -> {{:brightness, :down}, :click}
      "brightness_down_hold" -> {{:brightness, :down}, :hold}
      "brightness_down_release" -> {{:brightness, :down}, :release}
    end
  end
end
