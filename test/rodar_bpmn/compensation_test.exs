defmodule RodarBpmn.CompensationTest do
  use ExUnit.Case, async: true

  setup do
    {:ok, context} = RodarBpmn.Context.start_link(%{}, %{})
    {:ok, context: context}
  end

  describe "register_handler/3" do
    test "stores a handler entry", %{context: context} do
      RodarBpmn.Compensation.register_handler(context, "task1", "compensate_task1")
      handlers = RodarBpmn.Compensation.handlers(context)

      assert length(handlers) == 1
      assert hd(handlers).activity_id == "task1"
      assert hd(handlers).handler_id == "compensate_task1"
      assert is_integer(hd(handlers).registered_at)
    end

    test "appends multiple handlers", %{context: context} do
      RodarBpmn.Compensation.register_handler(context, "task1", "comp1")
      RodarBpmn.Compensation.register_handler(context, "task2", "comp2")

      assert length(RodarBpmn.Compensation.handlers(context)) == 2
    end
  end

  describe "handlers/1" do
    test "returns empty list when no handlers registered", %{context: context} do
      assert RodarBpmn.Compensation.handlers(context) == []
    end
  end

  describe "compensate_activity/2" do
    test "executes specific handler", %{context: context} do
      end_event = {:bpmn_event_end, %{id: "comp_end", incoming: [], outgoing: []}}
      process = %{"comp_handler" => end_event}
      RodarBpmn.Context.swap_process(context, process)

      RodarBpmn.Compensation.register_handler(context, "task1", "comp_handler")
      result = RodarBpmn.Compensation.compensate_activity(context, "task1")

      assert {:ok, ^context} = result
    end

    test "returns error for missing handler", %{context: context} do
      assert {:error, msg} = RodarBpmn.Compensation.compensate_activity(context, "nonexistent")
      assert msg =~ "No compensation handler registered"
    end
  end

  describe "compensate_all/1" do
    test "executes handlers in reverse completion order", %{context: context} do
      # Use script tasks that store results under different output_variables
      script1 =
        {:bpmn_activity_task_script,
         %{
           id: "comp1",
           outgoing: [],
           incoming: [],
           type: "elixir",
           script: ~s("compensated_1"),
           output_variable: :comp1_result
         }}

      script2 =
        {:bpmn_activity_task_script,
         %{
           id: "comp2",
           outgoing: [],
           incoming: [],
           type: "elixir",
           script: ~s("compensated_2"),
           output_variable: :comp2_result
         }}

      process = %{"comp1" => script1, "comp2" => script2}
      RodarBpmn.Context.swap_process(context, process)

      RodarBpmn.Compensation.register_handler(context, "task1", "comp1")
      RodarBpmn.Compensation.register_handler(context, "task2", "comp2")

      {:ok, _} = RodarBpmn.Compensation.compensate_all(context)

      # Both handlers executed
      assert RodarBpmn.Context.get_data(context, :comp1_result) == "compensated_1"
      assert RodarBpmn.Context.get_data(context, :comp2_result) == "compensated_2"

      # Verify reverse order via execution history
      history = RodarBpmn.Context.get_history(context)
      comp_ids = Enum.map(history, & &1.node_id)
      assert comp_ids == ["comp2", "comp1"]
    end

    test "returns ok with no handlers", %{context: context} do
      assert {:ok, ^context} = RodarBpmn.Compensation.compensate_all(context)
    end
  end
end
