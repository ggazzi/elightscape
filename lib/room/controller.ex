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

    for {:input, {module, handler, opts}} <- config do
      DynamicSupervisor.start_child(
        supervisor,
        {module,
         [hass: hass, mqtt: mqtt, subscriber: self(), handler: prepare_handler(handler)] ++ opts}
      )
    end

    {:ok,
     %{
       machine: machine,
       input_drivers: %{},
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

  def handle_info(
        {InputDriver, pid, :register, handler},
        %{input_drivers: input_drivers} = state
      ) do
    # No need to store the ref: we'll never stop monitoring while process is alive
    Process.monitor(pid)
    input_drivers = Map.put(input_drivers, pid, handler)
    {:noreply, %{state | input_drivers: input_drivers}}
  end

  def handle_info({Room.StateMachine, :register, machine}, state) do
    {:noreply, %{state | machine: machine}}
  end

  def handle_info({Room.StateMachine, :effect, effect}, state) do
    handle_effect(effect, state)
    {:noreply, state}
  end

  def handle_info({InputDriver, pid, event}, state) do
    case state.input_drivers[pid] do
      nil ->
        Logger.warn(fn -> "[#{inspect(pid)}] unknown input driver #{inspect(event)}" end)
        {:noreply, state}

      handler ->
        message = handler.(event)
        Room.StateMachine.send_event(state.machine, message)
        Logger.info(fn -> "[#{inspect(pid)}] #{inspect(message)}" end)
        Logger.debug(fn -> "[#{inspect(pid)}] #{inspect(event)}" end)
        {:noreply, state}
    end
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, %{input_drivers: input_drivers} = state) do
    {:noreply, %{state | input_drivers: Map.delete(input_drivers, pid)}}
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
