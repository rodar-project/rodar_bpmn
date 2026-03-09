defmodule Bpmn.Event.EndTest do
  use ExUnit.Case, async: true

  describe "plain end event" do
    test "returns {:ok, context} for a plain end event" do
      {:ok, context} = Bpmn.Context.start_link(%{}, %{})
      end_event = {:bpmn_event_end, %{id: "end_1", incoming: ["flow_1"], outgoing: []}}

      assert {:ok, ^context} = Bpmn.Event.End.token_in(end_event, context)
    end

    test "returns {:ok, context} when event definition fields are nil" do
      {:ok, context} = Bpmn.Context.start_link(%{}, %{})

      end_event =
        {:bpmn_event_end,
         %{
           id: "end_1",
           incoming: ["flow_1"],
           outgoing: [],
           errorEventDefinition: nil,
           terminateEventDefinition: nil
         }}

      assert {:ok, ^context} = Bpmn.Event.End.token_in(end_event, context)
    end
  end

  describe "error end event" do
    test "returns {:error, error_ref} and stores error in context" do
      {:ok, context} = Bpmn.Context.start_link(%{}, %{})

      end_event =
        {:bpmn_event_end,
         %{
           id: "end_err",
           incoming: ["flow_1"],
           errorEventDefinition: {:bpmn_event_definition_error, %{errorRef: "Error_001"}}
         }}

      assert {:error, "Error_001"} = Bpmn.Event.End.token_in(end_event, context)
      assert Bpmn.Context.get_meta(context, :error) == "Error_001"
    end
  end

  describe "terminate end event" do
    test "returns {:ok, context} and marks process as terminated" do
      {:ok, context} = Bpmn.Context.start_link(%{}, %{})

      end_event =
        {:bpmn_event_end,
         %{
           id: "end_term",
           incoming: ["flow_1"],
           terminateEventDefinition: %{}
         }}

      assert {:ok, ^context} = Bpmn.Event.End.token_in(end_event, context)
      assert Bpmn.Context.get_meta(context, :terminated) == true
    end
  end
end
