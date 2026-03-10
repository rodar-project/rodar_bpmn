defmodule Mix.Tasks.RodarBpmn.ValidateTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.RodarBpmn.Validate

  import ExUnit.CaptureIO

  describe "run/1" do
    test "valid BPMN file passes validation" do
      output =
        capture_io(fn ->
          Validate.run(["test/fixtures/simple.bpmn"])
        end)

      assert output =~ "OK"
    end

    test "file with issues shows errors" do
      assert_raise Mix.Error, ~r/Validation failed/, fn ->
        capture_io(fn ->
          Validate.run(["priv/bpmn/examples/user_login.bpmn"])
        end)
      end
    end

    test "prints usage on missing arguments" do
      output =
        capture_io(:stderr, fn ->
          Validate.run([])
        end)

      assert output =~ "Usage:"
    end
  end
end
