defmodule Bpmn.Event.Intermediate.ThrowTest do
  use ExUnit.Case, async: true

  alias Bpmn.{Context, Event.Bus, Event.Intermediate.Throw}

  setup do
    end_event = {:bpmn_event_end, %{id: "end", incoming: ["flow_out"], outgoing: []}}

    flow_out =
      {:bpmn_sequence_flow,
       %{
         id: "flow_out",
         sourceRef: "throw1",
         targetRef: "end",
         conditionExpression: nil,
         isImmediate: nil
       }}

    process = %{"flow_out" => flow_out, "end" => end_event}
    {:ok, context} = Context.start_link(process, %{})
    %{context: context}
  end

  describe "none throw event (pass-through)" do
    test "releases token to outgoing flows", %{context: context} do
      elem =
        {:bpmn_event_intermediate_throw,
         %{
           id: "throw1",
           outgoing: ["flow_out"],
           messageEventDefinition: nil,
           signalEventDefinition: nil,
           escalationEventDefinition: nil
         }}

      assert {:ok, ^context} = Throw.token_in(elem, context)
    end
  end

  describe "message throw event" do
    test "publishes message to event bus and releases token", %{context: context} do
      msg_name = "msg_throw_#{:erlang.unique_integer()}"

      # Subscribe to receive the message
      Bus.subscribe(:message, msg_name, %{node_id: "receiver"})

      elem =
        {:bpmn_event_intermediate_throw,
         %{
           id: "throw1",
           outgoing: ["flow_out"],
           messageEventDefinition: {:bpmn_event_definition_message, %{messageRef: msg_name}},
           signalEventDefinition: nil,
           escalationEventDefinition: nil
         }}

      assert {:ok, ^context} = Throw.token_in(elem, context)
      assert_receive {:bpmn_event, :message, ^msg_name, _, _}
    end
  end

  describe "signal throw event" do
    test "publishes signal to event bus and releases token", %{context: context} do
      sig_name = "sig_throw_#{:erlang.unique_integer()}"

      Bus.subscribe(:signal, sig_name, %{node_id: "receiver"})

      elem =
        {:bpmn_event_intermediate_throw,
         %{
           id: "throw1",
           outgoing: ["flow_out"],
           messageEventDefinition: nil,
           signalEventDefinition: {:bpmn_event_definition_signal, %{signalRef: sig_name}},
           escalationEventDefinition: nil
         }}

      assert {:ok, ^context} = Throw.token_in(elem, context)
      assert_receive {:bpmn_event, :signal, ^sig_name, _, _}
    end
  end

  describe "escalation throw event" do
    test "publishes escalation to event bus and releases token", %{context: context} do
      esc_code = "esc_throw_#{:erlang.unique_integer()}"

      Bus.subscribe(:escalation, esc_code, %{node_id: "receiver"})

      elem =
        {:bpmn_event_intermediate_throw,
         %{
           id: "throw1",
           outgoing: ["flow_out"],
           messageEventDefinition: nil,
           signalEventDefinition: nil,
           escalationEventDefinition:
             {:bpmn_event_definition_escalation, %{escalationRef: esc_code}}
         }}

      assert {:ok, ^context} = Throw.token_in(elem, context)
      assert_receive {:bpmn_event, :escalation, ^esc_code, _, _}
    end
  end

  describe "dispatch via Bpmn.execute/2" do
    test "dispatches intermediate throw events correctly", %{context: context} do
      elem =
        {:bpmn_event_intermediate_throw,
         %{
           id: "throw1",
           outgoing: ["flow_out"],
           messageEventDefinition: nil,
           signalEventDefinition: nil,
           escalationEventDefinition: nil
         }}

      assert {:ok, ^context} = Bpmn.execute(elem, context)
    end
  end
end
