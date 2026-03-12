defmodule RodarBpmn.ProcessTest do
  use ExUnit.Case, async: false

  alias RodarBpmn.{Context, Registry}

  @process_id "test_process"

  setup do
    # Clean up registry
    for id <- Registry.list() do
      Registry.unregister(id)
    end

    :ok
  end

  defp register_simple_process do
    start = {:bpmn_event_start, %{id: "start_1", incoming: [], outgoing: ["flow_1"]}}
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

    elements = %{
      "start_1" => start,
      "end_1" => end_event,
      "flow_1" => flow
    }

    definition = {:bpmn_process, %{id: @process_id}, elements}
    Registry.register(@process_id, definition)
    definition
  end

  describe "start_link/2" do
    test "creates a process instance in :created status" do
      register_simple_process()
      {:ok, pid} = RodarBpmn.Process.start_link(@process_id)

      assert RodarBpmn.Process.status(pid) == :created
    end

    test "returns error for unregistered process" do
      Process.flag(:trap_exit, true)
      assert {:error, _} = RodarBpmn.Process.start_link("nonexistent")
    end
  end

  describe "activate/1" do
    test "runs the process to completion" do
      register_simple_process()
      {:ok, pid} = RodarBpmn.Process.start_link(@process_id)

      assert :ok = RodarBpmn.Process.activate(pid)
      assert RodarBpmn.Process.status(pid) == :completed
    end

    test "cannot activate a non-created process" do
      register_simple_process()
      {:ok, pid} = RodarBpmn.Process.start_link(@process_id)

      RodarBpmn.Process.activate(pid)
      assert {:error, _} = RodarBpmn.Process.activate(pid)
    end
  end

  describe "create_and_run/2" do
    test "creates and runs a process in one step" do
      register_simple_process()

      {:ok, pid} = RodarBpmn.Process.create_and_run(@process_id)
      assert RodarBpmn.Process.status(pid) == :completed
    end

    test "returns error for unregistered process" do
      assert {:error, _} = RodarBpmn.Process.create_and_run("nonexistent")
    end
  end

  describe "suspend/1 and resume/1" do
    test "suspend/resume status transitions" do
      register_simple_process()
      {:ok, pid} = RodarBpmn.Process.start_link(@process_id)

      # Cannot suspend a :created process
      assert {:error, _} = RodarBpmn.Process.suspend(pid)
    end

    test "cannot resume a non-suspended process" do
      register_simple_process()
      {:ok, pid} = RodarBpmn.Process.start_link(@process_id)

      assert {:error, _} = RodarBpmn.Process.resume(pid)
    end
  end

  describe "terminate/1" do
    test "terminates and stops context" do
      register_simple_process()
      {:ok, pid} = RodarBpmn.Process.start_link(@process_id)
      context = RodarBpmn.Process.get_context(pid)

      assert Process.alive?(context)
      assert :ok = RodarBpmn.Process.terminate(pid)
      assert RodarBpmn.Process.status(pid) == :terminated

      # Context should be stopped (give it a moment to shut down)
      Process.sleep(10)
      refute Process.alive?(context)
    end
  end

  describe "get_context/1" do
    test "returns a live context pid" do
      register_simple_process()
      {:ok, pid} = RodarBpmn.Process.start_link(@process_id)

      context = RodarBpmn.Process.get_context(pid)
      assert is_pid(context)
      assert Process.alive?(context)
    end
  end

  describe "instance_id/1" do
    test "returns a unique instance ID" do
      register_simple_process()
      {:ok, pid1} = RodarBpmn.Process.start_link(@process_id)
      {:ok, pid2} = RodarBpmn.Process.start_link(@process_id)

      assert RodarBpmn.Process.instance_id(pid1) != RodarBpmn.Process.instance_id(pid2)
    end
  end

  describe "execution history integration" do
    test "records execution history during activate" do
      register_simple_process()
      {:ok, pid} = RodarBpmn.Process.start_link(@process_id)
      RodarBpmn.Process.activate(pid)

      context = RodarBpmn.Process.get_context(pid)
      history = Context.get_history(context)

      assert length(history) >= 2

      node_ids = Enum.map(history, & &1.node_id)
      assert "start_1" in node_ids
      assert "end_1" in node_ids
    end
  end

  describe "definition_version/1" do
    test "returns the version number of the definition" do
      register_simple_process()
      {:ok, pid} = RodarBpmn.Process.start_link(@process_id)

      assert RodarBpmn.Process.definition_version(pid) == 1
    end

    test "returns latest version after re-registration" do
      register_simple_process()
      # Re-register to get version 2
      definition =
        {:bpmn_process, %{id: @process_id},
         %{
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
         }}

      Registry.register(@process_id, definition)

      {:ok, pid} = RodarBpmn.Process.start_link(@process_id)
      assert RodarBpmn.Process.definition_version(pid) == 2
    end
  end

  describe "process_id/1" do
    test "returns the process ID string" do
      register_simple_process()
      {:ok, pid} = RodarBpmn.Process.start_link(@process_id)

      assert RodarBpmn.Process.process_id(pid) == @process_id
    end
  end

  describe "validation on activate" do
    setup do
      # Enable validation for this test
      Application.put_env(:rodar_bpmn, :validate_on_activate, true)

      on_exit(fn ->
        Application.delete_env(:rodar_bpmn, :validate_on_activate)
      end)
    end

    test "rejects invalid process with validation errors" do
      # Register a process with no end event
      elements = %{
        "start_1" => {:bpmn_event_start, %{id: "start_1", incoming: [], outgoing: ["flow_1"]}}
      }

      definition = {:bpmn_process, %{id: "invalid_process"}, elements}
      Registry.register("invalid_process", definition)

      {:ok, pid} = RodarBpmn.Process.start_link("invalid_process")

      assert {:error, {:validation_failed, issues}} = RodarBpmn.Process.activate(pid)
      assert is_list(issues)
      assert Enum.any?(issues, &(&1.rule == :end_event_exists))
    end

    test "valid process activates normally with validation enabled" do
      register_simple_process()
      {:ok, pid} = RodarBpmn.Process.start_link(@process_id)

      assert :ok = RodarBpmn.Process.activate(pid)
      assert RodarBpmn.Process.status(pid) == :completed
    end
  end
end
