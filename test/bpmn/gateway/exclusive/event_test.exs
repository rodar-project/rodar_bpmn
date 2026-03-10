defmodule Bpmn.Gateway.Exclusive.EventTest do
  use ExUnit.Case, async: true

  alias Bpmn.{Context, Gateway.Exclusive.Event}

  describe "event-based gateway" do
    test "returns manual with catch event info" do
      catch1 =
        {:bpmn_event_intermediate_catch,
         %{
           id: "catch1",
           outgoing: ["f_end"],
           messageEventDefinition: {:bpmn_event_definition_message, %{messageRef: "msg1"}},
           signalEventDefinition: nil,
           timerEventDefinition: nil
         }}

      f1 =
        {:bpmn_sequence_flow,
         %{
           id: "f1",
           sourceRef: "egw",
           targetRef: "catch1",
           conditionExpression: nil,
           isImmediate: nil
         }}

      f2 =
        {:bpmn_sequence_flow,
         %{
           id: "f2",
           sourceRef: "egw",
           targetRef: "catch2",
           conditionExpression: nil,
           isImmediate: nil
         }}

      catch2 =
        {:bpmn_event_intermediate_catch,
         %{
           id: "catch2",
           outgoing: ["f_end"],
           signalEventDefinition: {:bpmn_event_definition_signal, %{signalRef: "sig1"}},
           messageEventDefinition: nil,
           timerEventDefinition: nil
         }}

      process = %{"f1" => f1, "f2" => f2, "catch1" => catch1, "catch2" => catch2}
      {:ok, context} = Context.start_link(process, %{})

      elem = {:bpmn_gateway_exclusive_event, %{id: "egw", outgoing: ["f1", "f2"]}}
      assert {:manual, task_data} = Event.token_in(elem, context)
      assert task_data.id == "egw"
      assert task_data.type == :event_gateway
      assert length(task_data.catch_events) == 2
    end

    test "dispatches via Bpmn.execute/2" do
      {:ok, context} = Context.start_link(%{}, %{})
      elem = {:bpmn_gateway_exclusive_event, %{id: "egw", outgoing: []}}
      assert {:manual, _} = Bpmn.execute(elem, context)
    end
  end
end
