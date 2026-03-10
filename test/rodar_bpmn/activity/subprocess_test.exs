defmodule RodarBpmn.Activity.SubprocessTest do
  use ExUnit.Case, async: true

  alias RodarBpmn.{Activity.Subprocess, Context, Registry}

  describe "call activity" do
    test "executes external process from registry and merges data back" do
      # Child process that sets data
      child_start = {:bpmn_event_start, %{id: "cs", incoming: [], outgoing: ["cf1"]}}

      child_end = {:bpmn_event_end, %{id: "ce", incoming: ["cf1"], outgoing: []}}

      cf1 =
        {:bpmn_sequence_flow,
         %{
           id: "cf1",
           sourceRef: "cs",
           targetRef: "ce",
           conditionExpression: nil,
           isImmediate: nil
         }}

      child_elements = %{"cs" => child_start, "ce" => child_end, "cf1" => cf1}

      process_id = "call_test_#{:erlang.unique_integer()}"
      Registry.register(process_id, {:bpmn_process, %{id: process_id}, child_elements})

      # Parent process
      outer_end = {:bpmn_event_end, %{id: "end", incoming: ["flow_out"], outgoing: []}}

      flow_out =
        {:bpmn_sequence_flow,
         %{
           id: "flow_out",
           sourceRef: "call1",
           targetRef: "end",
           conditionExpression: nil,
           isImmediate: nil
         }}

      process = %{"flow_out" => flow_out, "end" => outer_end}
      {:ok, context} = Context.start_link(process, %{})

      elem =
        {:bpmn_activity_subprocess,
         %{id: "call1", calledElement: process_id, outgoing: ["flow_out"]}}

      assert {:ok, ^context} = Subprocess.token_in(elem, context)

      meta = Context.get_meta(context, "call1")
      assert meta.completed == true
      assert meta.type == :call_activity

      Registry.unregister(process_id)
    end

    test "returns error when process not found in registry" do
      {:ok, context} = Context.start_link(%{}, %{})

      elem =
        {:bpmn_activity_subprocess,
         %{id: "call1", calledElement: "nonexistent", outgoing: ["flow_out"]}}

      assert {:error, msg} = Subprocess.token_in(elem, context)
      assert msg =~ "not found in registry"
    end

    test "returns error when child process has no start event" do
      child_elements = %{
        "ce" => {:bpmn_event_end, %{id: "ce", incoming: [], outgoing: []}}
      }

      process_id = "no_start_#{:erlang.unique_integer()}"
      Registry.register(process_id, {:bpmn_process, %{id: process_id}, child_elements})

      {:ok, context} = Context.start_link(%{}, %{})

      elem =
        {:bpmn_activity_subprocess,
         %{id: "call1", calledElement: process_id, outgoing: ["flow_out"]}}

      assert {:error, msg} = Subprocess.token_in(elem, context)
      assert msg =~ "no start event"

      Registry.unregister(process_id)
    end

    test "propagates error from child process" do
      child_start = {:bpmn_event_start, %{id: "cs", incoming: [], outgoing: ["cf1"]}}

      child_err =
        {:bpmn_event_end,
         %{
           id: "ce",
           incoming: ["cf1"],
           outgoing: [],
           errorEventDefinition: {:bpmn_event_definition_error, %{errorRef: "child_error"}}
         }}

      cf1 =
        {:bpmn_sequence_flow,
         %{
           id: "cf1",
           sourceRef: "cs",
           targetRef: "ce",
           conditionExpression: nil,
           isImmediate: nil
         }}

      child_elements = %{"cs" => child_start, "ce" => child_err, "cf1" => cf1}
      process_id = "err_child_#{:erlang.unique_integer()}"
      Registry.register(process_id, {:bpmn_process, %{id: process_id}, child_elements})

      {:ok, context} = Context.start_link(%{}, %{})

      elem =
        {:bpmn_activity_subprocess,
         %{id: "call1", calledElement: process_id, outgoing: ["flow_out"]}}

      assert {:error, "child_error"} = Subprocess.token_in(elem, context)

      Registry.unregister(process_id)
    end
  end

  describe "dispatch via RodarBpmn.execute/2" do
    test "dispatches call activity correctly" do
      child_start = {:bpmn_event_start, %{id: "cs", incoming: [], outgoing: ["cf1"]}}
      child_end = {:bpmn_event_end, %{id: "ce", incoming: ["cf1"], outgoing: []}}

      cf1 =
        {:bpmn_sequence_flow,
         %{
           id: "cf1",
           sourceRef: "cs",
           targetRef: "ce",
           conditionExpression: nil,
           isImmediate: nil
         }}

      child_elements = %{"cs" => child_start, "ce" => child_end, "cf1" => cf1}
      process_id = "dispatch_call_#{:erlang.unique_integer()}"
      Registry.register(process_id, {:bpmn_process, %{id: process_id}, child_elements})

      outer_end = {:bpmn_event_end, %{id: "end", incoming: ["flow_out"], outgoing: []}}

      flow_out =
        {:bpmn_sequence_flow,
         %{
           id: "flow_out",
           sourceRef: "call1",
           targetRef: "end",
           conditionExpression: nil,
           isImmediate: nil
         }}

      process = %{"flow_out" => flow_out, "end" => outer_end}
      {:ok, context} = Context.start_link(process, %{})

      elem =
        {:bpmn_activity_subprocess,
         %{id: "call1", calledElement: process_id, outgoing: ["flow_out"]}}

      assert {:ok, ^context} = RodarBpmn.execute(elem, context)

      Registry.unregister(process_id)
    end
  end
end
