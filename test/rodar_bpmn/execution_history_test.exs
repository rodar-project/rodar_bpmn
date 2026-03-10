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
