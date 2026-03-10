defmodule Bpmn.CompensationIntegrationTest do
  use ExUnit.Case, async: false

  alias Bpmn.{Context, Event.Boundary}

  # Builds a process with:
  # start -> task1 -> task2 -> compensate_throw -> end
  # + compensation boundary on task1 -> comp_handler1
  # + compensation boundary on task2 -> comp_handler2
  defp build_compensation_process(opts \\ []) do
    activity_ref = Keyword.get(opts, :activity_ref, nil)
    wait = Keyword.get(opts, :wait_for_completion, "true")

    compensate_def_attrs =
      %{waitForCompletion: wait, _elems: []}
      |> then(fn attrs ->
        if activity_ref, do: Map.put(attrs, :activityRef, activity_ref), else: attrs
      end)

    %{
      "start" => {:bpmn_event_start, %{id: "start", incoming: [], outgoing: ["f1"]}},
      "f1" =>
        {:bpmn_sequence_flow,
         %{
           id: "f1",
           sourceRef: "start",
           targetRef: "task1",
           conditionExpression: nil,
           isImmediate: nil
         }},
      "task1" =>
        {:bpmn_activity_task_script,
         %{
           id: "task1",
           incoming: ["f1"],
           outgoing: ["f2"],
           type: "elixir",
           script: ~s(data["x"] || 0),
           output_variable: :task1_result
         }},
      "f2" =>
        {:bpmn_sequence_flow,
         %{
           id: "f2",
           sourceRef: "task1",
           targetRef: "task2",
           conditionExpression: nil,
           isImmediate: nil
         }},
      "task2" =>
        {:bpmn_activity_task_script,
         %{
           id: "task2",
           incoming: ["f2"],
           outgoing: ["f3"],
           type: "elixir",
           script: ~s(data["x"] || 0),
           output_variable: :task2_result
         }},
      "f3" =>
        {:bpmn_sequence_flow,
         %{
           id: "f3",
           sourceRef: "task2",
           targetRef: "throw_compensate",
           conditionExpression: nil,
           isImmediate: nil
         }},
      "throw_compensate" =>
        {:bpmn_event_intermediate_throw,
         %{
           id: "throw_compensate",
           incoming: ["f3"],
           outgoing: ["f4"],
           messageEventDefinition: nil,
           signalEventDefinition: nil,
           escalationEventDefinition: nil,
           compensateEventDefinition: {:bpmn_event_definition_compensate, compensate_def_attrs}
         }},
      "f4" =>
        {:bpmn_sequence_flow,
         %{
           id: "f4",
           sourceRef: "throw_compensate",
           targetRef: "end",
           conditionExpression: nil,
           isImmediate: nil
         }},
      "end" => {:bpmn_event_end, %{id: "end", incoming: ["f4"], outgoing: []}},
      # Compensation boundary on task1
      "boundary_comp1" =>
        {:bpmn_event_boundary,
         %{
           id: "boundary_comp1",
           attachedToRef: "task1",
           incoming: [],
           outgoing: ["f_comp1"],
           errorEventDefinition: nil,
           messageEventDefinition: nil,
           signalEventDefinition: nil,
           timerEventDefinition: nil,
           escalationEventDefinition: nil,
           compensateEventDefinition: {:bpmn_event_definition_compensate, %{_elems: []}}
         }},
      "f_comp1" =>
        {:bpmn_sequence_flow,
         %{
           id: "f_comp1",
           sourceRef: "boundary_comp1",
           targetRef: "comp_handler1",
           conditionExpression: nil,
           isImmediate: nil
         }},
      "comp_handler1" =>
        {:bpmn_activity_task_script,
         %{
           id: "comp_handler1",
           incoming: ["f_comp1"],
           outgoing: [],
           type: "elixir",
           script: ~s("task1_compensated"),
           output_variable: :comp1_executed
         }},
      # Compensation boundary on task2
      "boundary_comp2" =>
        {:bpmn_event_boundary,
         %{
           id: "boundary_comp2",
           attachedToRef: "task2",
           incoming: [],
           outgoing: ["f_comp2"],
           errorEventDefinition: nil,
           messageEventDefinition: nil,
           signalEventDefinition: nil,
           timerEventDefinition: nil,
           escalationEventDefinition: nil,
           compensateEventDefinition: {:bpmn_event_definition_compensate, %{_elems: []}}
         }},
      "f_comp2" =>
        {:bpmn_sequence_flow,
         %{
           id: "f_comp2",
           sourceRef: "boundary_comp2",
           targetRef: "comp_handler2",
           conditionExpression: nil,
           isImmediate: nil
         }},
      "comp_handler2" =>
        {:bpmn_activity_task_script,
         %{
           id: "comp_handler2",
           incoming: ["f_comp2"],
           outgoing: [],
           type: "elixir",
           script: ~s("task2_compensated"),
           output_variable: :comp2_executed
         }}
    }
  end

  describe "compensate throw event (all activities)" do
    test "executes compensation handlers in reverse completion order" do
      process = build_compensation_process()
      {:ok, context} = Context.start_link(process, %{})

      start = Map.get(process, "start")
      {:ok, _} = Bpmn.execute(start, context)

      # Both handlers executed
      assert Context.get_data(context, :comp1_executed) == "task1_compensated"
      assert Context.get_data(context, :comp2_executed) == "task2_compensated"

      # Verify execution order via history: comp_handler2 before comp_handler1 (reverse order)
      history = Context.get_history(context)
      comp_entries = Enum.filter(history, &(&1.node_id in ["comp_handler1", "comp_handler2"]))
      comp_order = Enum.map(comp_entries, & &1.node_id)
      assert comp_order == ["comp_handler2", "comp_handler1"]
    end
  end

  describe "compensate throw event with activityRef" do
    test "executes only the targeted activity's handler" do
      process = build_compensation_process(activity_ref: "task1")
      {:ok, context} = Context.start_link(process, %{})

      start = Map.get(process, "start")
      {:ok, _} = Bpmn.execute(start, context)

      assert Context.get_data(context, :comp1_executed) == "task1_compensated"
      assert Context.get_data(context, :comp2_executed) == nil
    end
  end

  describe "compensate end event" do
    test "executes compensation from end event" do
      process = %{
        "start" => {:bpmn_event_start, %{id: "start", incoming: [], outgoing: ["f1"]}},
        "f1" =>
          {:bpmn_sequence_flow,
           %{
             id: "f1",
             sourceRef: "start",
             targetRef: "task1",
             conditionExpression: nil,
             isImmediate: nil
           }},
        "task1" =>
          {:bpmn_activity_task_script,
           %{
             id: "task1",
             incoming: ["f1"],
             outgoing: ["f2"],
             type: "elixir",
             script: "1 + 1",
             output_variable: :task1_result
           }},
        "f2" =>
          {:bpmn_sequence_flow,
           %{
             id: "f2",
             sourceRef: "task1",
             targetRef: "end_comp",
             conditionExpression: nil,
             isImmediate: nil
           }},
        "end_comp" =>
          {:bpmn_event_end,
           %{
             id: "end_comp",
             incoming: ["f2"],
             outgoing: [],
             compensateEventDefinition: {:bpmn_event_definition_compensate, %{_elems: []}}
           }},
        "boundary_comp" =>
          {:bpmn_event_boundary,
           %{
             id: "boundary_comp",
             attachedToRef: "task1",
             incoming: [],
             outgoing: ["f_comp"],
             errorEventDefinition: nil,
             messageEventDefinition: nil,
             signalEventDefinition: nil,
             timerEventDefinition: nil,
             escalationEventDefinition: nil,
             compensateEventDefinition: {:bpmn_event_definition_compensate, %{_elems: []}}
           }},
        "f_comp" =>
          {:bpmn_sequence_flow,
           %{
             id: "f_comp",
             sourceRef: "boundary_comp",
             targetRef: "comp_handler",
             conditionExpression: nil,
             isImmediate: nil
           }},
        "comp_handler" =>
          {:bpmn_activity_task_script,
           %{
             id: "comp_handler",
             incoming: ["f_comp"],
             outgoing: [],
             type: "elixir",
             script: ~s("compensated"),
             output_variable: :comp_result
           }}
      }

      {:ok, context} = Context.start_link(process, %{})
      start = Map.get(process, "start")
      {:ok, _} = Bpmn.execute(start, context)

      assert Context.get_data(context, :comp_result) == "compensated"
    end
  end

  describe "compensation boundary event" do
    test "returns ok without executing (passive registration)" do
      boundary =
        {:bpmn_event_boundary,
         %{
           id: "b1",
           attachedToRef: "task1",
           incoming: [],
           outgoing: ["f1"],
           errorEventDefinition: nil,
           messageEventDefinition: nil,
           signalEventDefinition: nil,
           timerEventDefinition: nil,
           escalationEventDefinition: nil,
           compensateEventDefinition: {:bpmn_event_definition_compensate, %{_elems: []}}
         }}

      {:ok, context} = Context.start_link(%{}, %{})
      assert {:ok, ^context} = Boundary.token_in(boundary, context)
    end
  end
end
