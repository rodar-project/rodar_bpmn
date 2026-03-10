defmodule Bpmn.Expression.SandboxTest do
  use ExUnit.Case, async: true

  doctest Bpmn.Expression.Sandbox

  describe "safe expressions" do
    test "evaluates arithmetic" do
      assert {:ok, 7} = Bpmn.Expression.Sandbox.eval("3 + 4")
      assert {:ok, 6} = Bpmn.Expression.Sandbox.eval("2 * 3")
      assert {:ok, 2.0} = Bpmn.Expression.Sandbox.eval("10 / 5")
      assert {:ok, 1} = Bpmn.Expression.Sandbox.eval("rem(7, 3)")
    end

    test "evaluates comparisons" do
      assert {:ok, true} = Bpmn.Expression.Sandbox.eval("1 < 2")
      assert {:ok, false} = Bpmn.Expression.Sandbox.eval("1 > 2")
      assert {:ok, true} = Bpmn.Expression.Sandbox.eval("1 == 1")
      assert {:ok, false} = Bpmn.Expression.Sandbox.eval("1 != 1")
      assert {:ok, true} = Bpmn.Expression.Sandbox.eval("1 >= 1")
      assert {:ok, true} = Bpmn.Expression.Sandbox.eval("1 <= 1")
    end

    test "evaluates boolean logic" do
      assert {:ok, true} = Bpmn.Expression.Sandbox.eval("true and true")
      assert {:ok, false} = Bpmn.Expression.Sandbox.eval("true and false")
      assert {:ok, true} = Bpmn.Expression.Sandbox.eval("true or false")
      assert {:ok, false} = Bpmn.Expression.Sandbox.eval("not true")
      assert {:ok, true} = Bpmn.Expression.Sandbox.eval("!false")
    end

    test "evaluates string operations" do
      assert {:ok, "hello world"} = Bpmn.Expression.Sandbox.eval(~S|"hello" <> " world"|)
      assert {:ok, 5} = Bpmn.Expression.Sandbox.eval(~S|String.length("hello")|)
      assert {:ok, true} = Bpmn.Expression.Sandbox.eval(~S|String.contains?("hello", "ell")|)
      assert {:ok, "HELLO"} = Bpmn.Expression.Sandbox.eval(~S|String.upcase("hello")|)
    end

    test "evaluates data access via bindings" do
      bindings = %{"data" => %{"count" => 10, "name" => "test"}}
      assert {:ok, true} = Bpmn.Expression.Sandbox.eval(~S|data["count"] > 5|, bindings)
      assert {:ok, "test"} = Bpmn.Expression.Sandbox.eval(~S|data["name"]|, bindings)
    end

    test "evaluates map and list operations" do
      assert {:ok, 3} = Bpmn.Expression.Sandbox.eval("length([1, 2, 3])")
      assert {:ok, "b"} = Bpmn.Expression.Sandbox.eval(~S|Map.get(%{"a" => "b"}, "a")|)
      assert {:ok, true} = Bpmn.Expression.Sandbox.eval(~S|Map.has_key?(%{"a" => 1}, "a")|)
      assert {:ok, 1} = Bpmn.Expression.Sandbox.eval("List.first([1, 2, 3])")
      assert {:ok, 3} = Bpmn.Expression.Sandbox.eval("List.last([1, 2, 3])")
    end

    test "evaluates if/else" do
      assert {:ok, "yes"} = Bpmn.Expression.Sandbox.eval(~S|if true, do: "yes", else: "no"|)
      assert {:ok, "no"} = Bpmn.Expression.Sandbox.eval(~S|if false, do: "yes", else: "no"|)
    end

    test "evaluates case expressions" do
      expr = """
      case data["status"] do
        "active" -> true
        _ -> false
      end
      """

      bindings = %{"data" => %{"status" => "active"}}
      assert {:ok, true} = Bpmn.Expression.Sandbox.eval(expr, bindings)

      bindings = %{"data" => %{"status" => "inactive"}}
      assert {:ok, false} = Bpmn.Expression.Sandbox.eval(expr, bindings)
    end

    test "evaluates pipes" do
      assert {:ok, "HELLO"} = Bpmn.Expression.Sandbox.eval(~S["hello" |> String.upcase()])
    end

    test "evaluates nil check" do
      assert {:ok, true} = Bpmn.Expression.Sandbox.eval("data == nil", %{"data" => nil})
      assert {:ok, true} = Bpmn.Expression.Sandbox.eval("is_nil(data)", %{"data" => nil})
    end

    test "evaluates empty string as nil" do
      assert {:ok, nil} = Bpmn.Expression.Sandbox.eval("")
    end

    test "evaluates Enum functions" do
      assert {:ok, 3} = Bpmn.Expression.Sandbox.eval("Enum.count([1, 2, 3])")
      assert {:ok, true} = Bpmn.Expression.Sandbox.eval("Enum.member?([1, 2, 3], 2)")
      assert {:ok, true} = Bpmn.Expression.Sandbox.eval("Enum.any?([false, true, false])")
    end

    test "evaluates cond expressions" do
      expr = """
      cond do
        data["x"] > 10 -> "high"
        data["x"] > 5 -> "medium"
        true -> "low"
      end
      """

      assert {:ok, "high"} = Bpmn.Expression.Sandbox.eval(expr, %{"data" => %{"x" => 15}})
      assert {:ok, "medium"} = Bpmn.Expression.Sandbox.eval(expr, %{"data" => %{"x" => 7}})
      assert {:ok, "low"} = Bpmn.Expression.Sandbox.eval(expr, %{"data" => %{"x" => 2}})
    end
  end

  describe "rejected expressions" do
    test "rejects System calls" do
      assert {:error, "disallowed: module call System.cmd/2"} =
               Bpmn.Expression.Sandbox.eval(~S|System.cmd("ls", [])|)
    end

    test "rejects File calls" do
      assert {:error, "disallowed: module call File.read!/1"} =
               Bpmn.Expression.Sandbox.eval(~S|File.read!("/etc/passwd")|)
    end

    test "rejects Code calls" do
      assert {:error, "disallowed: module call Code.eval_string/1"} =
               Bpmn.Expression.Sandbox.eval(~S|Code.eval_string("1")|)
    end

    test "rejects Process calls" do
      assert {:error, _} =
               Bpmn.Expression.Sandbox.eval(~S|Process.exit(self(), :kill)|)
    end

    test "rejects IO calls" do
      assert {:error, _} = Bpmn.Expression.Sandbox.eval(~S|IO.puts("hello")|)
    end

    test "rejects Port calls" do
      assert {:error, _} =
               Bpmn.Expression.Sandbox.eval(~S|Port.open({:spawn, "ls"}, [:binary])|)
    end

    test "rejects Node calls" do
      assert {:error, _} = Bpmn.Expression.Sandbox.eval(~S|Node.self()|)
    end

    test "rejects fn definitions" do
      assert {:error, _} = Bpmn.Expression.Sandbox.eval("fn x -> x end")
    end

    test "rejects receive" do
      assert {:error, _} =
               Bpmn.Expression.Sandbox.eval("receive do msg -> msg after 0 -> nil end")
    end

    test "rejects import/require/use" do
      assert {:error, _} = Bpmn.Expression.Sandbox.eval("import Enum")
      assert {:error, _} = Bpmn.Expression.Sandbox.eval("require Logger")
    end

    test "rejects arbitrary atoms" do
      assert {:error, "disallowed: atom :dangerous"} =
               Bpmn.Expression.Sandbox.eval(":dangerous")
    end

    test "rejects Kernel.apply" do
      assert {:error, _} = Bpmn.Expression.Sandbox.eval(~S|Kernel.apply(System, :cmd, [])|)
    end

    test "rejects spawn" do
      assert {:error, _} = Bpmn.Expression.Sandbox.eval("spawn(fn -> nil end)")
    end

    test "rejects send" do
      assert {:error, _} = Bpmn.Expression.Sandbox.eval(~S|send(self(), :msg)|)
    end
  end

  describe "safe?/1" do
    test "returns true for safe AST" do
      {:ok, ast} = Code.string_to_quoted("1 + 2")
      assert Bpmn.Expression.Sandbox.safe?(ast) == true
    end

    test "returns error tuple for unsafe AST" do
      {:ok, ast} = Code.string_to_quoted(~S|System.cmd("ls", [])|)
      assert {:error, _} = Bpmn.Expression.Sandbox.safe?(ast)
    end
  end

  describe "runtime errors" do
    test "returns error for runtime exceptions" do
      assert {:error, "runtime error:" <> _} = Bpmn.Expression.Sandbox.eval("1 / 0")
    end

    test "returns error for parse failures" do
      assert {:error, "parse error:" <> _} = Bpmn.Expression.Sandbox.eval("1 +")
    end
  end
end
