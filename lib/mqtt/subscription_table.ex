defmodule Mqtt.SubscriptionTable do
  defstruct exact: MapSet.new(), any_deep: MapSet.new(), children: %{}
  alias Mqtt.Topic, as: Topic

  @type t :: %__MODULE__{
          exact: MapSet.t(pid),
          any_deep: MapSet.t(pid),
          children: %{(String.t() | :any) => t}
        }

  # @type topic_schema :: nonempty_list(Topic.filter_fragment())
  # @type topic :: nonempty_list(Topic.fragment())

  @doc """
  Empty subscription table
  """
  @spec new :: Mqtt.SubscriptionTable.t()
  def new() do
    %__MODULE__{}
  end

  @doc """
  Find all subscribers for the given concrete topic.
  """
  def lookup(table, %{fragments: topic}) do
    lookup_rec(MapSet.new(), table, topic)
  end

  def lookup(table, topic) when is_binary(topic) do
    lookup(table, Topic.parse(topic))
  end

  def lookup(table, topic) do
    lookup_rec(MapSet.new(), table, topic)
  end

  defp lookup_rec(acc, table, []) do
    MapSet.union(table.exact, acc)
  end

  defp lookup_rec(acc, table, [curr | rest]) do
    acc = MapSet.union(table.any_deep, acc)

    case {table.children[:any], table.children[curr]} do
      {nil, nil} ->
        acc

      {subtable, nil} ->
        lookup_rec(acc, subtable, rest)

      {nil, subtable} ->
        lookup_rec(acc, subtable, rest)

      {subtable_1, subtable_2} ->
        acc = lookup_rec(acc, subtable_1, rest)
        lookup_rec(acc, subtable_2, rest)
    end
  end

  def subscribe(table, subscriber, %{fragments: filter}) do
    subscribe(table, subscriber, filter)
  end

  def subscribe(table, subscriber, []) do
    %{table | exact: MapSet.put(table.exact, subscriber)}
  end

  def subscribe(table, subscriber, [:any_deep]) do
    %{table | any_deep: MapSet.put(table.any_deep, subscriber)}
  end

  def subscribe(table, subscriber, [curr | rest]) when curr != :any_deep do
    subtable = subscribe(Map.get(table.children, curr, new()), subscriber, rest)
    %{table | children: Map.put(table.children, curr, subtable)}
  end

  def subscribe(table, subscriber, filter) when is_binary(filter) do
    subscribe(table, subscriber, Topic.parse(filter))
  end

  def contains_filter?(table, %{fragments: filter}) do
    contains_filter?(table, filter)
  end

  def contains_filter?(table, []) do
    not Enum.empty?(table.exact)
  end

  def contains_filter?(table, [:any_deep]) do
    not Enum.empty?(table.any_deep)
  end

  def contains_filter?(table, [curr | rest]) when curr != :any_deep do
    case table.children[curr] do
      nil ->
        false

      subtable ->
        contains_filter?(subtable, rest)
    end
  end

  def contains_filter(table, filter) when is_binary(filter) do
    contains_filter?(table, Topic.parse(filter))
  end

  @spec subscribed_filters(t) :: MapSet.t(Schema.t())
  def subscribed_filters(table) do
    subscribed_filters(MapSet.new(), [], table)
  end

  def subscribed_filters(filters, prefix, table) do
    filters =
      unless Enum.empty?(table.exact) do
        MapSet.put(filters, Topic.new(prefix))
      else
        filters
      end

    filters =
      unless Enum.empty?(table.any_deep) do
        MapSet.put(filters, Topic.new(prefix ++ [:any_deep]))
      else
        filters
      end

    for {fragment, subtable} <- table.children, reduce: filters do
      filters -> subscribed_filters(filters, prefix ++ [fragment], subtable)
    end
  end

  def unsubscribe(table, subscriber, %{fragments: filter}) do
    unsubscribe(table, subscriber, filter)
  end

  def unsubscribe(table, subscriber, []) do
    %{table | exact: MapSet.delete(table.exact, subscriber)}
  end

  def unsubscribe(table, subscriber, [:any_deep]) do
    %{table | any_deep: MapSet.delete(table.any_deep, subscriber)}
  end

  def unsubscribe(table, subscriber, [fragment | rest]) do
    subtable =
      case Map.get(table.children, fragment) do
        nil -> nil
        subtable -> unsubscribe(subtable, subscriber, rest)
      end

    cond do
      subtable == nil ->
        table

      Enum.empty?(subtable) ->
        %{table | children: Map.delete(table.children, fragment)}

      true ->
        %{table | children: %{table.children | fragment => subtable}}
    end
  end

  def unsubscribe(table, subscriber, filter) when is_binary(filter) do
    unsubscribe(table, subscriber, Topic.parse(filter))
  end

  defimpl Collectable do
    def into(table) do
      collector_fun = fn
        table_acc, {:cont, {subscriber, filter}} ->
          Mqtt.SubscriptionTable.subscribe(table_acc, subscriber, filter)

        table_acc, :done ->
          table_acc

        _table_acc, :halt ->
          :ok
      end

      {table, collector_fun}
    end
  end

  defimpl Inspect do
    import Inspect.Algebra

    def inspect(table, opts) do
      contents =
        table
        |> Stream.map(fn {filter, subscribers} ->
          concat([to_doc(filter, opts), " => ", to_doc(subscribers, opts)])
        end)
        |> Enum.intersperse(concat([",", break()]))

      group(
        concat([
          "#Mqtt.SubscriptionTable<",
          nest(concat([break("") | contents] ++ [break("")]), 2),
          ">"
        ])
      )
    end
  end

  defimpl Enumerable do
    def count(_table) do
      {:error, __MODULE__}
    end

    def slice(_table) do
      {:error, __MODULE__}
    end

    def member?(table, {subscriber, %{fragments: filter}}) do
      {:ok, member?(table, subscriber, filter)}
    end

    defp member?(table, subscriber, []) do
      Enum.member?(table.exact, subscriber)
    end

    defp member?(table, subscriber, [:any_deep]) do
      Enum.member?(table.any_deep, subscriber)
    end

    defp member?(table, subscriber, [fragment | rest]) do
      case table.chidren[fragment] do
        nil -> false
        subtable -> member?(subtable, subscriber, rest)
      end
    end

    def reduce(table, acc, fun) do
      reduce_table({[{[], table}]}, acc, fun)
    end

    defp reduce_table(_state, {:halt, acc}, _fun) do
      {:halted, acc}
    end

    defp reduce_table(state, {:suspend, acc}, fun) do
      {:suspended, acc, &reduce_table(state, &1, fun)}
    end

    defp reduce_table({[]}, {:cont, acc}, _fun) do
      {:done, acc}
    end

    defp reduce_table({[{filter, table} | tables]}, {:cont, acc}, fun) do
      subtables = for {fragment, subtable} <- table.children, do: {filter ++ [fragment], subtable}

      reduce_table({filter, table.exact, table.any_deep, subtables ++ tables}, {:cont, acc}, fun)
    end

    defp reduce_table({filter, exact, any_deep, tables}, {:cont, acc}, fun) do
      acc =
        unless Enum.empty?(exact),
          do: fun.({Topic.new(filter), exact}, acc),
          else: {:cont, acc}

      reduce_table({filter, any_deep, tables}, acc, fun)
    end

    defp reduce_table({filter, any_deep, tables}, {:cont, acc}, fun) do
      acc =
        unless Enum.empty?(any_deep),
          do: fun.({Topic.new(filter ++ [:any_deep]), any_deep}, acc),
          else: {:cont, acc}

      reduce_table({tables}, acc, fun)
    end
  end
end
