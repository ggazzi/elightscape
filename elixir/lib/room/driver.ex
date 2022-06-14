defmodule Room.Controller do
  use GenServer
  require Logger

  ## Client API

  def start([hass, name | opts]) do
    GenServer.start(__MODULE__, {hass, name}, opts)
  end

  def start_link([hass, name | opts]) do
    GenServer.start_link(__MODULE__, {hass, name}, opts)
  end

  ## Server Callbacks

  def init({hass, name}) do
    {:ok, machine} = Room.StateMachine.start_link([])

    trigger_spec = [
      # {%{:platform => :state, entity_id: "sensor.bedroom_remote_action", to: nil}, :toggle}
      {{InputDriver.Ikea5Btn, ["sensor.#{name}_remote_action"]}, nil}
    ]

    triggers =
      for {trigger, handler} <- trigger_spec, into: %{} do
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
       scene_on: "scene.#{name}_normal_night",
       scene_off: "scene.#{name}_off"
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
    scene =
      if on do
        state.scene_on
      else
        state.scene_off
      end

    Task.start(fn ->
      {:ok, _} =
        Hass.Connection.call_service(state.hass, :scene, :turn_on, target: %{entity_id: scene})
    end)
  end

  defp handle_response(nil, _state) do
    nil
  end
end
