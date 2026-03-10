defmodule Mix.Tasks.Bpmn.InspectTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  describe "run/1" do
    test "prints element summary for a BPMN file" do
      output =
        capture_io(fn ->
          Mix.Tasks.Bpmn.Inspect.run(["test/fixtures/simple.bpmn"])
        end)

      assert output =~ "Process:"
      assert output =~ "Elements:"
      assert output =~ "bpmn_event_start"
      assert output =~ "bpmn_event_end"
    end

    test "prints usage on missing arguments" do
      output =
        capture_io(:stderr, fn ->
          Mix.Tasks.Bpmn.Inspect.run([])
        end)

      assert output =~ "Usage:"
    end
  end
end
