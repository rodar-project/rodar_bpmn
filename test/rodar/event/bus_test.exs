defmodule Rodar.Event.BusTest do
  use ExUnit.Case, async: true

  alias Rodar.Event.Bus

  describe "subscribe/3 and unsubscribe/2" do
    test "subscribes and returns event key" do
      {:ok, key} = Bus.subscribe(:message, "test_sub_#{:erlang.unique_integer()}")
      assert {type, _name} = key
      assert type == :message
    end

    test "unsubscribe removes subscription" do
      name = "test_unsub_#{:erlang.unique_integer()}"
      Bus.subscribe(:message, name, %{node_id: "n1"})
      assert length(Bus.subscriptions(:message, name)) == 1

      Bus.unsubscribe(:message, name)
      assert Bus.subscriptions(:message, name) == []
    end
  end

  describe "publish/3 with :message type" do
    test "delivers to first subscriber and unregisters it" do
      name = "msg_#{:erlang.unique_integer()}"
      Bus.subscribe(:message, name, %{node_id: "n1"})

      assert :ok = Bus.publish(:message, name, %{data: "hello"})
      assert_receive {:bpmn_event, :message, ^name, %{data: "hello"}, %{node_id: "n1"}}

      # Subscriber should be removed after delivery
      assert Bus.subscriptions(:message, name) == []
    end

    test "returns error when no subscriber exists" do
      assert {:error, :no_subscriber} =
               Bus.publish(:message, "no_such_#{:erlang.unique_integer()}", %{})
    end
  end

  describe "publish/3 with :signal type" do
    test "broadcasts to all subscribers" do
      name = "sig_#{:erlang.unique_integer()}"
      Bus.subscribe(:signal, name, %{node_id: "n1"})

      # Spawn another subscriber
      parent = self()

      spawn(fn ->
        Bus.subscribe(:signal, name, %{node_id: "n2"})
        send(parent, :subscribed)

        receive do
          msg -> send(parent, {:child_received, msg})
        end
      end)

      receive do
        :subscribed -> :ok
      end

      assert :ok = Bus.publish(:signal, name, %{data: "broadcast"})
      assert_receive {:bpmn_event, :signal, ^name, %{data: "broadcast"}, %{node_id: "n1"}}
      assert_receive {:child_received, {:bpmn_event, :signal, ^name, _, %{node_id: "n2"}}}
    end

    test "returns ok even with no subscribers" do
      assert :ok = Bus.publish(:signal, "no_such_#{:erlang.unique_integer()}", %{})
    end
  end

  describe "publish/3 with :escalation type" do
    test "broadcasts to all subscribers" do
      name = "esc_#{:erlang.unique_integer()}"
      Bus.subscribe(:escalation, name, %{node_id: "n1"})

      assert :ok = Bus.publish(:escalation, name, %{code: "E1"})
      assert_receive {:bpmn_event, :escalation, ^name, %{code: "E1"}, %{node_id: "n1"}}
    end
  end

  describe "publish/3 with :message type and correlation" do
    test "matches correct subscriber among multiple by correlation key" do
      name = "corr_msg_#{:erlang.unique_integer()}"

      # Subscribe both from current process with different correlation values
      Bus.subscribe(:message, name, %{
        node_id: "n1",
        correlation: %{key: "order_id", value: "ORD-1"}
      })

      Bus.subscribe(:message, name, %{
        node_id: "n2",
        correlation: %{key: "order_id", value: "ORD-2"}
      })

      # Publish with ORD-2 correlation — should reach subscriber 2 only
      assert :ok =
               Bus.publish(:message, name, %{
                 data: "payment",
                 correlation: %{key: "order_id", value: "ORD-2"}
               })

      assert_receive {:bpmn_event, :message, ^name, %{data: "payment"}, %{node_id: "n2"}}

      # Subscriber 1 should still be registered
      subs = Bus.subscriptions(:message, name)
      assert length(subs) == 1
      assert hd(subs).node_id == "n1"
    end

    test "falls back to uncorrelated subscriber when no correlation match" do
      name = "corr_fallback_#{:erlang.unique_integer()}"

      # Uncorrelated subscriber (current process)
      Bus.subscribe(:message, name, %{node_id: "uncorr"})

      # Publish with correlation that doesn't match anyone
      assert :ok =
               Bus.publish(:message, name, %{
                 data: "hello",
                 correlation: %{key: "order_id", value: "ORD-999"}
               })

      assert_receive {:bpmn_event, :message, ^name, _, %{node_id: "uncorr"}}
    end

    test "returns error when correlation specified but no match and no uncorrelated" do
      name = "corr_nomatch_#{:erlang.unique_integer()}"
      parent = self()

      # Only a correlated subscriber with different value
      spawn(fn ->
        Bus.subscribe(:message, name, %{
          node_id: "n1",
          correlation: %{key: "order_id", value: "ORD-1"}
        })

        send(parent, :ready)
        Process.sleep(:infinity)
      end)

      receive do: (:ready -> :ok)

      assert {:error, :no_subscriber} =
               Bus.publish(:message, name, %{
                 correlation: %{key: "order_id", value: "ORD-999"}
               })
    end

    test "backward compat: publish without correlation picks first subscriber" do
      name = "corr_compat_#{:erlang.unique_integer()}"

      Bus.subscribe(:message, name, %{node_id: "first"})

      assert :ok = Bus.publish(:message, name, %{data: "no_corr"})
      assert_receive {:bpmn_event, :message, ^name, %{data: "no_corr"}, %{node_id: "first"}}
    end

    test "mixed correlated and uncorrelated subscribers" do
      name = "corr_mixed_#{:erlang.unique_integer()}"

      # Correlated subscriber
      Bus.subscribe(:message, name, %{
        node_id: "corr",
        correlation: %{key: "id", value: "A"}
      })

      # Uncorrelated subscriber
      Bus.subscribe(:message, name, %{node_id: "uncorr"})

      # Publish with matching correlation — should go to correlated subscriber
      assert :ok =
               Bus.publish(:message, name, %{
                 correlation: %{key: "id", value: "A"}
               })

      assert_receive {:bpmn_event, :message, ^name, _, %{node_id: "corr"}}

      # Uncorrelated should still be there
      subs = Bus.subscriptions(:message, name)
      assert length(subs) == 1
      assert hd(subs).node_id == "uncorr"
    end
  end

  describe "subscriptions/2" do
    test "lists current subscribers" do
      name = "list_#{:erlang.unique_integer()}"
      Bus.subscribe(:message, name, %{node_id: "n1"})

      subs = Bus.subscriptions(:message, name)
      assert length(subs) == 1
      assert hd(subs).node_id == "n1"
    end

    test "returns empty list for no subscribers" do
      assert Bus.subscriptions(:message, "empty_#{:erlang.unique_integer()}") == []
    end
  end
end
