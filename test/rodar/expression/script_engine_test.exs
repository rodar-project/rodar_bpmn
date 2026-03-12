defmodule RodarBpmn.Expression.ScriptEngineTest do
  use ExUnit.Case, async: false

  alias RodarBpmn.Activity.Task.Script
  alias RodarBpmn.Context
  alias RodarBpmn.Expression.ScriptRegistry

  defmodule MockEngine do
    @behaviour RodarBpmn.Expression.ScriptEngine

    @impl true
    def eval("return_42", _bindings), do: {:ok, 42}
    def eval("use_bindings", bindings), do: {:ok, Map.get(bindings, "x", 0)}
    def eval("fail", _bindings), do: {:error, "mock error"}
    def eval(script, _bindings), do: {:ok, "echo: #{script}"}
  end

  setup do
    on_exit(fn ->
      for {lang, _mod} <- ScriptRegistry.list() do
        ScriptRegistry.unregister(lang)
      end
    end)
  end

  describe "ScriptEngine behaviour through ScriptTask" do
    test "registered engine is invoked by script task with binary script" do
      ScriptRegistry.register("mock", MockEngine)

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

      elem =
        {:bpmn_activity_task_script,
         %{id: "task", outgoing: ["flow_out"], type: "mock", script: "return_42"}}

      process = %{"flow_out" => flow_out, "end" => end_event}
      {:ok, context} = Context.start_link(process, %{})
      {:ok, ^context} = Script.token_in(elem, context)

      assert Context.get_data(context, :script_result) == 42
    end

    test "registered engine is invoked with bpmn_script tuple" do
      ScriptRegistry.register("mock", MockEngine)

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

      script = {:bpmn_script, %{expression: "return_42"}}

      elem =
        {:bpmn_activity_task_script,
         %{id: "task", outgoing: ["flow_out"], type: "mock", script: script}}

      process = %{"flow_out" => flow_out, "end" => end_event}
      {:ok, context} = Context.start_link(process, %{})
      {:ok, ^context} = Script.token_in(elem, context)

      assert Context.get_data(context, :script_result) == 42
    end

    test "engine receives process data as bindings" do
      ScriptRegistry.register("mock", MockEngine)

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

      elem =
        {:bpmn_activity_task_script,
         %{id: "task", outgoing: ["flow_out"], type: "mock", script: "use_bindings"}}

      process = %{"flow_out" => flow_out, "end" => end_event}
      {:ok, context} = Context.start_link(process, %{})
      Context.put_data(context, "x", 99)
      {:ok, ^context} = Script.token_in(elem, context)

      assert Context.get_data(context, :script_result) == 99
    end

    test "engine error propagates as script task error" do
      ScriptRegistry.register("mock", MockEngine)

      elem =
        {:bpmn_activity_task_script,
         %{id: "task", outgoing: ["flow_out"], type: "mock", script: "fail"}}

      process = %{}
      {:ok, context} = Context.start_link(process, %{})
      assert {:error, "mock error"} = Script.token_in(elem, context)
    end

    test "unregistered language returns error" do
      elem =
        {:bpmn_activity_task_script,
         %{id: "task", outgoing: ["flow_out"], type: "unknown_lang", script: "anything"}}

      process = %{}
      {:ok, context} = Context.start_link(process, %{})

      assert {:error, msg} = Script.token_in(elem, context)
      assert msg =~ "Unsupported script language"
      assert msg =~ "unknown_lang"
    end
  end
end
