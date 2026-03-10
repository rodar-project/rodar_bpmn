defmodule Bpmn.MigrationTest do
  use ExUnit.Case, async: false

  alias Bpmn.{Migration, Registry}

  @process_id "migration_test_process"

  setup do
    for id <- Registry.list() do
      Registry.unregister(id)
    end

    :ok
  end

  defp register_v1_process do
    elements = %{
      "start_1" => {:bpmn_event_start, %{id: "start_1", incoming: [], outgoing: ["flow_1"]}},
      "user_task" =>
        {:bpmn_activity_task_user,
         %{id: "user_task", name: "Do something", incoming: ["flow_1"], outgoing: ["flow_2"]}},
      "end_1" => {:bpmn_event_end, %{id: "end_1", incoming: ["flow_2"], outgoing: []}},
      "flow_1" =>
        {:bpmn_sequence_flow,
         %{
           id: "flow_1",
           sourceRef: "start_1",
           targetRef: "user_task",
           conditionExpression: nil,
           isImmediate: nil
         }},
      "flow_2" =>
        {:bpmn_sequence_flow,
         %{
           id: "flow_2",
           sourceRef: "user_task",
           targetRef: "end_1",
           conditionExpression: nil,
           isImmediate: nil
         }}
    }

    definition = {:bpmn_process, %{id: @process_id}, elements}
    Registry.register(@process_id, definition)
  end

  defp register_v2_compatible do
    elements = %{
      "start_1" => {:bpmn_event_start, %{id: "start_1", incoming: [], outgoing: ["flow_1"]}},
      "user_task" =>
        {:bpmn_activity_task_user,
         %{
           id: "user_task",
           name: "Do something updated",
           incoming: ["flow_1"],
           outgoing: ["flow_2"]
         }},
      "end_1" => {:bpmn_event_end, %{id: "end_1", incoming: ["flow_2"], outgoing: []}},
      "flow_1" =>
        {:bpmn_sequence_flow,
         %{
           id: "flow_1",
           sourceRef: "start_1",
           targetRef: "user_task",
           conditionExpression: nil,
           isImmediate: nil
         }},
      "flow_2" =>
        {:bpmn_sequence_flow,
         %{
           id: "flow_2",
           sourceRef: "user_task",
           targetRef: "end_1",
           conditionExpression: nil,
           isImmediate: nil
         }}
    }

    definition = {:bpmn_process, %{id: @process_id}, elements}
    Registry.register(@process_id, definition)
  end

  defp register_v2_incompatible do
    # Renames user_task to review_task — instance waiting on user_task won't find it
    elements = %{
      "start_1" => {:bpmn_event_start, %{id: "start_1", incoming: [], outgoing: ["flow_1"]}},
      "review_task" =>
        {:bpmn_activity_task_user,
         %{
           id: "review_task",
           name: "Review",
           incoming: ["flow_1"],
           outgoing: ["flow_2"]
         }},
      "end_1" => {:bpmn_event_end, %{id: "end_1", incoming: ["flow_2"], outgoing: []}},
      "flow_1" =>
        {:bpmn_sequence_flow,
         %{
           id: "flow_1",
           sourceRef: "start_1",
           targetRef: "review_task",
           conditionExpression: nil,
           isImmediate: nil
         }},
      "flow_2" =>
        {:bpmn_sequence_flow,
         %{
           id: "flow_2",
           sourceRef: "review_task",
           targetRef: "end_1",
           conditionExpression: nil,
           isImmediate: nil
         }}
    }

    definition = {:bpmn_process, %{id: @process_id}, elements}
    Registry.register(@process_id, definition)
  end

  describe "check_compatibility/2" do
    test "returns :compatible when active nodes exist in target" do
      register_v1_process()
      {:ok, pid} = Bpmn.Process.create_and_run(@process_id)
      assert Bpmn.Process.status(pid) == :suspended

      register_v2_compatible()

      assert :compatible = Migration.check_compatibility(pid, 2)

      Bpmn.Process.terminate(pid)
    end

    test "returns {:incompatible, issues} when active node is missing" do
      register_v1_process()
      {:ok, pid} = Bpmn.Process.create_and_run(@process_id)
      assert Bpmn.Process.status(pid) == :suspended

      register_v2_incompatible()

      assert {:incompatible, issues} = Migration.check_compatibility(pid, 2)
      assert Enum.any?(issues, &(&1.type == :missing_node and &1.node_id == "user_task"))

      Bpmn.Process.terminate(pid)
    end

    test "returns {:incompatible, _} for nonexistent version" do
      register_v1_process()
      {:ok, pid} = Bpmn.Process.create_and_run(@process_id)

      assert {:incompatible, issues} = Migration.check_compatibility(pid, 99)
      assert Enum.any?(issues, &(&1.type == :version_not_found))

      Bpmn.Process.terminate(pid)
    end
  end

  describe "migrate/2" do
    test "migrates a suspended instance to a compatible version" do
      register_v1_process()
      {:ok, pid} = Bpmn.Process.create_and_run(@process_id)
      assert Bpmn.Process.status(pid) == :suspended
      assert Bpmn.Process.definition_version(pid) == 1

      register_v2_compatible()

      assert :ok = Migration.migrate(pid, 2)
      assert Bpmn.Process.definition_version(pid) == 2
      assert Bpmn.Process.status(pid) == :suspended

      Bpmn.Process.terminate(pid)
    end

    test "returns error for incompatible migration" do
      register_v1_process()
      {:ok, pid} = Bpmn.Process.create_and_run(@process_id)

      register_v2_incompatible()

      assert {:error, {:incompatible, _issues}} = Migration.migrate(pid, 2)
      # Version should not have changed
      assert Bpmn.Process.definition_version(pid) == 1

      Bpmn.Process.terminate(pid)
    end

    test "force migration skips compatibility check" do
      register_v1_process()
      {:ok, pid} = Bpmn.Process.create_and_run(@process_id)

      register_v2_incompatible()

      assert :ok = Migration.migrate(pid, 2, force: true)
      assert Bpmn.Process.definition_version(pid) == 2

      Bpmn.Process.terminate(pid)
    end

    test "migrates a completed instance" do
      # Register a simple start→end process that completes immediately
      elements = %{
        "start_1" => {:bpmn_event_start, %{id: "start_1", incoming: [], outgoing: ["flow_1"]}},
        "end_1" => {:bpmn_event_end, %{id: "end_1", incoming: ["flow_1"], outgoing: []}},
        "flow_1" =>
          {:bpmn_sequence_flow,
           %{
             id: "flow_1",
             sourceRef: "start_1",
             targetRef: "end_1",
             conditionExpression: nil,
             isImmediate: nil
           }}
      }

      definition = {:bpmn_process, %{id: @process_id}, elements}
      Registry.register(@process_id, definition)

      {:ok, pid} = Bpmn.Process.create_and_run(@process_id)
      assert Bpmn.Process.status(pid) == :completed

      # Register v2 (same structure)
      Registry.register(@process_id, definition)

      assert :ok = Migration.migrate(pid, 2)
      assert Bpmn.Process.definition_version(pid) == 2

      Bpmn.Process.terminate(pid)
    end
  end
end
