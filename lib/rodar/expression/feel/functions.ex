defmodule Rodar.Expression.Feel.Functions do
  @moduledoc """
  Built-in FEEL function implementations.

  Dispatches on `{name_string, args_list}`. Implements null propagation:
  if any argument is `nil`, the result is `nil` (except for `is null` and `not`).

  ## Supported functions

  - Numeric: `abs/1`, `floor/1`, `ceiling/1`, `round/1-2`, `min/1`, `max/1`, `sum/1`, `count/1`
  - String: `string length/1`, `contains/2`, `starts with/2`, `ends with/2`,
    `upper case/1`, `lower case/1`, `substring/2-3`
  - Boolean: `not/1`
  - Null: `is null/1`

  ## Examples

      iex> Rodar.Expression.Feel.Functions.call("abs", [-5])
      {:ok, 5}

      iex> Rodar.Expression.Feel.Functions.call("string length", ["hello"])
      {:ok, 5}

      iex> Rodar.Expression.Feel.Functions.call("is null", [nil])
      {:ok, true}

      iex> Rodar.Expression.Feel.Functions.call("abs", [nil])
      {:ok, nil}

  """

  @doc """
  Call a FEEL built-in function by name with the given arguments.

  Returns `{:ok, result}` or `{:error, reason}`.
  """
  @spec call(String.t(), [any()]) :: {:ok, any()} | {:error, String.t()}
  def call(name, args) do
    dispatch(name, args)
  end

  # --- Null check (no null propagation) ---
  defp dispatch("is null", [val]), do: {:ok, is_nil(val)}
  defp dispatch("is null", args), do: arity_error("is null", 1, args)

  # --- Boolean not (no null propagation) ---
  defp dispatch("not", [nil]), do: {:ok, nil}
  defp dispatch("not", [val]) when is_boolean(val), do: {:ok, not val}
  defp dispatch("not", [_]), do: {:error, "not: argument must be boolean"}
  defp dispatch("not", args), do: arity_error("not", 1, args)

  # --- Numeric functions (with null propagation) ---
  defp dispatch("abs", [nil]), do: {:ok, nil}
  defp dispatch("abs", [n]) when is_number(n), do: {:ok, abs(n)}
  defp dispatch("abs", args), do: arity_error("abs", 1, args)

  defp dispatch("floor", [nil]), do: {:ok, nil}
  defp dispatch("floor", [n]) when is_number(n), do: {:ok, floor(n)}
  defp dispatch("floor", args), do: arity_error("floor", 1, args)

  defp dispatch("ceiling", [nil]), do: {:ok, nil}
  defp dispatch("ceiling", [n]) when is_number(n), do: {:ok, ceil(n)}
  defp dispatch("ceiling", args), do: arity_error("ceiling", 1, args)

  defp dispatch("round", [nil]), do: {:ok, nil}
  defp dispatch("round", [n]) when is_number(n), do: {:ok, round(n)}
  defp dispatch("round", [nil, _]), do: {:ok, nil}
  defp dispatch("round", [_, nil]), do: {:ok, nil}

  defp dispatch("round", [n, scale]) when is_number(n) and is_integer(scale) do
    factor = :math.pow(10, scale)
    {:ok, round(n * factor) / factor}
  end

  defp dispatch("round", args) when length(args) not in [1, 2] do
    arity_error("round", "1-2", args)
  end

  defp dispatch("min", [nil]), do: {:ok, nil}

  defp dispatch("min", [list]) when is_list(list) do
    if Enum.any?(list, &is_nil/1), do: {:ok, nil}, else: {:ok, Enum.min(list, fn -> nil end)}
  end

  defp dispatch("min", args), do: arity_error("min", 1, args)

  defp dispatch("max", [nil]), do: {:ok, nil}

  defp dispatch("max", [list]) when is_list(list) do
    if Enum.any?(list, &is_nil/1), do: {:ok, nil}, else: {:ok, Enum.max(list, fn -> nil end)}
  end

  defp dispatch("max", args), do: arity_error("max", 1, args)

  defp dispatch("sum", [nil]), do: {:ok, nil}

  defp dispatch("sum", [list]) when is_list(list) do
    if Enum.any?(list, &is_nil/1), do: {:ok, nil}, else: {:ok, Enum.sum(list)}
  end

  defp dispatch("sum", args), do: arity_error("sum", 1, args)

  defp dispatch("count", [nil]), do: {:ok, nil}
  defp dispatch("count", [list]) when is_list(list), do: {:ok, length(list)}
  defp dispatch("count", args), do: arity_error("count", 1, args)

  # --- String functions (with null propagation) ---
  defp dispatch("string length", [nil]), do: {:ok, nil}
  defp dispatch("string length", [s]) when is_binary(s), do: {:ok, String.length(s)}
  defp dispatch("string length", args), do: arity_error("string length", 1, args)

  defp dispatch("contains", [nil, _]), do: {:ok, nil}
  defp dispatch("contains", [_, nil]), do: {:ok, nil}

  defp dispatch("contains", [s, sub]) when is_binary(s) and is_binary(sub) do
    {:ok, String.contains?(s, sub)}
  end

  defp dispatch("contains", args), do: arity_error("contains", 2, args)

  defp dispatch("starts with", [nil, _]), do: {:ok, nil}
  defp dispatch("starts with", [_, nil]), do: {:ok, nil}

  defp dispatch("starts with", [s, prefix]) when is_binary(s) and is_binary(prefix) do
    {:ok, String.starts_with?(s, prefix)}
  end

  defp dispatch("starts with", args), do: arity_error("starts with", 2, args)

  defp dispatch("ends with", [nil, _]), do: {:ok, nil}
  defp dispatch("ends with", [_, nil]), do: {:ok, nil}

  defp dispatch("ends with", [s, suffix]) when is_binary(s) and is_binary(suffix) do
    {:ok, String.ends_with?(s, suffix)}
  end

  defp dispatch("ends with", args), do: arity_error("ends with", 2, args)

  defp dispatch("upper case", [nil]), do: {:ok, nil}
  defp dispatch("upper case", [s]) when is_binary(s), do: {:ok, String.upcase(s)}
  defp dispatch("upper case", args), do: arity_error("upper case", 1, args)

  defp dispatch("lower case", [nil]), do: {:ok, nil}
  defp dispatch("lower case", [s]) when is_binary(s), do: {:ok, String.downcase(s)}
  defp dispatch("lower case", args), do: arity_error("lower case", 1, args)

  defp dispatch("substring", [nil | _]), do: {:ok, nil}
  defp dispatch("substring", [_, nil | _]), do: {:ok, nil}
  defp dispatch("substring", [_, _, nil]), do: {:ok, nil}

  defp dispatch("substring", [s, start]) when is_binary(s) and is_integer(start) do
    # FEEL substring is 1-based
    idx = if start > 0, do: start - 1, else: start
    {:ok, String.slice(s, idx..-1//1)}
  end

  defp dispatch("substring", [s, start, len])
       when is_binary(s) and is_integer(start) and is_integer(len) do
    idx = if start > 0, do: start - 1, else: start
    {:ok, String.slice(s, idx, len)}
  end

  defp dispatch("substring", args) when length(args) not in [2, 3] do
    arity_error("substring", "2-3", args)
  end

  # --- Unknown function ---
  defp dispatch(name, _args) do
    {:error, "unknown FEEL function: #{name}"}
  end

  defp arity_error(name, expected, args) do
    {:error, "#{name}: expected #{expected} argument(s), got #{length(args)}"}
  end
end
