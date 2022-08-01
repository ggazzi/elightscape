defmodule Room.StateMachineTest do
  use ExUnit.Case
  import Room.StateMachine
  doctest Room.StateMachine

  @effect_timeout 10
  @effect_timeout_margin 5
  @recv_timeout 3

  setup do
    effect_timeout = @effect_timeout - @effect_timeout_margin
    {:ok, pid} = start_link([self(), [sensor_timeout: effect_timeout]])
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
end
