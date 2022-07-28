defmodule InputDriver.MqttButtons do
  @moduledoc """
  A behaviour module for implementing input drivers for MQTT-based remote controls.
  """

  @callback decode_action(String.t()) :: {term, :click | :hold | :release} | :release

  defmacro __using__(args) do
    click_cooldown = Macro.escape(Keyword.get(args, :click_cooldown, 500))

    quote location: :keep do
      require Logger

      @behaviour InputDriver.MqttButtons
      @behaviour :gen_server

      @click_cooldown unquote(click_cooldown)

      @doc false
      def init({mqtt, subscriber, entity_id}) do
        # FIXME: remove hardcoded MQTT topic prefix
        topic = "zigbee/#{entity_id}/action"

        case Mqtt.subscribe(mqtt, topic) do
          :ok ->
            ref = Process.monitor(mqtt)

            {:ok,
             %{
               curr_held: nil,
               curr_click: nil,
               topic: topic,
               subscriber: subscriber,
               mqtt: {ref, mqtt}
             }}

          {:error, reason} ->
            {:stop, reason}
        end
      end

      @doc false
      def handle_info(
            {:mqtt, topic, payload},
            %{curr_held: curr_held, curr_click: curr_click} = state
          )
          when topic == state.topic do
        case decode_action(payload) do
          {button, :hold} = action when curr_held == nil ->
            send_action(state, action)
            {:noreply, %{state | curr_held: button, curr_click: nil}}

          {^curr_held, :release} = action ->
            send_action(state, action)
            {:noreply, %{state | curr_held: nil, curr_click: nil}}

          :release when curr_held != nil ->
            send_action(state, {curr_held, :release})
            {:noreply, %{state | curr_held: nil, curr_click: nil}}

          {button, :click} ->
            case curr_click do
              nil ->
                {:noreply, %{state | curr_click: {button, 1}}, @click_cooldown}

              {^button, n} ->
                {:noreply, %{state | curr_click: {button, n + 1}}, @click_cooldown}

              {other_button, n} ->
                send_action(state, {other_button, :click, n})
                {:noreply, %{state | curr_click: {button, 1}}, @click_cooldown}
            end
        end
      end

      def handle_info(:timeout, %{curr_click: curr_click} = state) do
        case curr_click do
          {button, n} -> send_action(state, {button, :click, n})
          nil -> nil
        end

        {:noreply, %{state | curr_click: nil}}
      end

      def handle_info({:DOWN, ref, :process, _which, reason}, state)
          when ref == elem(state.mqtt, 0) do
        {:stop, {:mqtt_down, reason}, state}
      end

      @doc false
      def terminate(reason, %{curr_held: curr_held, curr_click: curr_click} = state) do
        case curr_click do
          {button, n} ->
            send_action(state, {button, :click, n})

          nil ->
            nil
        end

        if curr_held != nil do
          send_action(state, {curr_held, :release})
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

      defoverridable init: 1, handle_call: 3, handle_info: 2, terminate: 2, code_change: 3

      defp send_action(%{subscriber: subscriber}, action) do
        send(subscriber, {__MODULE__, self(), action})
      end
    end
  end
end
