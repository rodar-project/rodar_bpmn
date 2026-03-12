defmodule Mix.Tasks.RodarBpmn.ScaffoldTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.RodarBpmn.Scaffold

  import ExUnit.CaptureIO

  @sequential_flow "test/fixtures/conformance/execution/01_sequential_flow.bpmn"
  @miwg_b10 "test/fixtures/conformance/miwg/B.1.0.bpmn"

  describe "run/1 --dry-run" do
    test "prints generated modules to stdout" do
      output =
        capture_io(fn ->
          Scaffold.run([@sequential_flow, "--dry-run"])
        end)

      assert output =~ "defmodule"
      assert output =~ "@behaviour RodarBpmn.TaskHandler"
      assert output =~ "def token_in(_element, _context)"
    end

    test "prints multiple task modules for multi-task BPMN" do
      output =
        capture_io(fn ->
          Scaffold.run([@miwg_b10, "--dry-run"])
        end)

      assert output =~ "ServiceTask"
      assert output =~ "UserTask"
      assert output =~ "@behaviour RodarBpmn.Activity.Task.Service.Handler"
      assert output =~ "@behaviour RodarBpmn.TaskHandler"
    end

    test "respects --module-prefix" do
      output =
        capture_io(fn ->
          Scaffold.run([@sequential_flow, "--dry-run", "--module-prefix", "Custom.Prefix"])
        end)

      assert output =~ "defmodule Custom.Prefix."
    end
  end

  describe "run/1 --output-dir" do
    @tag :tmp_dir
    test "writes files to specified directory", %{tmp_dir: tmp_dir} do
      output =
        capture_io(fn ->
          Scaffold.run([@sequential_flow, "--output-dir", tmp_dir])
        end)

      assert output =~ "Created:"
      files = File.ls!(tmp_dir)
      assert "task_a.ex" in files
      assert "task_b.ex" in files

      content = File.read!(Path.join(tmp_dir, "task_a.ex"))
      assert content =~ "defmodule"
      assert content =~ "@behaviour RodarBpmn.TaskHandler"
    end

    @tag :tmp_dir
    test "generates service task with correct behaviour", %{tmp_dir: tmp_dir} do
      capture_io(fn ->
        Scaffold.run([@miwg_b10, "--output-dir", tmp_dir])
      end)

      service_file = Path.join(tmp_dir, "service_task.ex")
      assert File.exists?(service_file)

      content = File.read!(service_file)
      assert content =~ "@behaviour RodarBpmn.Activity.Task.Service.Handler"
      assert content =~ "def execute(_attrs, _data)"
    end

    @tag :tmp_dir
    test "prints registration instructions", %{tmp_dir: tmp_dir} do
      output =
        capture_io(fn ->
          Scaffold.run([@miwg_b10, "--output-dir", tmp_dir])
        end)

      assert output =~ "RodarBpmn.TaskRegistry.register("
      assert output =~ "handler_map"
    end
  end

  describe "run/1 --force" do
    @tag :tmp_dir
    test "overwrites existing files without prompting", %{tmp_dir: tmp_dir} do
      # First run
      capture_io(fn ->
        Scaffold.run([@sequential_flow, "--output-dir", tmp_dir])
      end)

      # Write custom content to a file
      File.write!(Path.join(tmp_dir, "task_a.ex"), "custom content")

      # Second run with --force
      output =
        capture_io(fn ->
          Scaffold.run([@sequential_flow, "--output-dir", tmp_dir, "--force"])
        end)

      assert output =~ "Overwritten:"
      content = File.read!(Path.join(tmp_dir, "task_a.ex"))
      assert content =~ "@behaviour RodarBpmn.TaskHandler"
    end
  end

  describe "run/1 edge cases" do
    test "prints usage on missing arguments" do
      output =
        capture_io(:stderr, fn ->
          Scaffold.run([])
        end)

      assert output =~ "Usage:"
    end

    test "reports no tasks for event-only BPMN" do
      # Create a minimal BPMN with only events
      bpmn = """
      <?xml version="1.0" encoding="UTF-8"?>
      <bpmn:definitions xmlns:bpmn="http://www.omg.org/spec/BPMN/20100524/MODEL" id="D1">
        <bpmn:process id="P1" isExecutable="true">
          <bpmn:startEvent id="Start_1">
            <bpmn:outgoing>Flow_1</bpmn:outgoing>
          </bpmn:startEvent>
          <bpmn:endEvent id="End_1">
            <bpmn:incoming>Flow_1</bpmn:incoming>
          </bpmn:endEvent>
          <bpmn:sequenceFlow id="Flow_1" sourceRef="Start_1" targetRef="End_1"/>
        </bpmn:process>
      </bpmn:definitions>
      """

      tmp = Path.join(System.tmp_dir!(), "scaffold_test_no_tasks.bpmn")
      File.write!(tmp, bpmn)

      output =
        capture_io(fn ->
          Scaffold.run([tmp, "--dry-run"])
        end)

      assert output =~ "No actionable tasks found"
    after
      File.rm(Path.join(System.tmp_dir!(), "scaffold_test_no_tasks.bpmn"))
    end
  end
end
