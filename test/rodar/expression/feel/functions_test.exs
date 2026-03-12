defmodule Rodar.Expression.Feel.FunctionsTest do
  use ExUnit.Case, async: true

  alias Rodar.Expression.Feel.Functions

  describe "numeric functions" do
    test "abs" do
      assert {:ok, 5} = Functions.call("abs", [-5])
      assert {:ok, 5} = Functions.call("abs", [5])
      assert {:ok, 3.14} = Functions.call("abs", [-3.14])
    end

    test "floor" do
      assert {:ok, 3} = Functions.call("floor", [3.7])
      assert {:ok, -4} = Functions.call("floor", [-3.2])
    end

    test "ceiling" do
      assert {:ok, 4} = Functions.call("ceiling", [3.2])
      assert {:ok, -3} = Functions.call("ceiling", [-3.7])
    end

    test "round with no scale" do
      assert {:ok, 4} = Functions.call("round", [3.7])
      assert {:ok, 3} = Functions.call("round", [3.2])
    end

    test "round with scale" do
      assert {:ok, 3.1} = Functions.call("round", [3.14, 1])
      assert {:ok, 3.15} = Functions.call("round", [3.145, 2])
    end

    test "min" do
      assert {:ok, 1} = Functions.call("min", [[3, 1, 2]])
      assert {:ok, nil} = Functions.call("min", [[]])
    end

    test "max" do
      assert {:ok, 3} = Functions.call("max", [[3, 1, 2]])
      assert {:ok, nil} = Functions.call("max", [[]])
    end

    test "sum" do
      assert {:ok, 6} = Functions.call("sum", [[1, 2, 3]])
      assert {:ok, 0} = Functions.call("sum", [[]])
    end

    test "count" do
      assert {:ok, 3} = Functions.call("count", [[1, 2, 3]])
      assert {:ok, 0} = Functions.call("count", [[]])
    end
  end

  describe "string functions" do
    test "string length" do
      assert {:ok, 5} = Functions.call("string length", ["hello"])
      assert {:ok, 0} = Functions.call("string length", [""])
    end

    test "contains" do
      assert {:ok, true} = Functions.call("contains", ["hello world", "world"])
      assert {:ok, false} = Functions.call("contains", ["hello", "world"])
    end

    test "starts with" do
      assert {:ok, true} = Functions.call("starts with", ["hello", "he"])
      assert {:ok, false} = Functions.call("starts with", ["hello", "lo"])
    end

    test "ends with" do
      assert {:ok, true} = Functions.call("ends with", ["hello", "lo"])
      assert {:ok, false} = Functions.call("ends with", ["hello", "he"])
    end

    test "upper case" do
      assert {:ok, "HELLO"} = Functions.call("upper case", ["hello"])
    end

    test "lower case" do
      assert {:ok, "hello"} = Functions.call("lower case", ["HELLO"])
    end

    test "substring with start" do
      assert {:ok, "llo"} = Functions.call("substring", ["hello", 3])
    end

    test "substring with start and length" do
      assert {:ok, "ll"} = Functions.call("substring", ["hello", 3, 2])
    end
  end

  describe "boolean functions" do
    test "not true returns false" do
      assert {:ok, false} = Functions.call("not", [true])
    end

    test "not false returns true" do
      assert {:ok, true} = Functions.call("not", [false])
    end

    test "not nil returns nil" do
      assert {:ok, nil} = Functions.call("not", [nil])
    end
  end

  describe "null functions" do
    test "is null with nil" do
      assert {:ok, true} = Functions.call("is null", [nil])
    end

    test "is null with value" do
      assert {:ok, false} = Functions.call("is null", [42])
      assert {:ok, false} = Functions.call("is null", [""])
      assert {:ok, false} = Functions.call("is null", [false])
    end
  end

  describe "null propagation" do
    test "numeric functions return nil for nil arg" do
      assert {:ok, nil} = Functions.call("abs", [nil])
      assert {:ok, nil} = Functions.call("floor", [nil])
      assert {:ok, nil} = Functions.call("ceiling", [nil])
      assert {:ok, nil} = Functions.call("round", [nil])
      assert {:ok, nil} = Functions.call("min", [nil])
      assert {:ok, nil} = Functions.call("max", [nil])
      assert {:ok, nil} = Functions.call("sum", [nil])
      assert {:ok, nil} = Functions.call("count", [nil])
    end

    test "string functions return nil for nil arg" do
      assert {:ok, nil} = Functions.call("string length", [nil])
      assert {:ok, nil} = Functions.call("contains", [nil, "x"])
      assert {:ok, nil} = Functions.call("contains", ["x", nil])
      assert {:ok, nil} = Functions.call("starts with", [nil, "x"])
      assert {:ok, nil} = Functions.call("ends with", ["x", nil])
      assert {:ok, nil} = Functions.call("upper case", [nil])
      assert {:ok, nil} = Functions.call("lower case", [nil])
    end

    test "lists with nil elements propagate nil for sum" do
      assert {:ok, nil} = Functions.call("sum", [[1, nil, 3]])
    end

    test "lists with nil elements propagate nil for min/max" do
      assert {:ok, nil} = Functions.call("min", [[1, nil, 3]])
      assert {:ok, nil} = Functions.call("max", [[1, nil, 3]])
    end
  end

  describe "error cases" do
    test "unknown function returns error" do
      assert {:error, "unknown FEEL function: foobar"} = Functions.call("foobar", [42])
    end
  end
end
