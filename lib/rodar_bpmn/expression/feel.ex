defmodule RodarBpmn.Expression.Feel do
  @moduledoc """
  FEEL (Friendly Enough Expression Language) evaluator for BPMN 2.0.

  FEEL is the standard expression language for BPMN and DMN. It provides
  a simple, safe expression language with null propagation, three-valued
  boolean logic, and built-in functions.

  Bindings receive the raw data map directly. FEEL users write `count > 5`,
  not `data["count"] > 5`. Top-level identifiers resolve against the bindings map.

  ## Examples

      iex> RodarBpmn.Expression.Feel.eval("1 + 2", %{})
      {:ok, 3}

      iex> RodarBpmn.Expression.Feel.eval("amount > 1000", %{"amount" => 1500})
      {:ok, true}

      iex> RodarBpmn.Expression.Feel.eval("null", %{})
      {:ok, nil}

      iex> RodarBpmn.Expression.Feel.eval("if x > 10 then \"high\" else \"low\"", %{"x" => 15})
      {:ok, "high"}

  """

  alias RodarBpmn.Expression.Feel.Evaluator
  alias RodarBpmn.Expression.Feel.Parser

  @doc """
  Parse and evaluate a FEEL expression string against the given bindings.

  Returns `{:ok, result}` or `{:error, reason}`.

  ## Examples

      iex> RodarBpmn.Expression.Feel.eval("2 * 3 + 1", %{})
      {:ok, 7}

      iex> RodarBpmn.Expression.Feel.eval("name", %{"name" => "Alice"})
      {:ok, "Alice"}

  """
  @spec eval(String.t(), map()) :: {:ok, any()} | {:error, String.t()}
  def eval(expr, bindings) do
    with {:ok, ast} <- Parser.parse(expr) do
      Evaluator.evaluate(ast, bindings)
    end
  end
end
