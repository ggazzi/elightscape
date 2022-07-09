defmodule Mqtt.Topic do
  @moduledoc ~S"""
  A structured representation of MQTT topics.

  The module [`Mqtt.Topic.Sigil`] provides a useful sigil,
  see the examples for its usage.

  This module does __not__ validate the topics!
  It is up to the user to ensure that wildcards are used properly.

  ## Examples

    iex> Mqtt.Topic.to_list(~t"foo/bar/baz")
    ["foo", "bar", "baz"]

    iex> Mqtt.Topic.to_list(~t"foo/bar/")
    ["foo", "bar", ""]

    iex> Mqtt.Topic.to_list(~t"+/bar/#")
    [:any, "bar", :any_deep]

    iex> Mqtt.Topic.concat([~t"foo/+", ~t"bar/#"])
    ~t"foo/+/bar/#"
  """

  defstruct fragments: []

  @typedoc """
  A utility type that can represent both concrete topics as well as topic filters.
  """
  @type gen(frag) :: %__MODULE__{fragments: list(frag)}

  @typedoc """
  Type for concrete topics, which don't contain wildcards
  """
  @type t :: gen(fragment)
  @type fragment :: String.t()

  @typedoc """
  Type for topic filters, which may contain deep and shallow wildcards.

  Note that deep wildcards are only allowed as the last item.
  """
  @type filter :: gen(filter_fragment)
  @type filter_fragment :: fragment | :any | :any_deep

  @spec parse(String.t()) :: filter
  def parse(string) do
    new(
      for fragment <- String.split(string, ~r"/") do
        case fragment do
          "#" -> :any_deep
          "+" -> :any
          _ -> fragment
        end
      end
    )
  end

  @spec concat(list(gen(frag))) :: gen(frag) when frag: any
  def concat(topics) do
    new(List.flatten(for %{fragments: frags} <- topics, do: frags))
  end

  @spec new(list(frag)) :: gen(frag) when frag: any
  def new(fragments) do
    %__MODULE__{fragments: fragments}
  end

  @spec to_list(gen(frag)) :: list(frag) when frag: any
  def to_list(%{fragments: fragments}) do
    fragments
  end

  @spec to_string(t) :: String.t()
  def to_string(%{fragments: fragments}) do
    fragments |> Stream.map(&fragment_to_string/1) |> Enum.join("/")
  end

  @spec fragment_to_string(fragment) :: String.t()
  defp fragment_to_string(:any), do: "+"
  defp fragment_to_string(:any_deep), do: "#"
  defp fragment_to_string(fragment), do: fragment

  defmodule Sigil do
    def sigil_t(string, []) do
      Mqtt.Topic.parse(string)
    end
  end

  defimpl Inspect do
    import Inspect.Algebra

    def inspect(topic, opts) do
      concat(["~t", to_doc(Mqtt.Topic.to_string(topic), opts)])
    end
  end
end
