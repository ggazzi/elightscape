defmodule InputDriver.Ikea.RemoteTradfri do
  use InputDriver.MqttButtons

  ## Client API

  def start([mqtt, subscriber, entity_id | opts]) do
    GenServer.start(__MODULE__, {mqtt, subscriber, entity_id}, opts)
  end

  def start_link([mqtt, subscriber, entity_id | opts]) do
    GenServer.start_link(__MODULE__, {mqtt, subscriber, entity_id}, opts)
  end

  ## GenServer Callbacks

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
      "brightness_up_click" -> {:brightness_up, :click}
      "brightness_up_hold" -> {:brightness_up, :hold}
      "brightness_up_release" -> {:brightness_up, :release}
      "brightness_down_click" -> {:brightness_down, :click}
      "brightness_down_hold" -> {:brightness_down, :hold}
      "brightness_down_release" -> {:brightness_down, :release}
    end
  end
end
