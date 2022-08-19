defmodule Room.StateMachineTest do
  use ExUnit.Case
  import Room.StateMachine
  doctest Room.StateMachine

  @recv_timeout 5
  @effect_timeout 10 + @recv_timeout

  setup do
    {:ok, pid} = start_link([self(), [sensor_timeout: @effect_timeout - @recv_timeout]])
    assert_receive({Room.StateMachine, :register, ^pid}, @effect_timeout)
    %{machine: pid}
  end

  defmacro assert_effect(pattern, timeout \\ @recv_timeout, failure_message \\ nil) do
    quote do
      assert_receive(
        {Room.StateMachine, :effect, unquote(pattern)},
        unquote(timeout),
        unquote(failure_message)
      )
    end
  end

  defmacro assert_past_effect(pattern, failure_message \\ nil) do
    quote do
      assert_received(
        {Room.StateMachine, :effect, unquote(pattern)},
        unquote(failure_message)
      )
    end
  end

  defmacro refute_effect(pattern, timeout \\ @recv_timeout, failure_message \\ nil) do
    quote do
      refute_receive(
        {Room.StateMachine, :effect, unquote(pattern)},
        unquote(timeout),
        unquote(failure_message)
      )
    end
  end

  defmacro refute_past_effect(pattern, failure_message \\ nil) do
    quote do
      refute_received(
        {Room.StateMachine, :effect, unquote(pattern)},
        unquote(failure_message)
      )
    end
  end

  describe "event `{:toggle, :click, 1}`:" do
    test "works correctly (and starting state of machine is off)", %{machine: machine} do
      send_event(machine, {:toggle, :click, 1})
      assert_effect({:set_lights, true})

      send_event(machine, {:toggle, :click, 1})
      assert_effect({:set_lights, false})

      send_event(machine, {:toggle, :click, 1})
      assert_effect({:set_lights, true})

      send_event(machine, {:toggle, :click, 1})
      assert_effect({:set_lights, false})
    end
  end

  describe "event `{:toggle, :click, 2}`:" do
    test "turns the lights on ignoring the sensor", %{machine: machine} do
      send_event(machine, {:toggle, :click, 2})
      assert_effect({:set_lights, true})
      refute_effect({:set_lights, false}, @effect_timeout)
    end

    test "turns the sensor off even if lights were already on", %{machine: machine} do
      send_event(machine, {:on, :click, 1})
      assert_effect({:set_lights, true})

      send_event(machine, {:toggle, :click, 2})
      refute_effect({:set_lights, _}, @effect_timeout)
    end

    test "is idempotent", %{machine: machine} do
      send_event(machine, {:toggle, :click, 2})
      assert_effect({:set_lights, true})

      send_event(machine, {:toggle, :click, 2})
      send_event(machine, {:toggle, :click, 2})
      refute_effect({:set_lights, true})
    end
  end

  describe "event `{:toggle, :click, 3}`:" do
    test "turn the lights off but the sensor on", %{machine: machine} do
      send_event(machine, {:on, :click, 2})
      assert_effect({:set_lights, true})

      send_event(machine, {:toggle, :click, 3})
      assert_effect({:set_lights, false})

      send_event(machine, :sensor_active)
      assert_effect({:set_lights, true})
    end

    test "turns the sensor on even if lights were already off", %{machine: machine} do
      send_event(machine, {:toggle, :click, 3})
      refute_effect({:set_lights, false})

      send_event(machine, :sensor_active)
      assert_effect({:set_lights, true})
    end

    test "is idempotent", %{machine: machine} do
      send_event(machine, {:on, :click, 1})
      assert_effect({:set_lights, true})

      send_event(machine, {:toggle, :click, 3})
      assert_effect({:set_lights, false})

      send_event(machine, {:toggle, :click, 3})
      send_event(machine, {:toggle, :click, 3})
      refute_effect({:set_lights, _})

      send_event(machine, :sensor_active)
      assert_effect({:set_lights, true})
    end
  end

  describe "event `{:on, :click, 1}`:" do
    test "turns the lights on and listens to the sensor", %{machine: machine} do
      send_event(machine, {:on, :click, 1})
      assert_effect({:set_lights, true})
      assert_effect({:set_lights, false}, @effect_timeout)
    end

    test "is idempotent", %{machine: machine} do
      send_event(machine, {:on, :click, 1})
      assert_effect({:set_lights, true})

      send_event(machine, {:on, :click, 1})
      send_event(machine, {:on, :click, 1})
      refute_effect({:set_lights, true})
      assert_effect({:set_lights, false}, @effect_timeout)
    end

    test "turns the sensor on even if lights were already on", %{machine: machine} do
      send_event(machine, {:on, :click, 2})
      assert_effect({:set_lights, true})

      send_event(machine, {:on, :click, 1})
      refute_effect({:set_lights, true})
      assert_effect({:set_lights, false}, @effect_timeout)
    end
  end

  describe "event `{:on, :click, 2}`:" do
    test "turns the lights on ignoring the sensor", %{machine: machine} do
      send_event(machine, {:on, :click, 2})
      assert_effect({:set_lights, true})
      refute_effect({:set_lights, false}, @effect_timeout)
    end

    test "turns the sensor off even if lights were already on", %{machine: machine} do
      send_event(machine, {:on, :click, 1})
      assert_effect({:set_lights, true})

      send_event(machine, {:on, :click, 2})
      refute_effect({:set_lights, _}, @effect_timeout)
    end

    test "is idempotent", %{machine: machine} do
      send_event(machine, {:on, :click, 2})
      assert_effect({:set_lights, true})

      send_event(machine, {:on, :click, 2})
      send_event(machine, {:on, :click, 2})
      refute_effect({:set_lights, true})
    end
  end

  describe "event `{:off, click, 1}`:" do
    test "turns the lights off ignoring the sensor", %{machine: machine} do
      send_event(machine, {:on, :click, 1})
      assert_effect({:set_lights, true})

      send_event(machine, {:off, :click, 1})
      assert_effect({:set_lights, false})

      send_event(machine, :sensor_active)
      refute_effect({:set_lights, _})
    end

    test "has no effect on the initial state", %{machine: machine} do
      send_event(machine, {:off, :click, 1})
      send_event(machine, {:off, :click, 1})
      refute_effect({:set_lights, _})
    end

    test "is idempotent", %{machine: machine} do
      send_event(machine, {:on, :click, 1})
      assert_effect({:set_lights, true})

      send_event(machine, {:off, :click, 1})
      assert_effect({:set_lights, false})

      send_event(machine, {:off, :click, 1})
      send_event(machine, {:off, :click, 1})
      refute_effect({:set_lights, _})
    end
  end

  describe "event `{:off, click, 2}`:" do
    test "turn the lights off but the sensor on", %{machine: machine} do
      send_event(machine, {:on, :click, 2})
      assert_effect({:set_lights, true})

      send_event(machine, {:off, :click, 2})
      assert_effect({:set_lights, false})

      send_event(machine, :sensor_active)
      assert_effect({:set_lights, true})
    end

    test "turns the sensor on even if lights were already off", %{machine: machine} do
      send_event(machine, {:off, :click, 2})
      refute_effect({:set_lights, false})

      send_event(machine, :sensor_active)
      assert_effect({:set_lights, true})
    end

    test "is idempotent", %{machine: machine} do
      send_event(machine, {:on, :click, 1})
      assert_effect({:set_lights, true})

      send_event(machine, {:off, :click, 2})
      assert_effect({:set_lights, false})

      send_event(machine, {:off, :click, 2})
      send_event(machine, {:off, :click, 2})
      refute_effect({:set_lights, _})

      send_event(machine, :sensor_active)
      assert_effect({:set_lights, true})
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
      send_event(machine, {:toggle, :click, 1})
      assert_effect({:set_lights, true})
      assert_effect({:set_lights, false}, @effect_timeout)

      send_event(machine, {:toggle, :click, 1})
      assert_effect({:set_lights, true})
      assert_effect({:set_lights, false}, @effect_timeout)

      send_event(machine, :sensor_active)
      assert_effect({:set_lights, true})
      assert_effect({:set_lights, false}, @effect_timeout)
    end

    test "repeated activations of the sensor before the timeout are idempotent", %{
      machine: machine
    } do
      send_event(machine, {:toggle, :click, 1})
      assert_effect({:set_lights, true})
      assert_effect({:set_lights, false}, @effect_timeout)

      send_event(machine, :sensor_active)
      assert_effect({:set_lights, true})

      send_event(machine, :sensor_active)
      send_event(machine, :sensor_active)
      assert_effect({:set_lights, false}, @effect_timeout)
    end
  end

  describe "event `{:turned_on, _, true}`:" do
    test "sets state to sensor-on if it was always-off, commiting the current light states", %{
      machine: machine
    } do
      send_event(machine, {:turned_on, "foo", true})
      assert_effect(:commit_lights)
      assert_effect({:set_lights, false}, @effect_timeout)
      refute_past_effect({:set_lights, true})
    end

    test "sets state to sensor-on if it was sensor-off, committing the current light states", %{
      machine: machine
    } do
      send_event(machine, {:turned_on, "foo", true})
      assert_effect(:commit_lights)
      assert_effect({:set_lights, false}, @effect_timeout)
      refute_past_effect({:set_lights, true})
    end

    test "has no effect if state was always-on", %{machine: machine} do
      send_event(machine, {:on, :click, 2})
      assert_effect({:set_lights, true})

      send_event(machine, {:turned_on, "foo", true})
      refute_effect(_, @effect_timeout)
    end

    test "has no effect if state was sensor-on", %{machine: machine} do
      send_event(machine, {:on, :click, 1})
      assert_effect({:set_lights, true})

      send_event(machine, {:turned_on, "foo", true})
      assert_effect({:set_lights, false}, @effect_timeout)
      refute_past_effect(:commit_lights)
    end
  end

  describe "event `{:turned_on, false}`:" do
    test "has no effect if state was always-off", %{machine: machine} do
      send_event(machine, {:turned_on, "foo", true})
      assert_effect(:commit_lights)
      send_event(machine, {:off, :click, 2})
      assert_effect({:set_lights, false})

      send_event(machine, {:turned_on, "foo", false})
      refute_effect(_, @effect_timeout)
    end

    test "has no effect if state was sensor-off", %{machine: machine} do
      send_event(machine, {:on, :click, 1})
      assert_effect({:set_lights, true})
      send_event(machine, {:turned_on, "foo", true})
      assert_effect({:set_lights, false}, @effect_timeout)

      send_event(machine, {:turned_on, "foo", false})
      refute_effect(_, @effect_timeout)

      send_event(machine, :sensor_active)
      assert_effect({:set_lights, true})
    end

    test "set to always-off without effects if state was always-on and only one light was on", %{
      machine: machine
    } do
      send_event(machine, {:on, :click, 2})
      assert_effect({:set_lights, true})

      send_event(machine, {:turned_on, "foo", true})
      refute_effect(_, @effect_timeout)

      send_event(machine, {:turned_on, "foo", false})
      send_event(machine, :sensor_active)
      refute_effect(_, @effect_timeout)

      send_event(machine, {:toggle, :click, 1})
      assert_effect({:set_lights, true})
    end

    test "set to always-off without effects if state was sensor-on an only one light was on", %{
      machine: machine
    } do
      send_event(machine, {:on, :click, 1})
      assert_effect({:set_lights, true})

      send_event(machine, {:turned_on, "foo", true})

      send_event(machine, {:turned_on, "foo", false})
      send_event(machine, :sensor_active)
      refute_effect(_, @effect_timeout)

      send_event(machine, {:toggle, :click, 1})
      assert_effect({:set_lights, true})
    end

    test "has no effect if state was always-on and two lights were on", %{machine: machine} do
      send_event(machine, {:on, :click, 2})
      assert_effect({:set_lights, true})

      send_event(machine, {:turned_on, "foo", true})
      send_event(machine, {:turned_on, "bar", true})
      refute_effect(_, @effect_timeout)

      send_event(machine, {:turned_on, "foo", false})
      refute_effect(_, @effect_timeout)
    end

    test "has no effect if state was sensor-on and two lights were on", %{machine: machine} do
      send_event(machine, {:on, :click, 1})
      assert_effect({:set_lights, true})

      send_event(machine, {:turned_on, "foo", true})
      send_event(machine, {:turned_on, "bar", true})

      send_event(machine, {:turned_on, "bar", false})
      refute_effect(_)
      assert_effect({:set_lights, false}, @effect_timeout)
    end

    test "set to always-off without effects if state was always-on and the two lights that were on became off",
         %{machine: machine} do
      send_event(machine, {:on, :click, 2})
      assert_effect({:set_lights, true})

      send_event(machine, {:turned_on, "foo", true})
      send_event(machine, {:turned_on, "bar", true})
      refute_effect(_, @effect_timeout)

      send_event(machine, {:turned_on, "foo", false})
      send_event(machine, {:turned_on, "bar", false})
      refute_effect(_, @effect_timeout)

      send_event(machine, {:toggle, :click, 1})
      assert_effect({:set_lights, true})
    end

    test "set to always-off without effects if state was always-on and the two lights were on became off",
         %{machine: machine} do
      send_event(machine, {:on, :click, 1})
      assert_effect({:set_lights, true})

      send_event(machine, {:turned_on, "foo", true})
      send_event(machine, {:turned_on, "bar", true})

      send_event(machine, {:turned_on, "bar", false})
      send_event(machine, {:turned_on, "foo", false})
      refute_effect(_, @effect_timeout)

      send_event(machine, {:toggle, :click, 1})
      assert_effect({:set_lights, true})
    end
  end
end
