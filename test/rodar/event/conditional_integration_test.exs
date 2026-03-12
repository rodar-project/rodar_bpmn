defmodule RodarBpmn.Event.ConditionalIntegrationTest do
  use ExUnit.Case, async: false

  alias RodarBpmn.{Context, Event.Boundary}

  defp build_conditional_catch_process(condition) do
    start = {:bpmn_event_start, %{id: "start", outgoing: ["f1"], incoming: []}}

    task =
      {:bpmn_activity_task_script,
       %{
         id: "task1",
         incoming: ["f1"],
         outgoing: ["f2"],
         type: "elixir",
         script: ~s(data["x"] || 0),
         output_variable: :task1_result
       }}

    catch_event =
      {:bpmn_event_intermediate_catch,
       %{
         id: "catch1",
         incoming: ["f2"],
         outgoing: ["f3"],
         messageEventDefinition: nil,
         signalEventDefinition: nil,
         timerEventDefinition: nil,
         conditionalEventDefinition:
           {:bpmn_event_definition_conditional, %{condition: condition, _elems: []}}
       }}

    end_event = {:bpmn_event_end, %{id: "end1", incoming: ["f3"], outgoing: []}}

    f1 =
      {:bpmn_sequence_flow,
       %{
         id: "f1",
         sourceRef: "start",
         targetRef: "task1",
         conditionExpression: nil,
         isImmediate: nil
       }}

    f2 =
      {:bpmn_sequence_flow,
       %{
         id: "f2",
         sourceRef: "task1",
         targetRef: "catch1",
         conditionExpression: nil,
         isImmediate: nil
       }}

    f3 =
      {:bpmn_sequence_flow,
       %{
         id: "f3",
         sourceRef: "catch1",
         targetRef: "end1",
         conditionExpression: nil,
         isImmediate: nil
       }}

    %{
      "start" => start,
      "task1" => task,
      "catch1" => catch_event,
      "end1" => end_event,
      "f1" => f1,
      "f2" => f2,
      "f3" => f3
    }
  end

  describe "process with conditional catch event" do
    test "pauses at conditional catch then continues on data change" do
      process = build_conditional_catch_process(~S|data["approved"] == true|)
      {:ok, context} = Context.start_link(process, %{})

      # Execute process — should pause at catch1
      result = RodarBpmn.execute(process["start"], context)
      assert {:manual, task_data} = result
      assert task_data.id == "catch1"
      assert task_data.type == :conditional_catch

      # Verify catch event is active
      meta = Context.get_meta(context, "catch1")
      assert meta.active == true
      assert meta.completed == false

      # Now change data to satisfy condition
      Context.put_data(context, "approved", true)

      # Allow spawned processes to complete
      Process.sleep(100)

      # Catch event should now be completed
      meta = Context.get_meta(context, "catch1")
      assert meta.active == false
      assert meta.completed == true
    end

    test "passes through immediately when condition is already true" do
      process = build_conditional_catch_process(~S|data["approved"] == true|)
      {:ok, context} = Context.start_link(process, %{})

      # Set data before execution
      Context.put_data(context, "approved", true)

      # Execute process — should pass through catch1 immediately
      result = RodarBpmn.execute(process["start"], context)
      assert {:ok, ^context} = result
    end

    test "condition with numeric comparison" do
      process = build_conditional_catch_process(~S|data["count"] == 5|)
      {:ok, context} = Context.start_link(process, %{})
      Context.put_data(context, "count", 0)

      result = RodarBpmn.execute(process["start"], context)
      assert {:manual, _} = result

      # Set count to 3 — still shouldn't trigger
      Context.put_data(context, "count", 3)
      Process.sleep(50)

      meta = Context.get_meta(context, "catch1")
      assert meta.active == true

      # Set count to 5 — should trigger
      Context.put_data(context, "count", 5)
      Process.sleep(100)

      meta = Context.get_meta(context, "catch1")
      assert meta.active == false
      assert meta.completed == true
    end
  end

  describe "boundary conditional on user task" do
    test "fires when condition becomes true" do
      end_event = {:bpmn_event_end, %{id: "end1", incoming: ["f3"], outgoing: []}}
      boundary_end = {:bpmn_event_end, %{id: "end2", incoming: ["f4"], outgoing: []}}

      user_task =
        {:bpmn_activity_task_user, %{id: "user1", incoming: ["f1"], outgoing: ["f3"]}}

      start = {:bpmn_event_start, %{id: "start", outgoing: ["f1"], incoming: []}}

      boundary =
        {:bpmn_event_boundary,
         %{
           id: "b1",
           outgoing: ["f4"],
           attachedToRef: "user1",
           errorEventDefinition: nil,
           messageEventDefinition: nil,
           signalEventDefinition: nil,
           timerEventDefinition: nil,
           escalationEventDefinition: nil,
           compensateEventDefinition: nil,
           conditionalEventDefinition:
             {:bpmn_event_definition_conditional,
              %{condition: ~S|data["escalate"] == true|, _elems: []}}
         }}

      f1 =
        {:bpmn_sequence_flow,
         %{
           id: "f1",
           sourceRef: "start",
           targetRef: "user1",
           conditionExpression: nil,
           isImmediate: nil
         }}

      f3 =
        {:bpmn_sequence_flow,
         %{
           id: "f3",
           sourceRef: "user1",
           targetRef: "end1",
           conditionExpression: nil,
           isImmediate: nil
         }}

      f4 =
        {:bpmn_sequence_flow,
         %{
           id: "f4",
           sourceRef: "b1",
           targetRef: "end2",
           conditionExpression: nil,
           isImmediate: nil
         }}

      process = %{
        "start" => start,
        "user1" => user_task,
        "b1" => boundary,
        "end1" => end_event,
        "end2" => boundary_end,
        "f1" => f1,
        "f3" => f3,
        "f4" => f4
      }

      {:ok, context} = Context.start_link(process, %{})

      # Execute boundary event — should subscribe
      result = Boundary.token_in(boundary, context)
      assert {:manual, task_data} = result
      assert task_data.type == :conditional_boundary

      # Trigger condition
      Context.put_data(context, "escalate", true)
      Process.sleep(100)

      # Boundary should have fired
      meta = Context.get_meta(context, "b1")
      assert meta.active == false
      assert meta.completed == true
    end
  end
end
