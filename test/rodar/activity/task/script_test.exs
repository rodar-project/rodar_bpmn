defmodule RodarBpmn.Activity.Task.ScriptTest do
  use ExUnit.Case, async: true

  alias RodarBpmn.{Activity.Task.Script, Context}

  doctest RodarBpmn.Activity.Task.Script

  defp build_process do
    end_event = {:bpmn_event_end, %{id: "end", incoming: ["flow_out"], outgoing: []}}

    flow_out =
      {:bpmn_sequence_flow,
       %{
         id: "flow_out",
         sourceRef: "task",
         targetRef: "end",
         conditionExpression: nil,
         isImmediate: nil
       }}

    %{"flow_out" => flow_out, "end" => end_event}
  end

  describe "elixir scripts" do
    test "executes an elixir script and stores result" do
      process = build_process()
      {:ok, context} = Context.start_link(process, %{})

      elem =
        {:bpmn_activity_task_script,
         %{id: "task", outgoing: ["flow_out"], type: "elixir", script: "3 * 7"}}

      assert {:ok, ^context} = Script.token_in(elem, context)
      assert Context.get_data(context, :script_result) == 21
    end

    test "script has access to context data" do
      process = build_process()
      {:ok, context} = Context.start_link(process, %{})
      Context.put_data(context, "x", 10)

      elem =
        {:bpmn_activity_task_script,
         %{id: "task", outgoing: ["flow_out"], type: "elixir", script: ~s(data["x"] + 5)}}

      assert {:ok, ^context} = Script.token_in(elem, context)
      assert Context.get_data(context, :script_result) == 15
    end

    test "stores result under custom output_variable" do
      process = build_process()
      {:ok, context} = Context.start_link(process, %{})

      elem =
        {:bpmn_activity_task_script,
         %{
           id: "task",
           outgoing: ["flow_out"],
           type: "elixir",
           script: ~s("hello"),
           output_variable: :greeting
         }}

      assert {:ok, ^context} = Script.token_in(elem, context)
      assert Context.get_data(context, :greeting) == "hello"
    end

    test "returns error for disallowed operations" do
      process = build_process()
      {:ok, context} = Context.start_link(process, %{})

      elem =
        {:bpmn_activity_task_script,
         %{id: "task", outgoing: ["flow_out"], type: "elixir", script: ~S|System.cmd("ls", [])|}}

      assert {:error, "disallowed: module call System.cmd/2"} =
               Script.token_in(elem, context)
    end

    test "returns error on runtime failure" do
      process = build_process()
      {:ok, context} = Context.start_link(process, %{})

      elem =
        {:bpmn_activity_task_script,
         %{id: "task", outgoing: ["flow_out"], type: "elixir", script: "1 / 0"}}

      assert {:error, "runtime error:" <> _} = Script.token_in(elem, context)
    end
  end

  describe "unsupported language" do
    test "returns error for unknown script language" do
      process = build_process()
      {:ok, context} = Context.start_link(process, %{})

      elem =
        {:bpmn_activity_task_script,
         %{id: "task", outgoing: ["flow_out"], type: "python", script: "print(1)"}}

      assert {:error, "Unsupported script language: \"python\""} =
               Script.token_in(elem, context)
    end

    test "returns error for javascript" do
      process = build_process()
      {:ok, context} = Context.start_link(process, %{})

      elem =
        {:bpmn_activity_task_script,
         %{id: "task", outgoing: ["flow_out"], type: "javascript", script: "1+1"}}

      assert {:error, "Unsupported script language: \"javascript\""} =
               Script.token_in(elem, context)
    end
  end

  describe "fallback" do
    test "returns {:not_implemented} for unrecognized element shape" do
      assert {:not_implemented} = Script.execute(:bad, nil)
    end
  end
end
