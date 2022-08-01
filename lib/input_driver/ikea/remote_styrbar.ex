defmodule InputDriver.Ikea.RemoteStyrbar do
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
