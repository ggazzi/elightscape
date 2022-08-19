defmodule Room.Light do
  use GenServer
  require Logger

  ## Client API

  def start([hass, controller, entity_id | opts]) do
    GenServer.start(__MODULE__, {hass, controller, entity_id}, opts)
  end

  def start_link([hass, controller, entity_id | opts]) do
    GenServer.start_link(__MODULE__, {hass, controller, entity_id}, opts)
  end

  def set_on(light, on?) do
    GenServer.cast(light, {:set_on, on?})
  end

  def commit_if_temporarily_off(light) do
    GenServer.cast(light, :commit_if_temporarily_off)
  end

  ## GenServer Callbacks

  @type status :: :on | :temporarily_off | :off
  defstruct [:hass, :controller, :sub_id, :entity_id, status: :off]

  @impl true
  def init({hass, controller, entity_id}) do
    # We use a task here so that the gun/HTTP client process doesn't couple to this process
    {:ok, state} = Task.await(Task.async(fn -> Hass.get_state("light.#{entity_id}") end))

    {:ok, sub_id} =
      Hass.subscribe_trigger(hass, %{platform: :state, entity_id: "light.#{entity_id}", from: nil})

    send(controller, {__MODULE__, :register, self()})

    {:ok,
     update_state_from_hass(
       state,
       %__MODULE__{hass: hass, controller: controller, sub_id: sub_id, entity_id: entity_id}
     )}
  end

  @impl true
  def handle_cast({:set_on, on?}, state) do
    new_status =
      case {on?, state.status} do
        {_, :off} -> :off
        {true, _} -> :on
        {false, _} -> :temporarily_off
      end

    new_state = %{state | status: new_status}

    if on?(new_status) == on?(state.status) do
      notify_hass(new_state)
    end

    {:noreply, new_state}
  end

  def handle_cast(:commit_if_temporarily_off, state) do
    case state.status do
      :temporarily_off ->
        new_state = %{state | status: :off}
        notify_room_controller(new_state)
        {:noreply, new_state}

      _ ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:hass, id, {:trigger, %{"to_state" => raw_state}}}, state)
      when id == state.sub_id do
    {:noreply, update_state_from_hass(raw_state, state)}
  end

  defp update_state_from_hass(%{"state" => raw_status}, state) do
    new_status =
      case {raw_status, state.status} do
        {"on", _} -> :on
        {"off", :temporarily_off} -> :temporarily_off
        {"off", _} -> :off
      end

    new_state = %{state | status: new_status}

    if permanently_off?(new_status) != permanently_off?(state.status) do
      notify_room_controller(new_state)
    end

    new_state
  end

  defp permanently_off?(status) do
    case status do
      :on -> false
      :temporarily_off -> false
      :off -> true
    end
  end

  defp on?(status) do
    case status do
      :on -> true
      :temporarily_off -> false
      :off -> false
    end
  end

  defp notify_room_controller(state) do
    send(
      state.controller,
      {__MODULE__, state.entity_id, :turned_on, not permanently_off?(state.status)}
    )
  end

  defp notify_hass(state) do
    if on?(state.status) do
      Hass.call_service(state.hass, :light, :turn_on,
        target: %{entity_id: "light.#{state.entity_id}"}
      )
    else
      Hass.call_service(state.hass, :light, :turn_off,
        target: %{entity_id: "light.#{state.entity_id}"}
      )
    end
  end
end
