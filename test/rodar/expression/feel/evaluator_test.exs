defmodule RodarBpmn.Expression.Feel.EvaluatorTest do
  use ExUnit.Case, async: true

  alias RodarBpmn.Expression.Feel.Evaluator

  describe "null propagation" do
    test "nil + number returns nil" do
      assert {:ok, nil} = Evaluator.evaluate({:binop, :+, {:literal, nil}, {:literal, 1}}, %{})
    end

    test "number + nil returns nil" do
      assert {:ok, nil} = Evaluator.evaluate({:binop, :+, {:literal, 1}, {:literal, nil}}, %{})
    end

    test "nil * number returns nil" do
      assert {:ok, nil} = Evaluator.evaluate({:binop, :*, {:literal, nil}, {:literal, 5}}, %{})
    end

    test "nil > number returns false" do
      assert {:ok, false} = Evaluator.evaluate({:binop, :>, {:literal, nil}, {:literal, 5}}, %{})
    end

    test "number < nil returns false" do
      assert {:ok, false} = Evaluator.evaluate({:binop, :<, {:literal, 5}, {:literal, nil}}, %{})
    end

    test "nil = nil returns true" do
      assert {:ok, true} =
               Evaluator.evaluate({:binop, :==, {:literal, nil}, {:literal, nil}}, %{})
    end

    test "nil != 5 returns true" do
      assert {:ok, true} = Evaluator.evaluate({:binop, :!=, {:literal, nil}, {:literal, 5}}, %{})
    end

    test "unary negation of nil returns nil" do
      assert {:ok, nil} = Evaluator.evaluate({:unary, :-, {:literal, nil}}, %{})
    end
  end

  describe "three-valued boolean logic" do
    test "true and nil returns nil" do
      assert {:ok, nil} =
               Evaluator.evaluate({:binop, :and, {:literal, true}, {:literal, nil}}, %{})
    end

    test "false and nil returns false" do
      assert {:ok, false} =
               Evaluator.evaluate({:binop, :and, {:literal, false}, {:literal, nil}}, %{})
    end

    test "nil and true returns nil" do
      assert {:ok, nil} =
               Evaluator.evaluate({:binop, :and, {:literal, nil}, {:literal, true}}, %{})
    end

    test "nil and false returns false" do
      assert {:ok, false} =
               Evaluator.evaluate({:binop, :and, {:literal, nil}, {:literal, false}}, %{})
    end

    test "true or nil returns true" do
      assert {:ok, true} =
               Evaluator.evaluate({:binop, :or, {:literal, true}, {:literal, nil}}, %{})
    end

    test "false or nil returns nil" do
      assert {:ok, nil} =
               Evaluator.evaluate({:binop, :or, {:literal, false}, {:literal, nil}}, %{})
    end

    test "nil or true returns true" do
      assert {:ok, true} =
               Evaluator.evaluate({:binop, :or, {:literal, nil}, {:literal, true}}, %{})
    end

    test "nil or false returns nil" do
      assert {:ok, nil} =
               Evaluator.evaluate({:binop, :or, {:literal, nil}, {:literal, false}}, %{})
    end
  end

  describe "path resolution" do
    test "resolves single-segment path" do
      assert {:ok, 42} = Evaluator.evaluate({:path, ["x"]}, %{"x" => 42})
    end

    test "resolves multi-segment path" do
      bindings = %{"order" => %{"status" => "active"}}
      assert {:ok, "active"} = Evaluator.evaluate({:path, ["order", "status"]}, bindings)
    end

    test "missing path returns nil" do
      assert {:ok, nil} = Evaluator.evaluate({:path, ["missing"]}, %{})
    end

    test "nested missing path returns nil" do
      assert {:ok, nil} = Evaluator.evaluate({:path, ["a", "b", "c"]}, %{"a" => 1})
    end
  end

  describe "string concatenation" do
    test "string + string concatenates" do
      ast = {:binop, :+, {:literal, "hello "}, {:literal, "world"}}
      assert {:ok, "hello world"} = Evaluator.evaluate(ast, %{})
    end

    test "number + number adds" do
      ast = {:binop, :+, {:literal, 1}, {:literal, 2}}
      assert {:ok, 3} = Evaluator.evaluate(ast, %{})
    end
  end

  describe "in operator" do
    test "value in list" do
      ast = {:in, {:literal, 2}, {:list, [{:literal, 1}, {:literal, 2}, {:literal, 3}]}}
      assert {:ok, true} = Evaluator.evaluate(ast, %{})
    end

    test "value not in list" do
      ast = {:in, {:literal, 4}, {:list, [{:literal, 1}, {:literal, 2}, {:literal, 3}]}}
      assert {:ok, false} = Evaluator.evaluate(ast, %{})
    end

    test "value in range" do
      ast = {:in, {:literal, 5}, {:range, {:literal, 1}, {:literal, 10}}}
      assert {:ok, true} = Evaluator.evaluate(ast, %{})
    end

    test "value outside range" do
      ast = {:in, {:literal, 15}, {:range, {:literal, 1}, {:literal, 10}}}
      assert {:ok, false} = Evaluator.evaluate(ast, %{})
    end

    test "nil in list returns nil" do
      ast = {:in, {:literal, nil}, {:list, [{:literal, 1}]}}
      assert {:ok, nil} = Evaluator.evaluate(ast, %{})
    end
  end

  describe "if-then-else" do
    test "true condition returns then branch" do
      ast = {:if, {:literal, true}, {:literal, "yes"}, {:literal, "no"}}
      assert {:ok, "yes"} = Evaluator.evaluate(ast, %{})
    end

    test "false condition returns else branch" do
      ast = {:if, {:literal, false}, {:literal, "yes"}, {:literal, "no"}}
      assert {:ok, "no"} = Evaluator.evaluate(ast, %{})
    end

    test "nil condition returns else branch" do
      ast = {:if, {:literal, nil}, {:literal, "yes"}, {:literal, "no"}}
      assert {:ok, "no"} = Evaluator.evaluate(ast, %{})
    end
  end

  describe "bracket access" do
    test "map bracket access with string key" do
      ast = {:bracket, {:path, ["data"]}, {:literal, "key"}}
      assert {:ok, "value"} = Evaluator.evaluate(ast, %{"data" => %{"key" => "value"}})
    end

    test "nil base returns nil" do
      ast = {:bracket, {:path, ["missing"]}, {:literal, "key"}}
      assert {:ok, nil} = Evaluator.evaluate(ast, %{})
    end

    test "list bracket access with index" do
      ast = {:bracket, {:path, ["items"]}, {:literal, 0}}
      assert {:ok, "first"} = Evaluator.evaluate(ast, %{"items" => ["first", "second"]})
    end
  end

  describe "function calls" do
    test "calls built-in function" do
      ast = {:funcall, "abs", [{:literal, -5}]}
      assert {:ok, 5} = Evaluator.evaluate(ast, %{})
    end

    test "calls multi-word function" do
      ast = {:funcall, "string length", [{:literal, "hello"}]}
      assert {:ok, 5} = Evaluator.evaluate(ast, %{})
    end

    test "returns error for unknown function" do
      ast = {:funcall, "unknown_func", [{:literal, 1}]}
      assert {:error, _} = Evaluator.evaluate(ast, %{})
    end
  end

  describe "arithmetic" do
    test "division" do
      ast = {:binop, :/, {:literal, 10}, {:literal, 3}}
      {:ok, result} = Evaluator.evaluate(ast, %{})
      assert_in_delta result, 3.333, 0.01
    end

    test "division by zero returns error" do
      ast = {:binop, :/, {:literal, 10}, {:literal, 0}}
      assert {:error, "division by zero"} = Evaluator.evaluate(ast, %{})
    end

    test "modulo" do
      ast = {:binop, :%, {:literal, 7}, {:literal, 3}}
      assert {:ok, 1} = Evaluator.evaluate(ast, %{})
    end

    test "exponentiation" do
      ast = {:binop, :**, {:literal, 2}, {:literal, 3}}
      {:ok, result} = Evaluator.evaluate(ast, %{})
      assert_in_delta result, 8.0, 0.001
    end
  end

  describe "list evaluation" do
    test "evaluates list elements" do
      ast = {:list, [{:literal, 1}, {:literal, 2}, {:literal, 3}]}
      assert {:ok, [1, 2, 3]} = Evaluator.evaluate(ast, %{})
    end

    test "evaluates empty list" do
      assert {:ok, []} = Evaluator.evaluate({:list, []}, %{})
    end
  end
end
