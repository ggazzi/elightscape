defmodule InputDriver.Ikea5Btn do
  use GenServer
  require Logger

  ## Client API

  def start([hass, subscriber, entity_id | opts]) do
    GenServer.start(__MODULE__, {hass, entity_id, subscriber}, opts)
  end

  def start_link([hass, subscriber, entity_id | opts]) do
    GenServer.start_link(__MODULE__, {hass, entity_id, subscriber}, opts)
  end

  ## GenServer Callbacks

  @impl true
  def init({hass, entity_id, subscriber}) do
    {:ok, id} =
      Hass.Connection.subscribe_trigger(hass, %{platform: :state, entity_id: entity_id, to: nil})

    {:ok, %{button: nil, subscriber: subscriber, hass_sub: id}}
  end

  @impl true
  def handle_info({:hass, id, {:event, event}}, state) when id == state.hass_sub do
    new_button = decode(event)

    if new_button != nil and new_button != state.button do
      send(state.subscriber, {__MODULE__, self(), new_button})
    end

    {:noreply, %{state | button: new_button}}
  end

  def decode(event) do
    case event["variables"]["trigger"]["to_state"]["attributes"]["action"] do
      "" -> nil
      "toggle" -> :toggle
      state -> state
    end
  end
end
