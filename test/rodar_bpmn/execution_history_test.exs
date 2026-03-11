defmodule RodarBpmn.ExecutionHistoryTest do
  use ExUnit.Case, async: true

  alias RodarBpmn.Context

  describe "execution history via RodarBpmn.execute/3" do
    test "records visit and completion for a simple start->end flow" do
      end_event = {:bpmn_event_end, %{id: "end_1", incoming: ["flow_1"], outgoing: []}}

      flow =
        {:bpmn_sequence_flow,
         %{
           id: "flow_1",
           sourceRef: "start_1",
           targetRef: "end_1",
           conditionExpression: nil,
           isImmediate: nil
         }}

      start = {:bpmn_event_start, %{id: "start_1", incoming: [], outgoing: ["flow_1"]}}

      process = %{
        "start_1" => start,
        "end_1" => end_event,
        "flow_1" => flow
      }

      {:ok, context} = Context.start_link(process, %{})
      token = RodarBpmn.Token.new()

      {:ok, ^context} = RodarBpmn.execute(start, context, token)

      history = Context.get_history(context)
      assert length(history) >= 2

      start_entries = Context.get_node_history(context, "start_1")
      assert length(start_entries) == 1
      assert hd(start_entries).result == :ok

      end_entries = Context.get_node_history(context, "end_1")
      assert length(end_entries) == 1
      assert hd(end_entries).result == :ok
    end

    test "records history entries with token_id and node_type" do
      start = {:bpmn_event_start, %{id: "start_1", incoming: [], outgoing: []}}
      process = %{"start_1" => start}

      {:ok, context} = Context.start_link(process, %{})
      token = RodarBpmn.Token.new()

      RodarBpmn.execute(start, context, token)

      [entry] = Context.get_node_history(context, "start_1")
      assert entry.token_id == token.id
      assert entry.node_type == :bpmn_event_start
      assert is_integer(entry.timestamp)
    end

    test "classifies preceding nodes as :ok when process suspends at user task" do
      # Process: Start -> flow1 -> ServiceTask -> flow2 -> UserTask -> flow3 -> End
      start =
        {:bpmn_event_start, %{id: "start_1", incoming: [], outgoing: ["flow_1"]}}

      flow_1 =
        {:bpmn_sequence_flow,
         %{
           id: "flow_1",
           sourceRef: "start_1",
           targetRef: "service_1",
           conditionExpression: nil,
           isImmediate: nil
         }}

      service_task =
        {:bpmn_activity_task_service,
         %{
           id: "service_1",
           outgoing: ["flow_2"],
           handler: RodarBpmn.Activity.Task.Service.TestHandler
         }}

      flow_2 =
        {:bpmn_sequence_flow,
         %{
           id: "flow_2",
           sourceRef: "service_1",
           targetRef: "user_1",
           conditionExpression: nil,
           isImmediate: nil
         }}

      user_task =
        {:bpmn_activity_task_user, %{id: "user_1", name: "Review", outgoing: ["flow_3"]}}

      flow_3 =
        {:bpmn_sequence_flow,
         %{
           id: "flow_3",
           sourceRef: "user_1",
           targetRef: "end_1",
           conditionExpression: nil,
           isImmediate: nil
         }}

      end_event =
        {:bpmn_event_end, %{id: "end_1", incoming: ["flow_3"], outgoing: []}}

      process = %{
        "start_1" => start,
        "flow_1" => flow_1,
        "service_1" => service_task,
        "flow_2" => flow_2,
        "user_1" => user_task,
        "flow_3" => flow_3,
        "end_1" => end_event
      }

      {:ok, context} = Context.start_link(process, %{})
      token = RodarBpmn.Token.new()

      # Execution suspends at user task
      {:manual, _task_data} = RodarBpmn.execute(start, context, token)

      # Start event should be :ok, not :manual
      [start_entry] = Context.get_node_history(context, "start_1")
      assert start_entry.result == :ok

      # Service task should be :ok, not :manual
      [service_entry] = Context.get_node_history(context, "service_1")
      assert service_entry.result == :ok

      # Sequence flows should be :ok
      [flow_1_entry] = Context.get_node_history(context, "flow_1")
      assert flow_1_entry.result == :ok

      [flow_2_entry] = Context.get_node_history(context, "flow_2")
      assert flow_2_entry.result == :ok

      # Only the user task itself should be :manual
      [user_entry] = Context.get_node_history(context, "user_1")
      assert user_entry.result == :manual
    end
  end

  describe "Context history API" do
    test "record_visit/2 appends to history" do
      {:ok, context} = Context.start_link(%{}, %{})

      Context.record_visit(context, %{node_id: "n1", token_id: "t1", timestamp: 100})
      Context.record_visit(context, %{node_id: "n2", token_id: "t1", timestamp: 200})

      history = Context.get_history(context)
      assert length(history) == 2
      assert Enum.map(history, & &1.node_id) == ["n1", "n2"]
    end

    test "record_completion/4 updates matching entry" do
      {:ok, context} = Context.start_link(%{}, %{})

      Context.record_visit(context, %{node_id: "n1", token_id: "t1", timestamp: 100})
      Context.record_completion(context, "n1", "t1", :ok)

      [entry] = Context.get_history(context)
      assert entry.result == :ok
    end

    test "get_node_history/2 filters by node_id" do
      {:ok, context} = Context.start_link(%{}, %{})

      Context.record_visit(context, %{node_id: "n1", token_id: "t1", timestamp: 100})
      Context.record_visit(context, %{node_id: "n2", token_id: "t1", timestamp: 200})
      Context.record_visit(context, %{node_id: "n1", token_id: "t2", timestamp: 300})

      assert length(Context.get_node_history(context, "n1")) == 2
      assert length(Context.get_node_history(context, "n2")) == 1
    end

    test "get_state/1 returns full state snapshot" do
      {:ok, context} = Context.start_link(%{id: "proc"}, %{key: "val"})
      Context.put_data(context, :x, 42)

      state = Context.get_state(context)
      assert state.init == %{key: "val"}
      assert state.data == %{x: 42}
      assert state.process == %{id: "proc"}
      assert state.history == []
    end
  end
end
