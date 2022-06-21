defmodule Room.Controller do
  use GenServer
  require Logger

  ## Client API

  def start([hass, mqtt, config | opts]) do
    GenServer.start(__MODULE__, {hass, mqtt, config}, opts)
  end

  def start_link([hass, mqtt, config | opts]) do
    GenServer.start_link(__MODULE__, {hass, mqtt, config}, opts)
  end

  ## Server Callbacks

  def init({hass, mqtt, config}) do
    {:ok, machine} = Room.StateMachine.start_link([self(), config])

    name = config[:name]

    triggers =
      for {:trigger, {trigger, handler}} <- config, into: %{} do
        {prepare_trigger(hass, trigger), prepare_handler(handler)}
      end

    triggers =
      for {:input, {module, args, handler}} <- config, into: triggers do
        {prepare_input(mqtt, module, args), prepare_handler(handler)}
      end

    {:ok,
     %{
       machine: machine,
       triggers: triggers,
       hass: hass,
       mqtt: mqtt,
       scene_on: "scene.#{name}_low_day",
       scene_off: "scene.#{name}_off"
     }}
  end

  defp prepare_handler(handler) do
    cond do
      is_function(handler) ->
        handler

      handler == nil ->
        fn x -> x end

      true ->
        fn _ -> handler end
    end
  end

  defp prepare_input(mqtt, module, opts) do
    {:ok, pid} = module.start([mqtt | opts])
    {module, pid}
  end

  defp prepare_trigger(hass, trigger) do
    {:ok, {:hass, sub_id}} = Hass.Connection.subscribe_trigger(hass, trigger)
    {:hass, sub_id}
  end

  def handle_info({Room.StateMachine, response}, state) do
    handle_response(response, state)
    {:noreply, state}
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
        Room.StateMachine.send_event(state.machine, message)
        Logger.info(fn -> "[#{inspect(sub)}] #{inspect(message)}" end)
        Logger.debug(fn -> "[#{inspect(sub)}] #{inspect(event)}" end)
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
