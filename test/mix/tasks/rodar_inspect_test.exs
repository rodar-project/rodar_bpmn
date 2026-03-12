defmodule Mix.Tasks.Rodar.InspectTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.Rodar.Inspect

  import ExUnit.CaptureIO

  describe "run/1" do
    test "prints element summary for a BPMN file" do
      output =
        capture_io(fn ->
          Inspect.run(["test/fixtures/simple.bpmn"])
        end)

      assert output =~ "Process:"
      assert output =~ "Elements:"
      assert output =~ "bpmn_event_start"
      assert output =~ "bpmn_event_end"
    end

    test "prints usage on missing arguments" do
      output =
        capture_io(:stderr, fn ->
          Inspect.run([])
        end)

      assert output =~ "Usage:"
    end
  end
end
