defmodule Mix.Tasks.RodarBpmn.RunTest do
  use ExUnit.Case, async: false

  alias Mix.Tasks.RodarBpmn.Run

  import ExUnit.CaptureIO

  describe "run/1" do
    test "executes a simple BPMN process with step-by-step output" do
      output =
        capture_io(fn ->
          Run.run(["test/fixtures/simple.bpmn"])
        end)

      assert output =~ "Simple Process"
      assert output =~ "--- Execution ---"
      assert output =~ "[OK]"
      assert output =~ "Start"
      assert output =~ "--- Result ---"
      assert output =~ "Status: completed"
    end

    test "accepts --data flag with JSON and passes data to execution" do
      output =
        capture_io(fn ->
          Run.run([
            "test/fixtures/simple.bpmn",
            "--data",
            ~S|{"username": "alice"}|
          ])
        end)

      assert output =~ "Simple Process"
      assert output =~ "Status: completed"
      assert output =~ "username"
      assert output =~ "alice"
    end

    test "prints usage on missing arguments" do
      output =
        capture_io(:stderr, fn ->
          Run.run([])
        end)

      assert output =~ "Usage:"
    end
  end

  describe "passthrough service tasks" do
    test "passes through unhandled service tasks and suggests scaffold" do
      output =
        capture_io(fn ->
          Run.run(["test/fixtures/run_service_tasks.bpmn"])
        end)

      assert output =~ "Service tasks without handlers (will pass through):"
      assert output =~ "Validate Order"
      assert output =~ "Fulfill Order"
      assert output =~ "[PASS]"
      assert output =~ "Status: completed"
      assert output =~ "passthrough"
      assert output =~ "mix rodar_bpmn.scaffold"
    end

    test "cleans up TaskRegistry entries after run" do
      capture_io(fn ->
        Run.run(["test/fixtures/run_service_tasks.bpmn"])
      end)

      assert RodarBpmn.TaskRegistry.lookup("Task_Validate") == :error
      assert RodarBpmn.TaskRegistry.lookup("Task_Fulfill") == :error
    end
  end

  describe "user task interaction" do
    test "prompts for input at user task in interactive mode" do
      output =
        capture_io([input: ~S|{"approved": true}| <> "\n"], fn ->
          Run.run(["test/fixtures/run_user_task.bpmn"])
        end)

      assert output =~ "[WAIT]"
      assert output =~ "Manager Approval"
      assert output =~ "Waiting for input"
      assert output =~ "approved"
      assert output =~ "resumed"
      assert output =~ "Status: completed"
    end

    test "skips user task prompt with --non-interactive" do
      output =
        capture_io(fn ->
          Run.run(["test/fixtures/run_user_task.bpmn", "--non-interactive"])
        end)

      assert output =~ "[WAIT]"
      assert output =~ "non-interactive"
      assert output =~ "Status: suspended"
    end

    test "handles skip input at user task" do
      output =
        capture_io([input: "skip\n"], fn ->
          Run.run(["test/fixtures/run_user_task.bpmn"])
        end)

      assert output =~ "Skipped"
      assert output =~ "Status: suspended"
    end
  end

  describe "data inference" do
    test "shows detected data keys in header" do
      output =
        capture_io([input: "skip\n"], fn ->
          Run.run(["test/fixtures/run_user_task.bpmn"])
        end)

      assert output =~ "Data keys in conditions: approved"
    end
  end

  describe "handler discovery" do
    test "runs discovery and prints discovered handlers when found" do
      # With no handlers at the conventional path, all tasks are not_found
      # and fall through to passthrough registration as before
      output =
        capture_io(fn ->
          Run.run(["test/fixtures/run_service_tasks.bpmn"])
        end)

      # Discovery runs but finds nothing, so passthrough still works
      assert output =~ "Service tasks without handlers (will pass through):"
      assert output =~ "Status: completed"
    end
  end

  describe "header output" do
    test "shows element counts" do
      output =
        capture_io(fn ->
          Run.run(["test/fixtures/run_service_tasks.bpmn"])
        end)

      assert output =~ "Elements:"
      assert output =~ "events"
      assert output =~ "tasks"
    end
  end
end
