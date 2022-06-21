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
      for {:input, {module, opts, handler}} <- config, into: %{} do
        opts = [mqtt, self() | opts]
        {pid, ref} = prepare_input(module, opts)
        {pid, {prepare_handler(handler), ref, {module, opts}}}
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

  defp prepare_input(module, opts) do
    {:ok, pid} = module.start(opts)
    ref = Process.monitor(pid)

    {pid, ref}
  end

  def handle_info({Room.StateMachine, response}, state) do
    handle_response(response, state)
    {:noreply, state}
  end

  def handle_info({module, pid, event}, state) do
    case state.triggers[pid] do
      nil ->
        Logger.warn(fn -> "[#{inspect(pid)}] unknown subscription #{inspect(event)}" end)
        {:noreply, state}

      {handler, _, _} ->
        message = handler.(event)
        Room.StateMachine.send_event(state.machine, message)
        Logger.info(fn -> "[#{inspect(pid)}] #{inspect(message)}" end)
        Logger.debug(fn -> "[#{inspect(pid)}] #{inspect(event)}" end)
        {:noreply, state}
    end
  end

  def handle_info({:DOWN, ref, :process, pid, reason}, state) do
    case state.triggers[pid] do
      nil ->
        {:noreply, state}

      {handler, ^ref, {module, opts}} ->
        {new_pid, new_ref} = prepare_input(module, opts)

        triggers =
          Map.put(Map.delete(state.triggers, pid), new_pid, {handler, new_ref, {module, opts}})

        {:noreply, %{state | triggers: triggers}}
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
