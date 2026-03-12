defmodule Rodar.Event.CorrelationTest do
  use ExUnit.Case, async: false

  alias Rodar.{
    Context,
    Event.Boundary,
    Event.Bus,
    Event.Intermediate.Catch,
    Event.Intermediate.Throw
  }

  describe "intermediate catch event with correlationKey" do
    test "subscribes with correlation metadata from context data" do
      {:ok, context} = Context.start_link(%{}, %{})
      Context.put_data(context, "order_id", "ORD-42")

      elem =
        {:bpmn_event_intermediate_catch,
         %{
           id: "catch1",
           outgoing: ["flow_out"],
           messageEventDefinition:
             {:bpmn_event_definition_message,
              %{messageRef: "payment_confirmed", correlationKey: "order_id"}},
           signalEventDefinition: nil,
           timerEventDefinition: nil
         }}

      {:manual, task_data} = Catch.token_in(elem, context)
      assert task_data.type == :message_catch

      subs = Bus.subscriptions(:message, "payment_confirmed")
      assert length(subs) == 1
      sub = hd(subs)
      assert sub.correlation == %{key: "order_id", value: "ORD-42"}
    end
  end

  describe "boundary event with correlationKey" do
    test "subscribes with correlation metadata from context data" do
      {:ok, context} = Context.start_link(%{}, %{})
      Context.put_data(context, "order_id", "ORD-99")

      elem =
        {:bpmn_event_boundary,
         %{
           id: "boundary1",
           outgoing: ["flow_b"],
           attachedToRef: "task1",
           messageEventDefinition:
             {:bpmn_event_definition_message,
              %{messageRef: "cancel_order", correlationKey: "order_id"}},
           errorEventDefinition: nil,
           signalEventDefinition: nil,
           timerEventDefinition: nil,
           escalationEventDefinition: nil,
           conditionalEventDefinition: nil,
           compensateEventDefinition: nil
         }}

      {:manual, _} = Boundary.token_in(elem, context)

      subs = Bus.subscriptions(:message, "cancel_order")
      assert length(subs) == 1
      assert hd(subs).correlation == %{key: "order_id", value: "ORD-99"}
    end
  end

  describe "end-to-end correlation routing" do
    test "two instances waiting for same message, routed by correlation" do
      {:ok, ctx1} = Context.start_link(%{}, %{"order_id" => "ORD-1"})
      {:ok, ctx2} = Context.start_link(%{}, %{"order_id" => "ORD-2"})

      msg_name = "payment_#{:erlang.unique_integer()}"

      # Both subscribe with different correlation values
      Bus.subscribe(:message, msg_name, %{
        context: ctx1,
        node_id: "catch_1",
        outgoing: ["f1"],
        correlation: %{key: "order_id", value: "ORD-1"}
      })

      Bus.subscribe(:message, msg_name, %{
        context: ctx2,
        node_id: "catch_2",
        outgoing: ["f2"],
        correlation: %{key: "order_id", value: "ORD-2"}
      })

      # Publish targeting ORD-1
      assert :ok =
               Bus.publish(:message, msg_name, %{
                 data: "paid",
                 correlation: %{key: "order_id", value: "ORD-1"}
               })

      # ctx1 should receive, ctx2 should still be subscribed
      subs = Bus.subscriptions(:message, msg_name)
      assert length(subs) == 1
      assert hd(subs).node_id == "catch_2"

      # Now publish targeting ORD-2
      assert :ok =
               Bus.publish(:message, msg_name, %{
                 data: "paid",
                 correlation: %{key: "order_id", value: "ORD-2"}
               })

      assert Bus.subscriptions(:message, msg_name) == []
    end
  end

  describe "intermediate throw event with correlationKey" do
    test "publishes with correlation from context data" do
      msg_name = "notify_#{:erlang.unique_integer()}"

      # Set up a subscriber to capture the published message
      Bus.subscribe(:message, msg_name, %{node_id: "receiver"})

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
      Context.put_data(context, "order_id", "ORD-77")

      elem =
        {:bpmn_event_intermediate_throw,
         %{
           id: "throw1",
           outgoing: ["flow_out"],
           messageEventDefinition:
             {:bpmn_event_definition_message, %{messageRef: msg_name, correlationKey: "order_id"}},
           signalEventDefinition: nil,
           escalationEventDefinition: nil
         }}

      {:ok, _} = Throw.token_in(elem, context)

      assert_receive {:bpmn_event, :message, ^msg_name, payload, %{node_id: "receiver"}}
      assert payload.correlation == %{key: "order_id", value: "ORD-77"}
    end
  end
end
