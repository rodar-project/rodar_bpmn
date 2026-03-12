defmodule Rodar.Expression.TestHelpers do
  @moduledoc """
  Testing utilities for BPMN expressions.

  Provides convenience functions for evaluating expressions against sample data
  without needing a full process context, and for validating expression safety.

  ## Examples

      iex> Rodar.Expression.TestHelpers.eval_expression("1 + 2", %{})
      {:ok, 3}

      iex> Rodar.Expression.TestHelpers.validate("1 + 2")
      :ok

      iex> {:error, _} = Rodar.Expression.TestHelpers.validate("System.cmd(\\"ls\\", [])")

  """

  alias Rodar.Expression.Sandbox

  @doc """
  Evaluate an expression against sample data without a full process context.
  """
  @spec eval_expression(String.t(), map()) :: {:ok, any()} | {:error, String.t()}
  def eval_expression(expr, data) do
    Sandbox.eval(expr, %{"data" => data})
  end

  @doc """
  Check if an expression is safe without evaluating it.
  """
  @spec validate(String.t()) :: :ok | {:error, String.t()}
  def validate(expr) do
    case Code.string_to_quoted(expr) do
      {:ok, ast} ->
        case Sandbox.safe?(ast) do
          true -> :ok
          {:error, _} = err -> err
        end

      {:error, {_line, message, token}} ->
        {:error, "parse error: #{message}#{token}"}
    end
  end
end
