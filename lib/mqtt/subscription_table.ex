defmodule Mqtt.SubscriptionTable do
  defstruct exact: [], any_deep: [], children: %{}

  @type t :: %__MODULE__{
          exact: list(pid),
          any_deep: list(pid),
          children: %{(String.t() | :any) => t}
        }

  @type fragment :: String.t() | :any | :any_deep
  @type topic_schema :: nonempty_list(fragment)
  @type topic :: nonempty_list(String.t())

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
  @spec lookup(t, topic) :: list(pid)
  def lookup(table, topic) do
    List.flatten(lookup_rec([], table, topic))
  end

  defp lookup_rec(acc, table, []) do
    [table.exact, acc]
  end

  defp lookup_rec(acc, table, [curr | rest]) do
    acc = [table.any_deep, acc]

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

  @spec subscribe(t, pid, topic_schema) :: t
  def subscribe(table, subscriber, []) do
    %{table | exact: [subscriber | table.exact]}
  end

  def subscribe(table, subscriber, [:any_deep]) do
    %{table | any_deep: [subscriber | table.any_deep]}
  end

  def subscribe(table, subscriber, [curr | rest]) when curr != :any_deep do
    subtable = subscribe(Map.get(table.children, curr, new()), subscriber, rest)
    %{table | children: Map.put(table.children, curr, subtable)}
  end

  @spec unsubscribe(t, pid, topic_schema) :: t
  def unsubscribe(table, subscriber, []) do
    %{table | exact: Enum.filter(table.exact, fn x -> x != subscriber end)}
  end

  def unsubscribe(table, subscriber, [:any_deep]) do
    %{table | any_deep: Enum.filter(table.any_deep, fn x -> x != subscriber end)}
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
end

defimpl Collectable, for: Mqtt.SubscriptionTable do
  import Mqtt.SubscriptionTable

  def into(table) do
    collector_fun = fn
      table_acc, {:cont, {subscriber, schema}} ->
        subscribe(table_acc, subscriber, schema)

      table_acc, :done ->
        table_acc

      _table_acc, :halt ->
        :ok
    end

    {table, collector_fun}
  end
end

defimpl Enumerable, for: Mqtt.SubscriptionTable do
  def count(_table) do
    {:error, __MODULE__}
  end

  def slice(_table) do
    {:error, __MODULE__}
  end

  def member?(table, {subscriber, schema}) do
    {:ok, member?(table, subscriber, schema)}
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
    reduce_table({nil, [], [{[], table}]}, acc, fun)
  end

  defp reduce_table(_state, {:halt, acc}, _fun) do
    {:halted, acc}
  end

  defp reduce_table(state, {:suspend, acc}, fun) do
    {:suspended, acc, &reduce_table(state, &1, fun)}
  end

  defp reduce_table({schema, [subscriber | exact], any_deep, tables}, {:cont, acc}, fun) do
    reduce_table({schema, exact, any_deep, tables}, fun.({subscriber, schema}, acc), fun)
  end

  defp reduce_table({schema, [], any_deep, tables}, acc, fun) do
    reduce_table({schema ++ [:any_deep], any_deep, tables}, acc, fun)
  end

  defp reduce_table({schema, [subscriber | any_deep], tables}, {:cont, acc}, fun) do
    reduce_table({schema, [], any_deep, tables}, fun.({subscriber, schema}, acc), fun)
  end

  defp reduce_table({_schema, [], [{prefix, table} | tables]}, acc, fun) do
    subtables =
      for {fragment, subtable} <- table.children do
        {prefix ++ [fragment], subtable}
      end

    reduce_table({prefix, table.exact, table.any_deep, subtables ++ tables}, acc, fun)
  end

  defp reduce_table({_schema, [], []}, {:cont, acc}, _fun) do
    {:done, acc}
  end
end
