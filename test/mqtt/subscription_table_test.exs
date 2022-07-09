defmodule Mqtt.SubscriptionTableTest do
  use ExUnit.Case
  use PropCheck
  import Mqtt.SubscriptionTable
  import Mqtt.Generators
  import Mqtt.Topic.Sigil
  alias Mqtt.Topic, as: Topic
  doctest Mqtt.SubscriptionTable

  property "newly created table has no subscriptions" do
    new_table = new()
    assert Enum.empty?(new_table)

    forall filter <- topic_filter() do
      assert not contains_filter?(new_table, filter)
    end
  end

  property "subscription to concrete topic accepts this topic" do
    forall [old_table <- subscription_table(), topic <- topic(), ref <- int()] do
      new_table = subscribe(old_table, ref, topic)

      old_subs = lookup(old_table, topic)
      new_subs = lookup(new_table, topic)

      assert MapSet.member?(new_subs, ref)
      assert MapSet.subset?(MapSet.difference(new_subs, old_subs), MapSet.new([ref]))
    end
  end

  property "subscription to concrete topic accepts nothing else" do
    forall [old_table <- subscription_table(), topic <- topic(), other <- topic()] do
      implies topic != other do
        ref = make_ref()
        new_table = subscribe(old_table, ref, topic)

        assert lookup(new_table, other) == lookup(old_table, other)
      end
    end
  end

  property "subscription with deep wildcard accepts appropriate topics" do
    forall [
      old_table <- subscription_table(),
      prefix <- topic(:allow_empty),
      postfix <- topic(),
      ref <- int()
    ] do
      filter = Topic.concat([prefix, ~t"#"])
      topic = Topic.concat([prefix, postfix])
      new_table = subscribe(old_table, ref, filter)

      old_subs = lookup(old_table, topic)
      new_subs = lookup(new_table, topic)

      assert MapSet.member?(new_subs, ref)
      assert MapSet.subset?(MapSet.difference(new_subs, old_subs), MapSet.new([ref]))
    end
  end

  property "subscription with deep wildcard accepts nothing else" do
    forall [
      old_table <- subscription_table(),
      prefix <- topic(:allow_empty),
      topic <- topic()
    ] do
      is_match =
        List.starts_with?(Topic.to_list(topic), Topic.to_list(prefix)) and
          length(Topic.to_list(topic)) > length(Topic.to_list(prefix))

      implies not is_match do
        ref = make_ref()
        filter = Topic.concat([prefix, ~t"#"])
        new_table = subscribe(old_table, ref, filter)

        assert lookup(new_table, topic) == lookup(old_table, topic)
      end
    end
  end

  property "subscription with shallow wildcard accepts appropriate topics" do
    forall [
      old_table <- subscription_table(),
      prefix <- topic(:allow_empty),
      mid <- fragment(),
      postfix <- topic(:allow_empty),
      ref <- int()
    ] do
      filter = Topic.concat([prefix, ~t"+", postfix])
      topic = Topic.concat([prefix, Topic.new([mid]), postfix])
      new_table = subscribe(old_table, ref, filter)

      old_subs = lookup(old_table, topic)
      new_subs = lookup(new_table, topic)

      assert MapSet.member?(new_subs, ref)
      assert MapSet.subset?(MapSet.difference(new_subs, old_subs), MapSet.new([ref]))
    end
  end

  property "subscription with shallow wildcard accepts nothing else" do
    forall [
      old_table <- subscription_table(),
      prefix <- topic(:allow_empty),
      postfix <- topic(:allow_empty),
      topic <- topic()
    ] do
      is_match =
        List.starts_with?(Topic.to_list(topic), Topic.to_list(prefix)) and
          Enum.drop(Topic.to_list(topic), length(Topic.to_list(prefix)) + 1) ==
            Topic.to_list(postfix)

      implies not is_match do
        ref = make_ref()
        filter = Topic.concat([prefix, ~t"+", postfix])
        new_table = subscribe(old_table, ref, filter)

        assert lookup(new_table, topic) == lookup(old_table, topic)
      end
    end
  end

  property "unsubscribe is inverse of subscribe" do
    forall [table <- subscription_table(), filter <- topic_filter()] do
      ref = make_ref()
      assert unsubscribe(subscribe(table, ref, filter), ref, filter) == table
    end
  end

  property "unsubscribe does nothing if subscription doesn't exist" do
    forall [table <- subscription_table(), schema <- topic_filter()] do
      ref = make_ref()
      assert unsubscribe(table, ref, schema) == table
    end
  end

  property "subscribed_filters is correct" do
    forall pairs <- list(tuple([int(), topic_filter()])) do
      table = Enum.into(pairs, new())

      filters = for {_, schema} <- pairs, into: MapSet.new(), do: schema
      assert filters == subscribed_filters(table)
    end
  end
end
