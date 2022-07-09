defmodule Mqtt.Generators do
  use PropCheck
  alias Mqtt.Topic, as: Topic
  alias Mqtt.SubscriptionTable, as: Table

  def topic(mode \\ :non_empty) do
    let fragments <- list_with_mode(fragment(), mode) do
      Topic.new(fragments)
    end
  end

  def fragment() do
    utf8()
    # TODO: avoid wildcards?
  end

  @spec topic_filter(:allow_empty | :non_empty) :: :proper_types.type()
  def topic_filter(mode \\ :non_empty) do
    fragment = frequency([{5, utf8()}, {1, exactly(:any)}])

    let [core <- list_with_mode(fragment, mode), any_deep <- float(0.0, 1.0)] do
      Topic.new(
        if any_deep <= 0.1 do
          core ++ [:any_deep]
        else
          core
        end
      )
    end
  end

  def subscription_table() do
    let items <- list(tuple([int(), topic_filter()])) do
      for {subscriber, filter} <- items, reduce: Table.new() do
        table -> Table.subscribe(table, subscriber, filter)
      end
    end
  end

  defp list_with_mode(element, :allow_empty), do: list(element)
  defp list_with_mode(element, :non_empty), do: non_empty(list(element))
end
