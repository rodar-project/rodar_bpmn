defmodule RodarBpmn.Expression do
  @moduledoc """
  Validates a BPMN condition expression and returns its value.

  Supports multiple expression languages:

  - `"elixir"` — Sandboxed Elixir expression evaluation via `RodarBpmn.Expression.Sandbox`
  - `"feel"` — FEEL (Friendly Enough Expression Language) via `RodarBpmn.Expression.Feel`

  ## Examples

      iex> {:ok, context} = RodarBpmn.Context.start_link(%{}, %{})
      iex> RodarBpmn.Expression.execute({:bpmn_expression, {"elixir", "1==2"}}, context)
      {:ok, false}

      iex> {:ok, context} = RodarBpmn.Context.start_link(%{}, %{})
      iex> RodarBpmn.Expression.execute({:bpmn_expression, {"elixir", "1<2"}}, context)
      {:ok, true}

  Elixir expressions can access the context data map:

      iex> {:ok, context} = RodarBpmn.Context.start_link(%{}, %{})
      iex> RodarBpmn.Context.put_data(context, "count", 4)
      iex> RodarBpmn.Expression.execute({:bpmn_expression, {"elixir", "data[\\"count\\"]==4"}}, context)
      {:ok, true}

  FEEL expressions receive the raw data map — identifiers resolve directly:

      iex> {:ok, context} = RodarBpmn.Context.start_link(%{}, %{})
      iex> RodarBpmn.Context.put_data(context, "count", 4)
      iex> RodarBpmn.Expression.execute({:bpmn_expression, {"feel", "count = 4"}}, context)
      {:ok, true}

  """

  alias RodarBpmn.Expression.Feel
  alias RodarBpmn.Expression.Sandbox

  @doc """
  Validate a BPMN condition expression and return the result
  """
  @spec execute(
          {:bpmn_expression, {String.t(), String.t()}}
          | {:bpmn_condition_expression, map()},
          RodarBpmn.context()
        ) :: {:ok, term()}
  def execute({:bpmn_expression, {_, ""}}, _), do: {:ok, true}
  def execute({:bpmn_expression, {lang, expr}}, context), do: {:ok, evaluate(lang, expr, context)}

  # Backward-compat: accept old parser format
  def execute({:bpmn_condition_expression, %{expression: expr} = attrs}, context) do
    lang = Map.get(attrs, :language, "elixir") |> to_string()
    execute({:bpmn_expression, {lang, expr}}, context)
  end

  @doc """
  Evaluate an expression within the given context using the appropriate evaluator.

  Supports `"elixir"` (via Sandbox) and `"feel"` (via FEEL evaluator).
  """
  @spec evaluate(String.t(), String.t(), RodarBpmn.context()) :: term()
  def evaluate("elixir", expr, context) do
    data = RodarBpmn.Context.get(context, :data)

    case Sandbox.eval(expr, %{"data" => data}) do
      {:ok, result} -> result
      {:error, reason} -> raise "Expression error: #{reason}"
    end
  end

  def evaluate("feel", expr, context) do
    data = RodarBpmn.Context.get(context, :data)

    case Feel.eval(expr, data) do
      {:ok, result} -> result
      {:error, reason} -> raise "FEEL expression error: #{reason}"
    end
  end

  def evaluate(lang, _expr, _context) do
    raise ~s|Unsupported expression language: #{lang}. Only "elixir" and "feel" are supported.|
  end
end
