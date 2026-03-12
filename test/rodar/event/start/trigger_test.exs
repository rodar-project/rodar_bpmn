defmodule RodarBpmn.Event.Start.TriggerTest do
  use ExUnit.Case, async: false

  alias RodarBpmn.Event.Bus
  alias RodarBpmn.Event.Start.Trigger

  setup do
    # Clean up any triggers from previous tests
    for trigger <- Trigger.list() do
      Trigger.unregister(trigger.process_id)
    end

    :ok
  end

  defp register_message_start_process(process_id, message_name) do
    elements = %{
      "start" =>
        {:bpmn_event_start,
         %{
           id: "start",
           outgoing: ["f1"],
           incoming: [],
           messageEventDefinition: {:bpmn_event_definition_message, %{messageRef: message_name}},
           signalEventDefinition: nil
         }},
      "f1" =>
        {:bpmn_sequence_flow,
         %{id: "f1", sourceRef: "start", targetRef: "end", conditionExpression: nil}},
      "end" => {:bpmn_event_end, %{id: "end", incoming: ["f1"], outgoing: []}}
    }

    process = {:bpmn_process, %{id: process_id}, elements}
    RodarBpmn.Registry.register(process_id, process)
    process
  end

  defp register_signal_start_process(process_id, signal_name) do
    elements = %{
      "start" =>
        {:bpmn_event_start,
         %{
           id: "start",
           outgoing: ["f1"],
           incoming: [],
           messageEventDefinition: nil,
           signalEventDefinition: {:bpmn_event_definition_signal, %{signalRef: signal_name}}
         }},
      "f1" =>
        {:bpmn_sequence_flow,
         %{id: "f1", sourceRef: "start", targetRef: "end", conditionExpression: nil}},
      "end" => {:bpmn_event_end, %{id: "end", incoming: ["f1"], outgoing: []}}
    }

    process = {:bpmn_process, %{id: process_id}, elements}
    RodarBpmn.Registry.register(process_id, process)
    process
  end

  describe "register/1" do
    test "registers a message-triggered start event" do
      msg_name = "msg_trigger_#{:erlang.unique_integer([:positive])}"
      register_message_start_process("msg-proc", msg_name)

      assert {:ok, subscriptions} = Trigger.register("msg-proc")
      assert length(subscriptions) == 1
      assert hd(subscriptions).event_type == :message
      assert hd(subscriptions).event_name == msg_name
    end

    test "registers a signal-triggered start event" do
      sig_name = "sig_trigger_#{:erlang.unique_integer([:positive])}"
      register_signal_start_process("sig-proc", sig_name)

      assert {:ok, subscriptions} = Trigger.register("sig-proc")
      assert length(subscriptions) == 1
      assert hd(subscriptions).event_type == :signal
      assert hd(subscriptions).event_name == sig_name
    end

    test "returns error for unknown process" do
      assert {:error, msg} = Trigger.register("nonexistent")
      assert msg =~ "not found"
    end

    test "returns empty list for process without triggers" do
      elements = %{
        "start" => {:bpmn_event_start, %{id: "start", outgoing: ["f1"], incoming: []}},
        "f1" =>
          {:bpmn_sequence_flow,
           %{id: "f1", sourceRef: "start", targetRef: "end", conditionExpression: nil}},
        "end" => {:bpmn_event_end, %{id: "end", incoming: ["f1"], outgoing: []}}
      }

      RodarBpmn.Registry.register("plain-proc", {:bpmn_process, %{id: "plain-proc"}, elements})

      assert {:ok, []} = Trigger.register("plain-proc")
    end
  end

  describe "unregister/1" do
    test "removes trigger subscriptions" do
      msg_name = "msg_unreg_#{:erlang.unique_integer([:positive])}"
      register_message_start_process("unreg-proc", msg_name)
      Trigger.register("unreg-proc")

      assert length(Trigger.list()) == 1
      assert :ok = Trigger.unregister("unreg-proc")
      assert Trigger.list() == []
    end
  end

  describe "list/0" do
    test "lists all registered triggers" do
      msg_name = "msg_list_#{:erlang.unique_integer([:positive])}"
      sig_name = "sig_list_#{:erlang.unique_integer([:positive])}"
      register_message_start_process("list-msg", msg_name)
      register_signal_start_process("list-sig", sig_name)

      Trigger.register("list-msg")
      Trigger.register("list-sig")

      triggers = Trigger.list()
      assert length(triggers) == 2
      process_ids = Enum.map(triggers, & &1.process_id)
      assert "list-msg" in process_ids
      assert "list-sig" in process_ids
    end
  end

  describe "auto-instantiation" do
    test "message event creates a new process instance" do
      msg_name = "msg_auto_#{:erlang.unique_integer([:positive])}"
      register_message_start_process("auto-msg-proc", msg_name)
      Trigger.register("auto-msg-proc")

      # Count instances before
      before_count = length(RodarBpmn.Observability.running_instances())

      Bus.publish(:message, msg_name, %{data: %{"order_id" => "123"}})

      # Give spawned process time to create and run
      Process.sleep(200)

      after_count = length(RodarBpmn.Observability.running_instances())
      assert after_count > before_count
    end

    test "signal event creates a new process instance" do
      sig_name = "sig_auto_#{:erlang.unique_integer([:positive])}"
      register_signal_start_process("auto-sig-proc", sig_name)
      Trigger.register("auto-sig-proc")

      before_count = length(RodarBpmn.Observability.running_instances())

      Bus.publish(:signal, sig_name, %{data: %{"alert" => "warning"}})

      Process.sleep(200)

      after_count = length(RodarBpmn.Observability.running_instances())
      assert after_count > before_count
    end
  end
end
