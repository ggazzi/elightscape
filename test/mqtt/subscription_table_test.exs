defmodule Mqtt.SubscriptionTableTest do
  use ExUnit.Case
  use PropCheck
  import Mqtt.SubscriptionTable
  doctest Mqtt.SubscriptionTable

  property "newly created table has no subscriptions" do
    new_table = new()

    forall topic <- topic() do
      assert lookup(new_table, topic) == []
    end
  end

  property "subscription to concrete topic accepts this topic" do
    forall [old_table <- table(), topic <- non_empty(topic()), ref <- int()] do
      new_table = subscribe(old_table, ref, topic)

      old_subs = lookup(old_table, topic)
      new_subs = lookup(new_table, topic)

      assert Enum.member?(new_subs, ref)
      assert List.delete(new_subs, ref) == old_subs
    end
  end

  property "subscription to concrete topic accepts nothing else" do
    forall [old_table <- table(), topic <- non_empty(topic()), other <- non_empty(topic())] do
      implies topic != other do
        ref = make_ref()
        new_table = subscribe(old_table, ref, topic)

        assert lookup(new_table, other) == lookup(old_table, other)
      end
    end
  end

  property "subscription with deep wildcard accepts appropriate topics" do
    forall [
      old_table <- table(),
      prefix <- topic(),
      postfix <- non_empty(topic()),
      ref <- int()
    ] do
      schema = prefix ++ [:any_deep]
      topic = prefix ++ postfix
      new_table = subscribe(old_table, ref, schema)

      old_subs = lookup(old_table, topic)
      new_subs = lookup(new_table, topic)

      assert Enum.member?(new_subs, ref)
      assert List.delete(new_subs, ref) == old_subs
    end
  end

  property "subscription with deep wildcard accepts nothing else" do
    forall [
      old_table <- table(),
      prefix <- topic(),
      topic <- non_empty(topic())
    ] do
      is_match = List.starts_with?(topic, prefix) and length(topic) > length(prefix)

      implies not is_match do
        ref = make_ref()
        schema = prefix ++ [:any_deep]
        new_table = subscribe(old_table, ref, schema)

        assert lookup(new_table, topic) == lookup(old_table, topic)
      end
    end
  end

  property "subscription with shallow wildcard accepts appropriate topics" do
    forall [
      old_table <- table(),
      prefix <- topic(),
      mid <- utf8(),
      postfix <- topic(),
      ref <- int()
    ] do
      schema = prefix ++ [:any | postfix]
      topic = prefix ++ [mid | postfix]
      new_table = subscribe(old_table, ref, schema)

      old_subs = lookup(old_table, topic)
      new_subs = lookup(new_table, topic)

      assert Enum.member?(new_subs, ref)
      assert List.delete(new_subs, ref) == old_subs
    end
  end

  property "subscription with shallow wildcard accepts nothing else" do
    forall [
      old_table <- table(),
      prefix <- topic(),
      postfix <- topic(),
      topic <- non_empty(topic())
    ] do
      is_match =
        List.starts_with?(topic, prefix) and Enum.drop(topic, length(prefix) + 1) == postfix

      implies not is_match do
        ref = make_ref()
        schema = prefix ++ [:any | postfix]
        new_table = subscribe(old_table, ref, schema)

        assert lookup(new_table, topic) == lookup(old_table, topic)
      end
    end
  end

  property "unsubscribe is inverse of subscribe" do
    forall [table <- table(), schema <- non_empty(topic_schema())] do
      ref = make_ref()
      assert unsubscribe(subscribe(table, ref, schema), ref, schema) == table
    end
  end

  property "unsubscribe does nothing if subscription doesn't exist" do
    forall [table <- table(), schema <- non_empty(topic_schema())] do
      ref = make_ref()
      assert unsubscribe(table, ref, schema) == table
    end
  end

  property "turning a table into a list produces the subscription pairs" do
    forall pairs <- list(tuple([int(), non_empty(topic_schema())])) do
      table = Enum.into(pairs, new())

      assert Enum.sort(pairs) == Enum.sort(table)
    end
  end

  def topic() do
    list(utf8())
  end

  def topic_schema() do
    fragment = frequency([{5, utf8()}, {1, exactly(:any)}])

    let [core <- list(fragment), any_deep <- float(0.0, 1.0)] do
      if any_deep <= 0.1 do
        core ++ [:any_deep]
      else
        core
      end
    end
  end

  def table() do
    let items <- list(tuple([int(), topic_schema()])) do
      for {subscriber, schema} <- items, reduce: new() do
        table -> subscribe(table, subscriber, schema)
      end
    end
  end
end
