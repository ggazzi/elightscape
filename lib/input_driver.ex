defmodule InputDriver do
  def send_input(%{subscriber: subscriber}, input) do
    send(subscriber, {InputDriver, self(), input})
  end
end
