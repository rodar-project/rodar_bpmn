defmodule RodarBpmn.TaskHandlerTest do
  use ExUnit.Case, async: false

  alias RodarBpmn.TaskRegistry

  defmodule CountingHandler do
    @behaviour RodarBpmn.TaskHandler

    @impl true
    def token_in({_type, %{id: id}}, context) do
      RodarBpmn.Context.put_data(context, "handled_by", id)
      {:ok, context}
    end
  end

  defmodule TypeHandler do
    @behaviour RodarBpmn.TaskHandler

    @impl true
    def token_in({type, _attrs}, context) do
      RodarBpmn.Context.put_data(context, "handler_type", Atom.to_string(type))
      {:ok, context}
    end
  end

  setup do
    for {key, _mod} <- TaskRegistry.list() do
      TaskRegistry.unregister(key)
    end

    :ok
  end

  defp build_process(custom_type, task_id) do
    %{
      "start" => {:bpmn_event_start, %{id: "start", incoming: [], outgoing: ["f1"]}},
      "f1" =>
        {:bpmn_sequence_flow,
         %{id: "f1", sourceRef: "start", targetRef: task_id, conditionExpression: nil}},
      task_id => {custom_type, %{id: task_id, incoming: ["f1"], outgoing: ["f2"]}},
      "f2" =>
        {:bpmn_sequence_flow,
         %{id: "f2", sourceRef: task_id, targetRef: "end", conditionExpression: nil}},
      "end" => {:bpmn_event_end, %{id: "end", incoming: ["f2"], outgoing: []}}
    }
  end

  describe "custom handler by type" do
    test "handler is invoked for registered type" do
      TaskRegistry.register(:my_custom_task, TypeHandler)
      process = build_process(:my_custom_task, "task_1")
      {:ok, context} = RodarBpmn.Context.start_link(process, %{})
      start = process["start"]

      {:ok, ^context} = RodarBpmn.execute(start, context)
      assert RodarBpmn.Context.get_data(context, "handler_type") == "my_custom_task"
    end
  end

  describe "custom handler by task ID" do
    test "handler is invoked for registered task ID" do
      TaskRegistry.register("specific_task", CountingHandler)
      process = build_process(:some_unknown_type, "specific_task")
      {:ok, context} = RodarBpmn.Context.start_link(process, %{})
      start = process["start"]

      {:ok, ^context} = RodarBpmn.execute(start, context)
      assert RodarBpmn.Context.get_data(context, "handled_by") == "specific_task"
    end

    test "task ID takes priority over type registration" do
      TaskRegistry.register(:my_custom_task, TypeHandler)
      TaskRegistry.register("priority_task", CountingHandler)
      process = build_process(:my_custom_task, "priority_task")
      {:ok, context} = RodarBpmn.Context.start_link(process, %{})
      start = process["start"]

      {:ok, ^context} = RodarBpmn.execute(start, context)
      # CountingHandler sets "handled_by", TypeHandler sets "handler_type"
      assert RodarBpmn.Context.get_data(context, "handled_by") == "priority_task"
      assert RodarBpmn.Context.get_data(context, "handler_type") == nil
    end
  end

  describe "unregistered types" do
    test "unregistered types return nil (existing behavior)" do
      process = build_process(:totally_unknown, "unknown_task")
      {:ok, context} = RodarBpmn.Context.start_link(process, %{})

      # Dispatch directly — should return nil for unknown type
      result = RodarBpmn.execute({:totally_unknown, %{id: "unknown_task"}}, context)
      # nil result from dispatch means no handler matched
      assert result == nil
    end
  end
end
