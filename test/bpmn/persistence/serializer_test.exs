defmodule Bpmn.Persistence.SerializerTest do
  use ExUnit.Case, async: true

  alias Bpmn.Persistence.Serializer
  alias Bpmn.Token

  describe "serialize_token/1 and deserialize_token/1" do
    test "roundtrips a token" do
      token = Token.new(current_node: "task_1", state: :waiting)
      serialized = Serializer.serialize_token(token)
      deserialized = Serializer.deserialize_token(serialized)

      assert %Token{} = deserialized
      assert deserialized.id == token.id
      assert deserialized.current_node == "task_1"
      assert deserialized.state == :waiting
      assert deserialized.parent_id == token.parent_id
      assert deserialized.created_at == token.created_at
    end

    test "handles nil token" do
      assert Serializer.serialize_token(nil) == nil
      assert Serializer.deserialize_token(nil) == nil
    end

    test "roundtrips a forked token" do
      parent = Token.new(current_node: "gateway_1")
      child = Token.fork(parent)
      serialized = Serializer.serialize_token(child)
      deserialized = Serializer.deserialize_token(serialized)

      assert deserialized.parent_id == parent.id
      assert deserialized.current_node == "gateway_1"
    end
  end

  describe "serialize_context_state/1 and deserialize_context_state/1" do
    test "roundtrips context state with MapSets in nodes" do
      state = %{
        init: %{order_id: "123"},
        data: %{status: "pending"},
        process: %{"start" => {:bpmn_event_start, %{id: "start", outgoing: ["f1"]}}},
        nodes: %{
          {:gateway_tokens, "gw1"} => MapSet.new(["flow_a", "flow_b"]),
          "task1" => %{active: true, completed: false, type: :user_task}
        },
        history: [%{node_id: "start", token_id: "t1", timestamp: 12_345}]
      }

      serialized = Serializer.serialize_context_state(state)

      # MapSets should be converted to sorted lists
      assert serialized.nodes[{:gateway_tokens, "gw1"}] == ["flow_a", "flow_b"]

      deserialized = Serializer.deserialize_context_state(serialized)

      # MapSets should be reconstituted
      assert %MapSet{} = deserialized.nodes[{:gateway_tokens, "gw1"}]
      assert MapSet.member?(deserialized.nodes[{:gateway_tokens, "gw1"}], "flow_a")
      assert MapSet.member?(deserialized.nodes[{:gateway_tokens, "gw1"}], "flow_b")

      # Regular node metadata preserved
      assert deserialized.nodes["task1"] == %{active: true, completed: false, type: :user_task}

      # Other fields preserved
      assert deserialized.init == state.init
      assert deserialized.data == state.data
      assert deserialized.process == state.process
      assert deserialized.history == state.history
    end

    test "strips timer_ref from node metadata" do
      state = %{
        init: %{},
        data: %{},
        process: %{},
        nodes: %{
          "timer1" => %{active: true, completed: false, type: :catch_event, timer_ref: make_ref()}
        },
        history: []
      }

      serialized = Serializer.serialize_context_state(state)
      refute Map.has_key?(serialized.nodes["timer1"], :timer_ref)

      deserialized = Serializer.deserialize_context_state(serialized)
      assert deserialized.nodes["timer1"] == %{active: true, completed: false, type: :catch_event}
    end

    test "roundtrips context state with BPMN element tuples" do
      process = %{
        "start" => {:bpmn_event_start, %{id: "start", outgoing: ["f1"]}},
        "task1" => {:bpmn_task_user, %{id: "task1", incoming: ["f1"], outgoing: ["f2"]}},
        "end" => {:bpmn_event_end, %{id: "end", incoming: ["f2"], outgoing: []}}
      }

      state = %{init: %{}, data: %{}, process: process, nodes: %{}, history: []}

      serialized = Serializer.serialize_context_state(state)
      deserialized = Serializer.deserialize_context_state(serialized)

      assert deserialized.process == process
    end

    test "roundtrips with history entries" do
      history = [
        %{node_id: "start", token_id: "t1", timestamp: 1000, result: :ok},
        %{node_id: "task1", token_id: "t1", timestamp: 2000}
      ]

      state = %{init: %{}, data: %{}, process: %{}, nodes: %{}, history: history}

      serialized = Serializer.serialize_context_state(state)
      deserialized = Serializer.deserialize_context_state(serialized)

      assert deserialized.history == history
    end

    test "handles empty maps and nil values in data" do
      state = %{
        init: %{},
        data: %{key: nil, nested: %{}},
        process: %{},
        nodes: %{},
        history: []
      }

      serialized = Serializer.serialize_context_state(state)
      deserialized = Serializer.deserialize_context_state(serialized)

      assert deserialized.data == %{key: nil, nested: %{}}
    end
  end

  describe "snapshot/1" do
    test "builds a complete snapshot map" do
      token = Token.new(current_node: "task_1")

      input = %{
        instance_id: "inst-123",
        process_id: "my_process",
        status: :suspended,
        root_token: token,
        context_state: %{
          init: %{},
          data: %{x: 1},
          process: %{},
          nodes: %{},
          history: []
        }
      }

      snapshot = Serializer.snapshot(input)

      assert snapshot.version == 1
      assert snapshot.instance_id == "inst-123"
      assert snapshot.process_id == "my_process"
      assert snapshot.status == :suspended
      assert snapshot.root_token.id == token.id
      assert snapshot.context_state.data == %{x: 1}
      assert is_integer(snapshot.dehydrated_at)
    end
  end

  describe "serialize/1 and deserialize/1" do
    test "roundtrips a snapshot through binary format" do
      snapshot = %{
        version: 1,
        instance_id: "inst-456",
        process_id: "proc",
        status: :suspended,
        root_token: %{
          id: "t1",
          current_node: "task",
          state: :waiting,
          parent_id: nil,
          created_at: 0
        },
        context_state: %{
          init: %{},
          data: %{result: "hello"},
          process: %{"s" => {:bpmn_event_start, %{id: "s"}}},
          nodes: %{},
          history: []
        },
        dehydrated_at: 1_700_000_000_000
      }

      binary = Serializer.serialize(snapshot)
      assert is_binary(binary)

      restored = Serializer.deserialize(binary)
      assert restored == snapshot
    end
  end
end
