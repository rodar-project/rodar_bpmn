defmodule RodarBpmn.PersistenceTest do
  use ExUnit.Case, async: false

  alias RodarBpmn.Persistence
  alias RodarBpmn.Persistence.Adapter.ETS

  setup do
    :ets.delete_all_objects(:rodar_bpmn_persistence)

    # Register a simple process with a user task
    process_id = "persist_test_#{:erlang.unique_integer([:positive])}"

    start_event =
      {:bpmn_event_start, %{id: "start", outgoing: ["f1"], incoming: []}}

    flow1 =
      {:bpmn_sequence_flow,
       %{
         id: "f1",
         sourceRef: "start",
         targetRef: "user_task",
         conditionExpression: nil,
         isImmediate: nil
       }}

    user_task =
      {:bpmn_activity_task_user,
       %{id: "user_task", incoming: ["f1"], outgoing: ["f2"], name: "Do something"}}

    flow2 =
      {:bpmn_sequence_flow,
       %{
         id: "f2",
         sourceRef: "user_task",
         targetRef: "end",
         conditionExpression: nil,
         isImmediate: nil
       }}

    end_event =
      {:bpmn_event_end, %{id: "end", incoming: ["f2"], outgoing: []}}

    definition =
      {:bpmn_process, %{id: process_id}, [start_event, flow1, user_task, flow2, end_event]}

    :ok = RodarBpmn.Registry.register(process_id, definition)

    on_exit(fn ->
      RodarBpmn.Registry.unregister(process_id)
    end)

    %{process_id: process_id}
  end

  describe "full dehydrate/rehydrate cycle" do
    test "start → user_task → dehydrate → rehydrate → verify context data", %{
      process_id: process_id
    } do
      # Start and run until user task suspends
      {:ok, pid} = RodarBpmn.Process.create_and_run(process_id, %{order_id: "ORD-001"})

      assert RodarBpmn.Process.status(pid) == :suspended

      # Store some data in context before dehydrating
      context = RodarBpmn.Process.get_context(pid)
      RodarBpmn.Context.put_data(context, :step, "waiting_for_input")
      instance_id = RodarBpmn.Process.instance_id(pid)

      # Dehydrate
      assert {:ok, ^instance_id} = RodarBpmn.Process.dehydrate(pid)

      # Verify snapshot is persisted
      assert {:ok, _snapshot} = Persistence.load(instance_id)

      # Stop the original process
      RodarBpmn.Process.terminate(pid)

      # Rehydrate
      assert {:ok, new_pid} = RodarBpmn.Process.rehydrate(instance_id)
      assert new_pid != pid

      # Verify status
      assert RodarBpmn.Process.status(new_pid) == :suspended

      # Verify context data is preserved
      new_context = RodarBpmn.Process.get_context(new_pid)
      assert RodarBpmn.Context.get_data(new_context, :step) == "waiting_for_input"
      assert RodarBpmn.Context.get(new_context, :init) == %{order_id: "ORD-001"}

      # Verify instance ID is preserved
      assert RodarBpmn.Process.instance_id(new_pid) == instance_id

      # Cleanup
      RodarBpmn.Process.terminate(new_pid)
    end
  end

  describe "auto-dehydrate" do
    test "automatically saves snapshot on {:manual, _}", %{process_id: process_id} do
      {:ok, pid} = RodarBpmn.Process.create_and_run(process_id, %{})
      instance_id = RodarBpmn.Process.instance_id(pid)

      # Auto-dehydrate should have saved the snapshot
      assert {:ok, snapshot} = Persistence.load(instance_id)
      assert snapshot.status == :suspended
      assert snapshot.process_id == process_id

      RodarBpmn.Process.terminate(pid)
    end

    test "does not auto-dehydrate when disabled", %{process_id: process_id} do
      # Temporarily disable auto-dehydrate
      original = Application.get_env(:rodar_bpmn, :persistence)

      Application.put_env(
        :rodar_bpmn,
        :persistence,
        Keyword.put(original, :auto_dehydrate, false)
      )

      {:ok, pid} = RodarBpmn.Process.create_and_run(process_id, %{})
      instance_id = RodarBpmn.Process.instance_id(pid)

      # Should NOT have auto-saved
      assert {:error, :not_found} = Persistence.load(instance_id)

      # Restore config
      Application.put_env(:rodar_bpmn, :persistence, original)
      RodarBpmn.Process.terminate(pid)
    end
  end

  describe "rehydrate error cases" do
    test "returns error for missing snapshot" do
      assert {:error, :not_found} = RodarBpmn.Process.rehydrate("nonexistent-id")
    end

    test "returns error when process definition not in registry" do
      # Save a snapshot with a bogus process_id
      snapshot = %{
        version: 1,
        instance_id: "orphan-id",
        process_id: "deleted_process",
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
          data: %{},
          process: %{},
          nodes: %{},
          history: []
        },
        dehydrated_at: 0
      }

      ETS.save("orphan-id", snapshot)

      assert {:error, _} = RodarBpmn.Process.rehydrate("orphan-id")
    end
  end

  describe "persistence facade" do
    test "CRUD operations via facade" do
      snapshot = %{version: 1, data: "test"}

      assert :ok = Persistence.save("facade-1", snapshot)
      assert {:ok, ^snapshot} = Persistence.load("facade-1")
      assert "facade-1" in Persistence.list()

      assert :ok = Persistence.delete("facade-1")
      assert {:error, :not_found} = Persistence.load("facade-1")
    end

    test "adapter/0 returns configured adapter" do
      assert Persistence.adapter() == RodarBpmn.Persistence.Adapter.ETS
    end
  end
end
