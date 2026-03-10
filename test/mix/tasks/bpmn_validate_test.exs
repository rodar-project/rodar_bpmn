defmodule Mix.Tasks.Bpmn.ValidateTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  describe "run/1" do
    test "valid BPMN file passes validation" do
      output =
        capture_io(fn ->
          Mix.Tasks.Bpmn.Validate.run(["test/fixtures/simple.bpmn"])
        end)

      assert output =~ "OK"
    end

    test "file with issues shows errors" do
      assert_raise Mix.Error, ~r/Validation failed/, fn ->
        capture_io(fn ->
          Mix.Tasks.Bpmn.Validate.run(["priv/bpmn/examples/user_login.bpmn"])
        end)
      end
    end

    test "prints usage on missing arguments" do
      output =
        capture_io(:stderr, fn ->
          Mix.Tasks.Bpmn.Validate.run([])
        end)

      assert output =~ "Usage:"
    end
  end
end
