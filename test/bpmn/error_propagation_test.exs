defmodule Bpmn.ErrorPropagationTest do
  use ExUnit.Case, async: true

  alias Bpmn.{Activity.Subprocess.Embedded, Context}

  describe "subprocess with attached error boundary event" do
    test "routes to boundary event outgoing flows on subprocess error" do
      # Nested subprocess that will fail (no start event → error)
      nested = %{
        "sub_end" => {:bpmn_event_end, %{id: "sub_end", incoming: [], outgoing: []}}
      }

      # Boundary error event attached to the subprocess
      boundary =
        {:bpmn_event_boundary,
         %{
           id: "boundary_1",
           attachedToRef: "sub",
           outgoing: ["error_flow"],
           errorEventDefinition: {:bpmn_event_definition_error, %{_elems: []}},
           messageEventDefinition: nil,
           signalEventDefinition: nil,
           timerEventDefinition: nil,
           escalationEventDefinition: nil
         }}

      error_end = {:bpmn_event_end, %{id: "error_end", incoming: ["error_flow"], outgoing: []}}

      error_flow =
        {:bpmn_sequence_flow,
         %{
           id: "error_flow",
           sourceRef: "boundary_1",
           targetRef: "error_end",
           conditionExpression: nil,
           isImmediate: nil
         }}

      normal_end =
        {:bpmn_event_end, %{id: "normal_end", incoming: ["normal_flow"], outgoing: []}}

      normal_flow =
        {:bpmn_sequence_flow,
         %{
           id: "normal_flow",
           sourceRef: "sub",
           targetRef: "normal_end",
           conditionExpression: nil,
           isImmediate: nil
         }}

      process = %{
        "boundary_1" => boundary,
        "error_end" => error_end,
        "error_flow" => error_flow,
        "normal_end" => normal_end,
        "normal_flow" => normal_flow
      }

      {:ok, context} = Context.start_link(process, %{})

      elem =
        {:bpmn_activity_subprocess_embeded,
         %{id: "sub", outgoing: ["normal_flow"], elements: nested}}

      # Should route through boundary event's outgoing flows instead of returning error
      assert {:ok, ^context} =
               Embedded.token_in(elem, context)

      # Subprocess should be marked as errored
      meta = Context.get_meta(context, "sub")
      assert meta.error == true
      assert meta.completed == false
    end

    test "returns error when no matching boundary event exists" do
      nested = %{
        "sub_end" => {:bpmn_event_end, %{id: "sub_end", incoming: [], outgoing: []}}
      }

      normal_end =
        {:bpmn_event_end, %{id: "normal_end", incoming: ["normal_flow"], outgoing: []}}

      normal_flow =
        {:bpmn_sequence_flow,
         %{
           id: "normal_flow",
           sourceRef: "sub",
           targetRef: "normal_end",
           conditionExpression: nil,
           isImmediate: nil
         }}

      process = %{
        "normal_end" => normal_end,
        "normal_flow" => normal_flow
      }

      {:ok, context} = Context.start_link(process, %{})

      elem =
        {:bpmn_activity_subprocess_embeded,
         %{id: "sub", outgoing: ["normal_flow"], elements: nested}}

      # No boundary event → error propagates upward
      assert {:error, _} = Embedded.token_in(elem, context)
    end

    test "ignores non-error boundary events" do
      nested = %{
        "sub_end" => {:bpmn_event_end, %{id: "sub_end", incoming: [], outgoing: []}}
      }

      # Boundary event with timer definition (not error)
      boundary =
        {:bpmn_event_boundary,
         %{
           id: "boundary_1",
           attachedToRef: "sub",
           outgoing: ["timer_flow"],
           errorEventDefinition: nil,
           timerEventDefinition: {:bpmn_event_definition_timer, %{_elems: []}},
           messageEventDefinition: nil,
           signalEventDefinition: nil,
           escalationEventDefinition: nil
         }}

      process = %{
        "boundary_1" => boundary
      }

      {:ok, context} = Context.start_link(process, %{})

      elem =
        {:bpmn_activity_subprocess_embeded,
         %{id: "sub", outgoing: ["normal_flow"], elements: nested}}

      # Timer boundary should not catch errors
      assert {:error, _} = Embedded.token_in(elem, context)
    end
  end
end
