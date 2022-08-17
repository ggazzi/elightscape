defmodule InputDriver.Mqtt do
  @moduledoc """
  A behaviour module for implementing input drivers based on a single MQTT topic.
  """

  @callback init_inner([...]) :: inner_state when inner_state: any

  @type handle_payload_result(inner_state) ::
          {:noreply, inner_state}
          | {:noreply, inner_state, :timeout | :hibernate | {:continue, any}}
          | {:stop, reason :: any, inner_state}

  @callback handle_payload(payload, state(inner_state)) :: handle_payload_result(inner_state)
            when payload: any, inner_state: any

  @spec start(atom, [
          {:debug, [:log | :statistics | :trace | {any, any}]}
          | {:hibernate_after, :infinity | non_neg_integer}
          | {:name, atom | {:global, any} | {:via, atom, any}}
          | {:spawn_opt, [:link | :monitor | {any, any}]}
          | {:timeout, :infinity | non_neg_integer}
        ]) :: :ignore | {:error, any} | {:ok, pid}
  def start(module, opts) do
    GenServer.start(
      module,
      {opts[:mqtt], opts[:subscriber], opts[:handler], opts[:topic], opts},
      opts
    )
  end

  def start_link(module, opts) do
    GenServer.start_link(
      module,
      {opts[:mqtt], opts[:subscriber], opts[:handler], opts[:topic], opts},
      opts
    )
  end

  @spec child_spec(atom, [...]) :: Supervisor.child_spec()
  def child_spec(module, opts) do
    %{
      id: {module, opts[:topic]},
      start: {module, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 500
    }
  end

  defstruct [:subscriber, :topic, :mqtt, :inner]

  @type state(inner_state) :: %__MODULE__{
          subscriber: pid,
          topic: String.t(),
          mqtt: pid,
          inner: inner_state
        }

  defmacro __using__(args) do
    payload_type = Keyword.get(args, :payload_type, :json)

    quote location: :keep do
      @behaviour InputDriver.Mqtt
      @behaviour :gen_server

      def init({mqtt, subscriber, handler, topic, opts}) do
        case Mqtt.subscribe(mqtt, topic) do
          :ok ->
            ref = Process.monitor(mqtt)
            {:ok, inner_state} = init_inner(opts)

            send(subscriber, {InputDriver, self(), :register, handler})

            {:ok,
             %InputDriver.Mqtt{
               subscriber: subscriber,
               topic: topic,
               mqtt: mqtt,
               inner: inner_state
             }}
        end
      end

      def handle_info({:mqtt, topic, payload}, state) do
        result =
          handle_payload(
            unquote(
              case payload_type do
                :string -> quote do: payload
                :json -> quote do: JSON.decode!(payload)
              end
            ),
            state
          )

        InputDriver.Mqtt.payload_result_inner_to_full_state(result, state)
      end

      def handle_info({:DOWN, _ref, :process, pid, reason}, state) when pid == state.mqtt do
        {:stop, {:mqtt_down, reason}, state}
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

      defoverridable handle_call: 3, handle_cast: 2, code_change: 3
    end
  end

  @spec payload_result_inner_to_full_state(handle_payload_result(inner_state), state(inner_state)) ::
          handle_payload_result(state(inner_state))
        when inner_state: any
  def payload_result_inner_to_full_state({:noreply, inner_state}, state) do
    {:noreply, %{state | inner: inner_state}}
  end

  def payload_result_inner_to_full_state(
        {:noreply, inner_state, timeout_hibernate_or_continue},
        state
      ) do
    {:noreply, %{state | inner: inner_state}, timeout_hibernate_or_continue}
  end

  def payload_result_inner_to_full_state({:stop, reason, inner_state}, state) do
    {:stop, reason, %{state | inner: inner_state}}
  end
end
