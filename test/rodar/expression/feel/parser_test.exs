defmodule Rodar.Expression.Feel.ParserTest do
  use ExUnit.Case, async: true

  alias Rodar.Expression.Feel.Parser

  describe "literals" do
    test "parses integers" do
      assert {:ok, {:literal, 42}} = Parser.parse("42")
      assert {:ok, {:literal, 0}} = Parser.parse("0")
    end

    test "parses floats" do
      assert {:ok, {:literal, 3.14}} = Parser.parse("3.14")
      assert {:ok, {:literal, 0.5}} = Parser.parse("0.5")
    end

    test "parses strings" do
      assert {:ok, {:literal, "hello"}} = Parser.parse(~S("hello"))
      assert {:ok, {:literal, ""}} = Parser.parse(~S(""))
      assert {:ok, {:literal, "a\"b"}} = Parser.parse(~S("a\"b"))
    end

    test "parses booleans" do
      assert {:ok, {:literal, true}} = Parser.parse("true")
      assert {:ok, {:literal, false}} = Parser.parse("false")
    end

    test "parses null" do
      assert {:ok, {:literal, nil}} = Parser.parse("null")
    end

    test "does not parse identifiers starting with keywords" do
      assert {:ok, {:path, ["trueish"]}} = Parser.parse("trueish")
      assert {:ok, {:path, ["nullable"]}} = Parser.parse("nullable")
      assert {:ok, {:path, ["falsehood"]}} = Parser.parse("falsehood")
    end
  end

  describe "arithmetic" do
    test "parses addition" do
      assert {:ok, {:binop, :+, {:literal, 1}, {:literal, 2}}} = Parser.parse("1 + 2")
    end

    test "parses subtraction" do
      assert {:ok, {:binop, :-, {:literal, 5}, {:literal, 3}}} = Parser.parse("5 - 3")
    end

    test "parses multiplication" do
      assert {:ok, {:binop, :*, {:literal, 2}, {:literal, 3}}} = Parser.parse("2 * 3")
    end

    test "parses division" do
      assert {:ok, {:binop, :/, {:literal, 10}, {:literal, 2}}} = Parser.parse("10 / 2")
    end

    test "parses modulo" do
      assert {:ok, {:binop, :%, {:literal, 7}, {:literal, 3}}} = Parser.parse("7 % 3")
    end

    test "parses exponentiation" do
      assert {:ok, {:binop, :**, {:literal, 2}, {:literal, 3}}} = Parser.parse("2 ** 3")
    end

    test "respects precedence: multiplication before addition" do
      {:ok, ast} = Parser.parse("1 + 2 * 3")
      assert {:binop, :+, {:literal, 1}, {:binop, :*, {:literal, 2}, {:literal, 3}}} = ast
    end

    test "respects left associativity" do
      {:ok, ast} = Parser.parse("1 - 2 - 3")
      assert {:binop, :-, {:binop, :-, {:literal, 1}, {:literal, 2}}, {:literal, 3}} = ast
    end
  end

  describe "comparisons" do
    test "parses equality (FEEL = is equality)" do
      assert {:ok, {:binop, :==, {:literal, 1}, {:literal, 1}}} = Parser.parse("1 = 1")
    end

    test "parses inequality" do
      assert {:ok, {:binop, :!=, {:literal, 1}, {:literal, 2}}} = Parser.parse("1 != 2")
    end

    test "parses less than" do
      assert {:ok, {:binop, :<, {:literal, 1}, {:literal, 2}}} = Parser.parse("1 < 2")
    end

    test "parses greater than" do
      assert {:ok, {:binop, :>, {:literal, 2}, {:literal, 1}}} = Parser.parse("2 > 1")
    end

    test "parses less than or equal" do
      assert {:ok, {:binop, :<=, {:literal, 1}, {:literal, 2}}} = Parser.parse("1 <= 2")
    end

    test "parses greater than or equal" do
      assert {:ok, {:binop, :>=, {:literal, 2}, {:literal, 1}}} = Parser.parse("2 >= 1")
    end
  end

  describe "boolean operators" do
    test "parses and" do
      {:ok, ast} = Parser.parse("true and false")
      assert {:binop, :and, {:literal, true}, {:literal, false}} = ast
    end

    test "parses or" do
      {:ok, ast} = Parser.parse("true or false")
      assert {:binop, :or, {:literal, true}, {:literal, false}} = ast
    end

    test "parses not" do
      {:ok, ast} = Parser.parse("not true")
      assert {:unary, :not, {:literal, true}} = ast
    end

    test "and binds tighter than or" do
      {:ok, ast} = Parser.parse("true or false and true")

      assert {:binop, :or, {:literal, true}, {:binop, :and, {:literal, false}, {:literal, true}}} =
               ast
    end
  end

  describe "paths" do
    test "parses single identifier" do
      assert {:ok, {:path, ["x"]}} = Parser.parse("x")
    end

    test "parses dotted path" do
      assert {:ok, {:path, ["a", "b", "c"]}} = Parser.parse("a.b.c")
    end
  end

  describe "bracket access" do
    test "parses string key bracket access" do
      {:ok, ast} = Parser.parse(~S(a["key"]))
      assert {:bracket, {:path, ["a"]}, {:literal, "key"}} = ast
    end

    test "parses numeric index bracket access" do
      {:ok, ast} = Parser.parse("a[0]")
      assert {:bracket, {:path, ["a"]}, {:literal, 0}} = ast
    end
  end

  describe "if-then-else" do
    test "parses if-then-else" do
      {:ok, ast} = Parser.parse(~S(if x > 10 then "high" else "low"))

      assert {:if, {:binop, :>, {:path, ["x"]}, {:literal, 10}}, {:literal, "high"},
              {:literal, "low"}} = ast
    end
  end

  describe "in operator" do
    test "parses in with list" do
      {:ok, ast} = Parser.parse(~S(x in [1, 2, 3]))
      assert {:in, {:path, ["x"]}, {:list, [{:literal, 1}, {:literal, 2}, {:literal, 3}]}} = ast
    end

    test "parses in with range" do
      {:ok, ast} = Parser.parse("x in 1..10")
      assert {:in, {:path, ["x"]}, {:range, {:literal, 1}, {:literal, 10}}} = ast
    end
  end

  describe "function calls" do
    test "parses single-word function call" do
      {:ok, ast} = Parser.parse("abs(-5)")
      assert {:funcall, "abs", [{:unary, :-, {:literal, 5}}]} = ast
    end

    test "parses multi-argument function call" do
      {:ok, ast} = Parser.parse("round(3.14, 1)")
      assert {:funcall, "round", [{:literal, 3.14}, {:literal, 1}]} = ast
    end

    test "parses space-named function: string length" do
      {:ok, ast} = Parser.parse(~S|string length("hello")|)
      assert {:funcall, "string length", [{:literal, "hello"}]} = ast
    end

    test "parses space-named function: starts with" do
      {:ok, ast} = Parser.parse(~S|starts with("hello", "he")|)
      assert {:funcall, "starts with", [{:literal, "hello"}, {:literal, "he"}]} = ast
    end

    test "parses space-named function: is null" do
      {:ok, ast} = Parser.parse("is null(x)")
      assert {:funcall, "is null", [{:path, ["x"]}]} = ast
    end

    test "parses zero-argument function call" do
      {:ok, ast} = Parser.parse("count([])")
      assert {:funcall, "count", [{:list, []}]} = ast
    end
  end

  describe "list literals" do
    test "parses empty list" do
      assert {:ok, {:list, []}} = Parser.parse("[]")
    end

    test "parses list of numbers" do
      {:ok, ast} = Parser.parse("[1, 2, 3]")
      assert {:list, [{:literal, 1}, {:literal, 2}, {:literal, 3}]} = ast
    end

    test "parses list of strings" do
      {:ok, ast} = Parser.parse(~S(["a", "b"]))
      assert {:list, [{:literal, "a"}, {:literal, "b"}]} = ast
    end
  end

  describe "unary operators" do
    test "parses unary negation" do
      assert {:ok, {:unary, :-, {:literal, 5}}} = Parser.parse("-5")
    end
  end

  describe "parenthesized expressions" do
    test "parses parenthesized expression" do
      {:ok, ast} = Parser.parse("(1 + 2) * 3")
      assert {:binop, :*, {:binop, :+, {:literal, 1}, {:literal, 2}}, {:literal, 3}} = ast
    end
  end

  describe "complex expressions" do
    test "parses compound boolean with comparisons" do
      {:ok, ast} = Parser.parse(~S(amount > 1000 and status = "approved"))

      assert {:binop, :and, {:binop, :>, {:path, ["amount"]}, {:literal, 1000}},
              {:binop, :==, {:path, ["status"]}, {:literal, "approved"}}} = ast
    end
  end

  describe "error cases" do
    test "returns error for incomplete expression" do
      assert {:error, _} = Parser.parse("1 +")
    end

    test "returns error for empty input" do
      assert {:error, _} = Parser.parse("")
    end
  end
end
