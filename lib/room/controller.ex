defmodule Room.Controller do
  use GenServer
  require Logger

  defmodule Supervisor do
    use Elixir.Supervisor

    def start_link({_, _, config} = init_arg) do
      Supervisor.start_link(__MODULE__, init_arg,
        name: :"Room.#{Keyword.get(config, :name)}.Supervisor"
      )
    end

    @impl true
    def init({hass, mqtt, config}) do
      room_name = Keyword.get(config, :name)
      supervisor_name = :"Room.#{room_name}.DynamicSupervisor"

      children = [
        {DynamicSupervisor, name: supervisor_name, strategy: :one_for_one},
        {Room.Controller,
         [{hass, mqtt, supervisor_name, config}, name: :"Room.#{room_name}.Controller"]}
      ]

      # If either the controller or the supervisor die, the other one cannot work anymore
      Supervisor.init(children, strategy: :one_for_all)
    end
  end

  ## Client API

  def start([init_args | opts]) do
    GenServer.start(__MODULE__, init_args, opts)
  end

  def start_link([init_args | opts]) do
    GenServer.start_link(__MODULE__, init_args, opts)
  end

  ## Server Callbacks

  def init({hass, mqtt, supervisor, config}) do
    name = config[:name]

    {:ok, machine} =
      DynamicSupervisor.start_child(
        supervisor,
        {Room.StateMachine, [self(), config, name: :"Room.#{name}.StateMachine"]}
      )

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
       scene_on: "scene.#{name}_high_night",
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

  def handle_info({Room.StateMachine, :register, machine}, state) do
    {:noreply, %{state | machine: machine}}
  end

  def handle_info({Room.StateMachine, :effect, effect}, state) do
    handle_effect(effect, state)
    {:noreply, state}
  end

  def handle_info({_module, pid, event}, state) do
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

  def handle_info({:DOWN, ref, :process, pid, _reason}, state) do
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

  defp handle_effect({:set_lights, on}, state) do
    scene =
      if on do
        state.scene_on
      else
        state.scene_off
      end

    Task.start(fn ->
      {:ok, _} = Hass.call_service(state.hass, :scene, :turn_on, target: %{entity_id: scene})
    end)
  end
end
