defmodule Room.Controller do
  use GenServer
  require Logger

  ## Client API

  def start(hass, opts) do
    GenServer.start(__MODULE__, hass, opts)
  end

  def start_link(hass, opts) do
    GenServer.start_link(__MODULE__, hass, opts)
  end

  ## Server Callbacks

  @triggers [
    # {%{:platform => :state, entity_id: "sensor.bedroom_remote_action", to: nil}, :toggle}
    {{InputDriver.Ikea5Btn, ["sensor.bedroom_remote_action"]}, nil}
  ]

  def child_spec([hass | opts]) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, [hass, opts]}}
  end

  def init(hass) do
    {:ok, machine} = Room.StateMachine.start_link([])

    triggers =
      for {trigger, handler} <- @triggers, into: %{} do
        sub = prepare_subscription(hass, trigger)

        actual_handler =
          cond do
            is_function(handler) ->
              handler

            handler == nil ->
              fn x -> x end

            true ->
              fn _ -> handler end
          end

        {sub, actual_handler}
      end

    {:ok,
     %{
       machine: machine,
       triggers: triggers,
       hass: hass,
       light: "light.bedroom_light_ceiling_retro"
     }}
  end

  defp prepare_subscription(hass, {module, opts}) do
    {:ok, pid} = module.start_link([hass, self() | opts])
    {module, pid}
  end

  defp prepare_subscription(hass, trigger) do
    {:ok, {:hass, sub_id}} = Hass.Connection.subscribe_trigger(hass, trigger)
    {:hass, sub_id}
  end

  def handle_info({module, id, event}, state) do
    sub = {module, id}

    case state.triggers[sub] do
      nil ->
        Logger.warn(fn -> "[#{inspect(sub)}] unknown subscription #{inspect(event)}" end)
        exit(:foo)

        Logger.debug(fn -> "[#{inspect(sub)}] #{inspect(event)}" end)
        {:noreply, state}

      handler ->
        message = handler.(event)
        response = Room.StateMachine.send_event(state.machine, message)
        Logger.info(fn -> "[#{inspect(sub)}] #{inspect(message)} / #{inspect(response)}" end)
        Logger.debug(fn -> "[#{inspect(sub)}] #{inspect(event)}" end)
        handle_response(response, state)
        {:noreply, state}
    end
  end

  defp handle_response({:set_lights, on}, state) do
    service =
      if on do
        "turn_on"
      else
        "turn_off"
      end

    Task.start(fn ->
      Hass.Connection.call_service(state.hass, "light", service, target: %{entity_id: state.light})
    end)
  end

  defp handle_response(nil, _state) do
    nil
  end
end
