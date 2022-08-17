defmodule InputDriver.MqttButtons do
  @moduledoc """
  A behaviour module for implementing input drivers for MQTT-based remote controls.
  """
  require Logger

  @type action :: {term, :click | :hold | :release} | :release
  @callback decode_action(String.t()) :: action

  defdelegate start(module, opts), to: InputDriver.Mqtt
  defdelegate start_link(module, opts), to: InputDriver.Mqtt
  defdelegate child_spec(module, opts), to: InputDriver.Mqtt

  defstruct curr_held: nil, curr_click: nil

  @type inner_state :: %__MODULE__{
          curr_held: nil | term,
          curr_click: nil | term
        }
  @type state :: InputDriver.Mqtt.state(inner_state)

  defmacro __using__(args) do
    click_cooldown = Macro.escape(Keyword.get(args, :click_cooldown, 500))
    fire_click_immediately = Macro.escape(Keyword.get(args, :fire_click_immediately, true))

    quote location: :keep do
      require Logger
      @behaviour InputDriver.MqttButtons

      import InputDriver.Mqtt
      InputDriver.Mqtt.__using__(unquote(Macro.escape(args)))

      @click_cooldown unquote(click_cooldown)

      @doc false
      def init_inner(_opts) do
        {:ok, %InputDriver.MqttButtons{curr_held: nil, curr_click: nil}}
      end

      @doc false
      def handle_payload(payload, state) do
        InputDriver.MqttButtons.handle_action(
          decode_action(payload),
          state,
          unquote(fire_click_immediately),
          @click_cooldown
        )
      end

      def handle_info(:timeout, state) do
        unquote(
          if fire_click_immediately do
            quote do: {:noreply, %{state | curr_click: nil}}
          else
            quote do
              case state.inner.curr_click do
                {button, n} -> InputDriver.MqttButtons.send_action(state, {button, :click, n})
                nil -> nil
              end

              {:noreply, %{state | inner: %{state.inner | curr_click: nil}}}
            end
          end
        )
      end

      def handle_info({:DOWN, ref, :process, _which, reason}, state)
          when ref == elem(state.mqtt, 0) do
        {:stop, {:mqtt_down, reason}, state}
      end

      @doc false
      def terminate(reason, %{inner: %{curr_held: curr_held, curr_click: curr_click}} = state) do
        case curr_click do
          {button, n} ->
            InputDriver.MqttButtons.send_action(state, {button, :click, n})

          nil ->
            nil
        end

        if curr_held != nil do
          InputDriver.MqttButtons.send_action(state, {curr_held, :release})
        end

        {:stop, reason}
      end

      @doc false
      def handle_call(msg, _from, state) do
        # We do this to trick dialyzer to not complain about non-local returns.
        reason = {:bad_call, msg}

        case :erlang.phash2(1, 1) do
          0 -> exit(reason)
          1 -> {:stop, reason, state}
        end
      end

      @doc false
      def handle_cast(msg, state) do
        # We do this to trick dialyzer to not complain about non-local returns.
        reason = {:bad_cast, msg}

        case :erlang.phash2(1, 1) do
          0 -> exit(reason)
          1 -> {:stop, reason, state}
        end
      end

      @doc false
      def code_change(_old, state, _extra) do
        {:ok, state}
      end

      defoverridable handle_call: 3,
                     handle_cast: 2,
                     code_change: 3
    end
  end

  @spec handle_action(action, state, boolean(), non_neg_integer()) ::
          InputDriver.Mqtt.handle_payload_result(inner_state)
  def handle_action({button, :hold} = action, state, _fire_click_immediately, _click_cooldown)
      when state.inner.curr_held == nil do
    send_action(state, action)
    {:noreply, %{state.inner | curr_held: button, curr_click: nil}}
  end

  def handle_action({button, :release} = action, state, _fire_click_immediately, _click_cooldown)
      when button == state.inner.curr_held do
    send_action(state, action)
    {:noreply, %{state.inner | curr_held: nil, curr_click: nil}}
  end

  def handle_action(:release, state, _fire_click_immediately, _click_cooldown) do
    if state.inner.curr_held == nil do
      Logger.warn("received :release when no button is curr_held")
      {:noreply, state}
    else
      send_action(state, {state.inner.curr_held, :release})
      {:noreply, %{state.inner | curr_held: nil, curr_click: nil}}
    end
  end

  def handle_action({button, :click}, state, true, click_cooldown) do
    num_clicks =
      case state.inner.curr_click do
        nil -> 1
        {^button, num_clicks} -> num_clicks + 1
        {_other_button, _} -> 1
      end

    send_action(state, {button, :click, num_clicks})
    {:noreply, %{state.inner | curr_click: {button, num_clicks}}, click_cooldown}
  end

  def handle_action({button, :click}, state, false, click_cooldown) do
    case state.inner.curr_click do
      nil ->
        {:noreply, %{state.inner | curr_click: {button, 1}}, click_cooldown}

      {^button, num_clicks} ->
        {:noreply, %{state.inner | curr_click: {button, num_clicks + 1}}, click_cooldown}

      {other_button, num_clicks} ->
        send_action(state, {other_button, :click, num_clicks})
        {:noreply, %{state.inner | curr_click: {button, 1}}, click_cooldown}
    end
  end

  def send_action(%{subscriber: subscriber}, action) do
    send(subscriber, {InputDriver, self(), action})
  end
end
