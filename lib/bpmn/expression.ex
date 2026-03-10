defmodule Bpmn.Expression do
  @moduledoc """
  Bpmn.Expression
  ===============

  Validate a Bpmn condition expression and return its value.

  Uses `Bpmn.Expression.Sandbox` for safe evaluation — arbitrary code
  execution is prevented by AST restriction.

    iex> {:ok, context} = Bpmn.Context.start_link(%{}, %{})
    iex> Bpmn.Expression.execute({:bpmn_expression, {"elixir", "1==2"}}, context)
    {:ok, false}

    iex> {:ok, context} = Bpmn.Context.start_link(%{}, %{})
    iex> Bpmn.Expression.execute({:bpmn_expression, {"elixir", "1<2"}}, context)
    {:ok, true}

    The following example illustrates how we can execute an Elixir expression on the data in our context:

    iex> {:ok, context} = Bpmn.Context.start_link(%{}, %{})
    iex> Bpmn.Context.put_data(context, "count", 4)
    iex> Bpmn.Expression.execute({:bpmn_expression, {"elixir", "data[\\"count\\"]==4"}}, context)
    {:ok, true}

  """

  @doc """
  Validate a Bpmn condition expression and return the result
  """
  @spec execute(
          {:bpmn_expression, {String.t(), String.t()}}
          | {:bpmn_condition_expression, map()},
          Bpmn.context()
        ) :: {:ok, boolean()}
  def execute({:bpmn_expression, {_, ""}}, _), do: {:ok, true}
  def execute({:bpmn_expression, {lang, expr}}, context), do: {:ok, evaluate(lang, expr, context)}

  # Backward-compat: accept old parser format
  def execute({:bpmn_condition_expression, %{expression: expr} = attrs}, context) do
    lang = Map.get(attrs, :language, "elixir") |> to_string()
    execute({:bpmn_expression, {lang, expr}}, context)
  end

  @doc """
  Evaluate an elixir expression within the given context using the sandbox.
  """
  @spec evaluate(String.t(), String.t(), Bpmn.context()) :: boolean()
  def evaluate("elixir", expr, context) do
    data = Bpmn.Context.get(context, :data)

    case Bpmn.Expression.Sandbox.eval(expr, %{"data" => data}) do
      {:ok, result} -> result
      {:error, reason} -> raise "Expression error: #{reason}"
    end
  end

  def evaluate(lang, _expr, _context) do
    raise "Unsupported expression language: #{lang}. Only \"elixir\" is supported."
  end
end
