defmodule Rodar.Expression.Feel.Evaluator do
  @moduledoc """
  Tree-walking evaluator for FEEL AST nodes.

  Implements FEEL semantics including null propagation, three-valued boolean
  logic, and string concatenation via `+`.

  ## Key behaviors

  - **Null propagation:** `nil + 1` evaluates to `nil`, `nil > 5` evaluates to `false`
  - **Three-valued boolean:** `true and nil` evaluates to `nil`, `false and nil` evaluates to `false`
  - **String `+`:** If both operands are strings, concatenate; if both are numbers, add
  - **Path resolution:** `order.status` resolves to `bindings["order"]["status"]`
  - **`in` operator:** Check list membership or range inclusion
  - **Bracket access:** `a["key"]` resolves `a` then accesses string key

  ## Examples

      iex> alias Rodar.Expression.Feel.Evaluator
      iex> Evaluator.evaluate({:literal, 42}, %{})
      {:ok, 42}

      iex> alias Rodar.Expression.Feel.Evaluator
      iex> Evaluator.evaluate({:binop, :+, {:literal, 1}, {:literal, 2}}, %{})
      {:ok, 3}

      iex> alias Rodar.Expression.Feel.Evaluator
      iex> Evaluator.evaluate({:path, ["x"]}, %{"x" => 10})
      {:ok, 10}

  """

  alias Rodar.Expression.Feel.Functions

  @doc """
  Evaluate a FEEL AST node against the given bindings map.

  Returns `{:ok, value}` or `{:error, reason}`.
  """
  @spec evaluate(tuple() | any(), map()) :: {:ok, any()} | {:error, String.t()}
  def evaluate(ast, bindings) when is_map(bindings) do
    eval_node(ast, bindings)
  rescue
    e -> {:error, "runtime error: #{Exception.message(e)}"}
  end

  # --- Literals ---
  defp eval_node({:literal, value}, _bindings), do: {:ok, value}

  # --- Path resolution ---
  defp eval_node({:path, segments}, bindings), do: {:ok, resolve_path(segments, bindings)}

  # --- Bracket access ---
  defp eval_node({:bracket, base, key_ast}, bindings) do
    with {:ok, base_val} <- eval_node(base, bindings),
         {:ok, key_val} <- eval_node(key_ast, bindings) do
      eval_bracket_access(base_val, key_val)
    end
  end

  # --- List ---
  defp eval_node({:list, items}, bindings), do: eval_list(items, bindings, [])

  # --- If-then-else ---
  defp eval_node({:if, cond_ast, then_ast, else_ast}, bindings) do
    with {:ok, cond_val} <- eval_node(cond_ast, bindings) do
      if cond_val == true do
        eval_node(then_ast, bindings)
      else
        eval_node(else_ast, bindings)
      end
    end
  end

  # --- In operator ---
  defp eval_node({:in, expr_ast, collection_ast}, bindings) do
    with {:ok, val} <- eval_node(expr_ast, bindings),
         {:ok, collection} <- eval_node(collection_ast, bindings) do
      eval_in(val, collection)
    end
  end

  # --- Range ---
  defp eval_node({:range, from_ast, to_ast}, bindings) do
    with {:ok, from} <- eval_node(from_ast, bindings),
         {:ok, to} <- eval_node(to_ast, bindings) do
      {:ok, {:range_value, from, to}}
    end
  end

  # --- Unary operators ---
  defp eval_node({:unary, :-, expr_ast}, bindings) do
    with {:ok, val} <- eval_node(expr_ast, bindings) do
      eval_unary_neg(val)
    end
  end

  defp eval_node({:unary, :not, expr_ast}, bindings) do
    with {:ok, val} <- eval_node(expr_ast, bindings) do
      eval_unary_not(val)
    end
  end

  # --- Binary operators ---
  defp eval_node({:binop, :and, left_ast, right_ast}, bindings) do
    eval_and(left_ast, right_ast, bindings)
  end

  defp eval_node({:binop, :or, left_ast, right_ast}, bindings) do
    eval_or(left_ast, right_ast, bindings)
  end

  defp eval_node({:binop, op, left_ast, right_ast}, bindings) do
    with {:ok, left} <- eval_node(left_ast, bindings),
         {:ok, right} <- eval_node(right_ast, bindings) do
      eval_binop(op, left, right)
    end
  end

  # --- Function calls ---
  defp eval_node({:funcall, name, arg_asts}, bindings) do
    with {:ok, args} <- eval_args(arg_asts, bindings, []) do
      Functions.call(name, args)
    end
  end

  # --- Helpers ---

  defp resolve_path([], _map), do: nil

  defp resolve_path([segment | rest], map) when is_map(map) do
    value = Map.get(map, segment)
    resolve_remaining(rest, value)
  end

  defp resolve_path(_segments, _non_map), do: nil

  defp resolve_remaining([], value), do: value

  defp resolve_remaining([segment | rest], map) when is_map(map) do
    resolve_remaining(rest, Map.get(map, segment))
  end

  defp resolve_remaining(_segments, _non_map), do: nil

  defp eval_bracket_access(nil, _key), do: {:ok, nil}

  defp eval_bracket_access(map, key) when is_map(map) do
    {:ok, Map.get(map, to_string(key))}
  end

  defp eval_bracket_access(list, index) when is_list(list) and is_integer(index) do
    {:ok, Enum.at(list, index)}
  end

  defp eval_bracket_access(_base, _key), do: {:ok, nil}

  defp eval_list([], _bindings, acc), do: {:ok, Enum.reverse(acc)}

  defp eval_list([item | rest], bindings, acc) do
    with {:ok, val} <- eval_node(item, bindings) do
      eval_list(rest, bindings, [val | acc])
    end
  end

  defp eval_args([], _bindings, acc), do: {:ok, Enum.reverse(acc)}

  defp eval_args([arg | rest], bindings, acc) do
    with {:ok, val} <- eval_node(arg, bindings) do
      eval_args(rest, bindings, [val | acc])
    end
  end

  # --- Unary helpers ---

  defp eval_unary_neg(nil), do: {:ok, nil}
  defp eval_unary_neg(n) when is_number(n), do: {:ok, -n}
  defp eval_unary_neg(_), do: {:error, "unary -: operand must be a number"}

  defp eval_unary_not(nil), do: {:ok, nil}
  defp eval_unary_not(true), do: {:ok, false}
  defp eval_unary_not(false), do: {:ok, true}
  defp eval_unary_not(_), do: {:error, "not: operand must be boolean"}

  # --- Three-valued boolean logic ---

  defp eval_and(left_ast, right_ast, bindings) do
    with {:ok, left} <- eval_node(left_ast, bindings) do
      case left do
        false -> {:ok, false}
        true -> eval_node(right_ast, bindings)
        nil -> eval_and_nil(right_ast, bindings)
      end
    end
  end

  defp eval_and_nil(right_ast, bindings) do
    with {:ok, right} <- eval_node(right_ast, bindings) do
      case right do
        false -> {:ok, false}
        _ -> {:ok, nil}
      end
    end
  end

  defp eval_or(left_ast, right_ast, bindings) do
    with {:ok, left} <- eval_node(left_ast, bindings) do
      case left do
        true -> {:ok, true}
        false -> eval_node(right_ast, bindings)
        nil -> eval_or_nil(right_ast, bindings)
      end
    end
  end

  defp eval_or_nil(right_ast, bindings) do
    with {:ok, right} <- eval_node(right_ast, bindings) do
      case right do
        true -> {:ok, true}
        _ -> {:ok, nil}
      end
    end
  end

  # --- Binary operator dispatch ---

  # Equality always works (including nil)
  defp eval_binop(:==, left, right), do: {:ok, left == right}
  defp eval_binop(:!=, left, right), do: {:ok, left != right}

  # Both nil for non-equality ops
  defp eval_binop(_op, nil, nil), do: {:ok, nil}

  # Comparison with nil returns false
  defp eval_binop(op, nil, _right) when op in [:<, :>, :<=, :>=], do: {:ok, false}
  defp eval_binop(op, _left, nil) when op in [:<, :>, :<=, :>=], do: {:ok, false}

  # Arithmetic with nil propagates nil
  defp eval_binop(op, nil, _right) when op in [:+, :-, :*, :/, :%, :**], do: {:ok, nil}
  defp eval_binop(op, _left, nil) when op in [:+, :-, :*, :/, :%, :**], do: {:ok, nil}

  # Arithmetic
  defp eval_binop(:+, l, r) when is_number(l) and is_number(r), do: {:ok, l + r}
  defp eval_binop(:+, l, r) when is_binary(l) and is_binary(r), do: {:ok, l <> r}
  defp eval_binop(:-, l, r) when is_number(l) and is_number(r), do: {:ok, l - r}
  defp eval_binop(:*, l, r) when is_number(l) and is_number(r), do: {:ok, l * r}

  defp eval_binop(:/, _l, 0), do: {:error, "division by zero"}
  defp eval_binop(:/, _l, +0.0), do: {:error, "division by zero"}
  defp eval_binop(:/, l, r) when is_number(l) and is_number(r), do: {:ok, l / r}

  defp eval_binop(:%, _l, 0), do: {:error, "modulo by zero"}

  defp eval_binop(:%, l, r) when is_integer(l) and is_integer(r) do
    {:ok, rem(l, r)}
  end

  defp eval_binop(:**, l, r) when is_number(l) and is_number(r) do
    {:ok, :math.pow(l, r)}
  end

  # Comparison
  defp eval_binop(:<, l, r), do: {:ok, l < r}
  defp eval_binop(:>, l, r), do: {:ok, l > r}
  defp eval_binop(:<=, l, r), do: {:ok, l <= r}
  defp eval_binop(:>=, l, r), do: {:ok, l >= r}

  defp eval_binop(op, _l, _r), do: {:error, "unsupported binop: #{op}"}

  # --- In operator ---

  defp eval_in(nil, _collection), do: {:ok, nil}
  defp eval_in(_val, nil), do: {:ok, nil}

  defp eval_in(val, {:range_value, from, to}) when is_number(val) do
    {:ok, val >= from and val <= to}
  end

  defp eval_in(val, list) when is_list(list) do
    {:ok, Enum.member?(list, val)}
  end

  defp eval_in(_val, _other), do: {:ok, false}
end
