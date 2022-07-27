defmodule Room.StateMachineTest do
  use ExUnit.Case
  import Room.StateMachine
  doctest Room.StateMachine

  @sensor_timeout 6
  @recv_timeout 1

  setup do
    {:ok, pid} = start_link([self(), [sensor_timeout: @sensor_timeout - 2]])
    %{machine: pid}
  end

  defmacro assert_effect(pattern, timeout \\ @recv_timeout, failure_message \\ nil) do
    quote do
      assert_receive(
        {Room.StateMachine, unquote(pattern)},
        unquote(timeout),
        unquote(failure_message)
      )
    end
  end

  defmacro refute_effect(pattern, timeout \\ @recv_timeout, failure_message \\ nil) do
    quote do
      refute_receive(
        {Room.StateMachine, unquote(pattern)},
        unquote(timeout),
        unquote(failure_message)
      )
    end
  end

  describe "event `:toggle`:" do
    test "works correctly (and starting state of machine is off)", %{machine: machine} do
      send_event(machine, {:toggle, :click})
      assert_effect({:set_lights, true})

      send_event(machine, {:toggle, :click})
      assert_effect({:set_lights, false})

      send_event(machine, {:toggle, :click})
      assert_effect({:set_lights, true})

      send_event(machine, {:toggle, :click})
      assert_effect({:set_lights, false})
    end
  end

  describe "event `:on`:" do
    test "turns the machine on and listens to the sensor", %{machine: machine} do
      send_event(machine, {:on, :click})
      assert_effect({:set_lights, true})
      assert_effect({:set_lights, false}, @sensor_timeout)
    end
  end

  describe "event `:off`:" do
    test "turns the machine off ignoring the sensor", %{machine: machine} do
      send_event(machine, {:on, :click})
      assert_effect({:set_lights, true})

      send_event(machine, {:off, :click})
      assert_effect({:set_lights, false})

      send_event(machine, :sensor_active)
      refute_effect({:set_lights, _})
    end

    test "has no effect on the initial state", %{machine: machine} do
      send_event(machine, {:off, :click})
      send_event(machine, {:off, :click})
      refute_effect({:set_lights, _})
    end

    test "is idempotent", %{machine: machine} do
      send_event(machine, {:on, :click})
      assert_effect({:set_lights, true})

      send_event(machine, {:off, :click})
      assert_effect({:set_lights, false})

      send_event(machine, {:off, :click})
      send_event(machine, {:off, :click})
      refute_effect({:set_lights, _})
    end
  end

  describe "sensor and its timeout:" do
    test "machine starts off and not listening to sensor", %{machine: machine} do
      send_event(machine, :sensor_active)
      refute_effect({:set_lights, _})
    end

    test "lights are turned off after timeout and back on when the sensor is active", %{
      machine: machine
    } do
      send_event(machine, {:toggle, :click})
      assert_effect({:set_lights, true})
      assert_effect({:set_lights, false}, @sensor_timeout)

      send_event(machine, {:toggle, :click})
      assert_effect({:set_lights, true})
      assert_effect({:set_lights, false}, @sensor_timeout)

      send_event(machine, :sensor_active)
      assert_effect({:set_lights, true})
      assert_effect({:set_lights, false}, @sensor_timeout)
    end
  end
end
