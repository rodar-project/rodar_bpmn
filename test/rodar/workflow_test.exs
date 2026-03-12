defmodule Rodar.WorkflowTest do
  use ExUnit.Case, async: true

  alias Rodar.Workflow

  @fixture_path Path.join([__DIR__, "..", "fixtures", "run_user_task.bpmn"])
  @process_id "workflow-test-#{:erlang.unique_integer([:positive])}"

  setup do
    {:ok, _diagram} =
      Workflow.setup(
        bpmn_file: @fixture_path,
        process_id: @process_id
      )

    :ok
  end

  describe "setup/1" do
    test "loads BPMN and registers definition" do
      id = "setup-test-#{:erlang.unique_integer([:positive])}"

      assert {:ok, diagram} =
               Workflow.setup(
                 bpmn_file: @fixture_path,
                 process_id: id
               )

      assert is_map(diagram)
      assert {:ok, _} = Rodar.Registry.lookup(id)
    end

    test "returns error for missing file" do
      assert {:error, :enoent} =
               Workflow.setup(
                 bpmn_file: "nonexistent.bpmn",
                 process_id: "nope"
               )
    end
  end

  describe "start_process/2" do
    test "creates and activates a process instance" do
      {:ok, pid} = Workflow.start_process(@process_id, %{"item" => "widget"})
      assert is_pid(pid)
      assert Workflow.process_status(pid) == :suspended
    end

    test "sets data before activation" do
      {:ok, pid} = Workflow.start_process(@process_id, %{"item" => "widget", "amount" => 100})
      data = Workflow.process_data(pid)
      assert data["item"] == "widget"
      assert data["amount"] == 100
    end

    test "starts with empty data" do
      {:ok, pid} = Workflow.start_process(@process_id)
      assert is_pid(pid)
    end
  end

  describe "resume_user_task/3" do
    test "resumes user task and routes through gateway (approved)" do
      {:ok, pid} = Workflow.start_process(@process_id)
      assert Workflow.process_status(pid) == :suspended

      Workflow.resume_user_task(pid, "Task_Approval", %{"approved" => true})
      assert Workflow.process_status(pid) == :completed
    end

    test "resumes user task and routes through gateway (rejected)" do
      {:ok, pid} = Workflow.start_process(@process_id)

      Workflow.resume_user_task(pid, "Task_Approval", %{"approved" => false})
      assert Workflow.process_status(pid) == :completed
    end

    test "returns error for non-existent task" do
      {:ok, pid} = Workflow.start_process(@process_id)

      assert {:error, "Task 'Nonexistent' not found in process"} =
               Workflow.resume_user_task(pid, "Nonexistent", %{})
    end

    test "returns error for non-user task" do
      {:ok, pid} = Workflow.start_process(@process_id)

      assert {:error, msg} = Workflow.resume_user_task(pid, "Gateway_1", %{})
      assert msg =~ "not a user task"
    end
  end

  describe "process_status/1" do
    test "returns current status" do
      {:ok, pid} = Workflow.start_process(@process_id)
      assert Workflow.process_status(pid) == :suspended
    end
  end

  describe "process_data/1" do
    test "returns current data map" do
      {:ok, pid} = Workflow.start_process(@process_id, %{"key" => "value"})
      assert Workflow.process_data(pid)["key"] == "value"
    end
  end

  describe "process_history/1" do
    test "returns execution history" do
      {:ok, pid} = Workflow.start_process(@process_id)
      history = Workflow.process_history(pid)
      assert is_list(history)
      assert history != []
    end
  end

  describe "use Rodar.Workflow" do
    defmodule TestWorkflow do
      use Rodar.Workflow,
        bpmn_file: Path.join([__DIR__, "..", "fixtures", "run_user_task.bpmn"]),
        process_id: "macro-workflow-test"
    end

    test "injects setup/0" do
      assert {:ok, _} = TestWorkflow.setup()
    end

    test "injects start_process/1" do
      TestWorkflow.setup()
      assert {:ok, pid} = TestWorkflow.start_process(%{"item" => "test"})
      assert is_pid(pid)
    end

    test "injects resume_user_task/3" do
      TestWorkflow.setup()
      {:ok, pid} = TestWorkflow.start_process()
      assert :suspended = TestWorkflow.process_status(pid)
      TestWorkflow.resume_user_task(pid, "Task_Approval", %{"approved" => true})
      assert :completed = TestWorkflow.process_status(pid)
    end

    test "injects process_data/1" do
      TestWorkflow.setup()
      {:ok, pid} = TestWorkflow.start_process(%{"x" => 1})
      assert TestWorkflow.process_data(pid)["x"] == 1
    end

    test "injects process_history/1" do
      TestWorkflow.setup()
      {:ok, pid} = TestWorkflow.start_process()
      assert is_list(TestWorkflow.process_history(pid))
    end
  end
end
