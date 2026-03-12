defmodule Rodar.MigrationTest do
  use ExUnit.Case, async: false

  alias Rodar.{Migration, Registry}

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
      {:ok, pid} = Rodar.Process.create_and_run(@process_id)
      assert Rodar.Process.status(pid) == :suspended

      register_v2_compatible()

      assert :compatible = Migration.check_compatibility(pid, 2)

      Rodar.Process.terminate(pid)
    end

    test "returns {:incompatible, issues} when active node is missing" do
      register_v1_process()
      {:ok, pid} = Rodar.Process.create_and_run(@process_id)
      assert Rodar.Process.status(pid) == :suspended

      register_v2_incompatible()

      assert {:incompatible, issues} = Migration.check_compatibility(pid, 2)
      assert Enum.any?(issues, &(&1.type == :missing_node and &1.node_id == "user_task"))

      Rodar.Process.terminate(pid)
    end

    test "returns {:incompatible, _} for nonexistent version" do
      register_v1_process()
      {:ok, pid} = Rodar.Process.create_and_run(@process_id)

      assert {:incompatible, issues} = Migration.check_compatibility(pid, 99)
      assert Enum.any?(issues, &(&1.type == :version_not_found))

      Rodar.Process.terminate(pid)
    end
  end

  describe "migrate/2" do
    test "migrates a suspended instance to a compatible version" do
      register_v1_process()
      {:ok, pid} = Rodar.Process.create_and_run(@process_id)
      assert Rodar.Process.status(pid) == :suspended
      assert Rodar.Process.definition_version(pid) == 1

      register_v2_compatible()

      assert :ok = Migration.migrate(pid, 2)
      assert Rodar.Process.definition_version(pid) == 2
      assert Rodar.Process.status(pid) == :suspended

      Rodar.Process.terminate(pid)
    end

    test "returns error for incompatible migration" do
      register_v1_process()
      {:ok, pid} = Rodar.Process.create_and_run(@process_id)

      register_v2_incompatible()

      assert {:error, {:incompatible, _issues}} = Migration.migrate(pid, 2)
      # Version should not have changed
      assert Rodar.Process.definition_version(pid) == 1

      Rodar.Process.terminate(pid)
    end

    test "force migration skips compatibility check" do
      register_v1_process()
      {:ok, pid} = Rodar.Process.create_and_run(@process_id)

      register_v2_incompatible()

      assert :ok = Migration.migrate(pid, 2, force: true)
      assert Rodar.Process.definition_version(pid) == 2

      Rodar.Process.terminate(pid)
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

      {:ok, pid} = Rodar.Process.create_and_run(@process_id)
      assert Rodar.Process.status(pid) == :completed

      # Register v2 (same structure)
      Registry.register(@process_id, definition)

      assert :ok = Migration.migrate(pid, 2)
      assert Rodar.Process.definition_version(pid) == 2

      Rodar.Process.terminate(pid)
    end
  end
end
