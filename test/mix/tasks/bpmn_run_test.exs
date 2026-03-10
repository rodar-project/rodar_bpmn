defmodule Mix.Tasks.Bpmn.RunTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  describe "run/1" do
    test "executes a simple BPMN process and prints result" do
      output =
        capture_io(fn ->
          Mix.Tasks.Bpmn.Run.run(["test/fixtures/simple.bpmn"])
        end)

      assert output =~ "Running process:"
      assert output =~ "Status:"
    end

    test "accepts --data flag with JSON" do
      output =
        capture_io(fn ->
          Mix.Tasks.Bpmn.Run.run([
            "test/fixtures/simple.bpmn",
            "--data",
            ~S|{"username": "alice"}|
          ])
        end)

      assert output =~ "Running process:"
    end

    test "prints usage on missing arguments" do
      output =
        capture_io(:stderr, fn ->
          Mix.Tasks.Bpmn.Run.run([])
        end)

      assert output =~ "Usage:"
    end
  end
end
