defmodule Rodar.Expression.TestHelpersTest do
  use ExUnit.Case, async: true

  alias Rodar.Expression.TestHelpers

  doctest Rodar.Expression.TestHelpers

  describe "eval_expression/2" do
    test "evaluates expression with data bindings" do
      assert {:ok, true} =
               TestHelpers.eval_expression(
                 ~s(data["count"] > 5),
                 %{"count" => 10}
               )
    end

    test "evaluates simple arithmetic" do
      assert {:ok, 42} = TestHelpers.eval_expression("6 * 7", %{})
    end

    test "rejects unsafe expressions" do
      assert {:error, _} =
               TestHelpers.eval_expression(~S|System.cmd("ls", [])|, %{})
    end
  end

  describe "validate/1" do
    test "returns :ok for safe expressions" do
      assert :ok = TestHelpers.validate("1 + 2")
      assert :ok = TestHelpers.validate(~s(data["key"] == "value"))
    end

    test "returns error for unsafe expressions" do
      assert {:error, _} = TestHelpers.validate(~S|System.cmd("ls", [])|)
      assert {:error, _} = TestHelpers.validate(~S|File.read!("/etc/passwd")|)
    end

    test "returns error for unparseable expressions" do
      assert {:error, "parse error:" <> _} = TestHelpers.validate("1 +")
    end
  end
end
