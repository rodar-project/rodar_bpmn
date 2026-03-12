defmodule Rodar.Expression.Feel.Parser do
  @moduledoc """
  NimbleParsec-based parser for FEEL (Friendly Enough Expression Language).

  Produces an AST of tagged tuples suitable for evaluation by
  `Rodar.Expression.Feel.Evaluator`.

  ## Grammar precedence (low to high)

  1. `or`
  2. `and`
  3. Comparison (`=`, `!=`, `<`, `>`, `<=`, `>=`) and `in`
  4. Addition (`+`, `-`)
  5. Multiplication (`*`, `/`, `%`)
  6. Exponentiation (`**`)
  7. Unary (`-`, `not`)
  8. Primary (literals, parens, if-then-else, function calls, paths, lists, bracket access)

  ## AST node types

  - `{:literal, value}` -- number, string, boolean, nil
  - `{:binop, op, left, right}` -- arithmetic, comparison, boolean
  - `{:unary, op, expr}` -- negation, not
  - `{:path, [segments]}` -- dot-separated identifiers
  - `{:bracket, base, index}` -- bracket access
  - `{:if, condition, then_expr, else_expr}`
  - `{:in, expr, collection_or_range}`
  - `{:range, from, to}`
  - `{:list, [items]}`
  - `{:funcall, name, [args]}`

  ## Examples

      iex> Rodar.Expression.Feel.Parser.parse("1 + 2")
      {:ok, {:binop, :+, {:literal, 1}, {:literal, 2}}}

      iex> Rodar.Expression.Feel.Parser.parse("true and false")
      {:ok, {:binop, :and, {:literal, true}, {:literal, false}}}

      iex> Rodar.Expression.Feel.Parser.parse("null")
      {:ok, {:literal, nil}}

  """

  import NimbleParsec

  # --- Whitespace (optional) ---
  ws = ascii_string([?\s, ?\t, ?\n, ?\r], min: 0)

  # Word boundary: lookahead for non-identifier char (space, operator, eof, etc.)
  word_boundary = lookahead_not(ascii_char([?a..?z, ?A..?Z, ?0..?9, ?_]))

  # --- Literals ---
  float_literal =
    ascii_string([?0..?9], min: 1)
    |> ascii_char([?.])
    |> ascii_string([?0..?9], min: 1)
    |> reduce(:build_float)

  integer_literal =
    ascii_string([?0..?9], min: 1)
    |> reduce(:build_integer)

  number_literal = choice([float_literal, integer_literal])

  # Strings (double-quoted)
  string_literal =
    ignore(ascii_char([?"]))
    |> repeat(
      choice([
        string("\\\"") |> replace(?"),
        string("\\\\") |> replace(?\\),
        string("\\n") |> replace(?\n),
        string("\\t") |> replace(?\t),
        utf8_char(not: ?", not: ?\\)
      ])
    )
    |> ignore(ascii_char([?"]))
    |> reduce(:build_string)

  # Boolean and null keywords
  true_literal = string("true") |> concat(word_boundary) |> replace({:literal, true})
  false_literal = string("false") |> concat(word_boundary) |> replace({:literal, false})
  null_literal = string("null") |> concat(word_boundary) |> replace({:literal, nil})

  # --- Identifiers ---
  identifier =
    ascii_string([?a..?z, ?A..?Z, ?_], 1)
    |> ascii_string([?a..?z, ?A..?Z, ?0..?9, ?_], min: 0)
    |> reduce(:build_identifier)

  # --- Multi-word function names ---
  # Each known name is parsed as a literal string (with space), then matched to `(`
  multiword_funcall =
    choice([
      string("string length") |> concat(word_boundary),
      string("starts with") |> concat(word_boundary),
      string("ends with") |> concat(word_boundary),
      string("upper case") |> concat(word_boundary),
      string("lower case") |> concat(word_boundary),
      string("is null") |> concat(word_boundary)
    ])
    |> ignore(ws)
    |> ignore(ascii_char([?(]))
    |> ignore(ws)
    |> optional(
      parsec(:expr)
      |> repeat(ignore(ws) |> ignore(ascii_char([?,])) |> ignore(ws) |> parsec(:expr))
    )
    |> ignore(ws)
    |> ignore(ascii_char([?)]))
    |> reduce(:build_multiword_funcall)

  # Single-word function call: identifier followed by `(`
  singleword_funcall =
    identifier
    |> ignore(ws)
    |> ignore(ascii_char([?(]))
    |> ignore(ws)
    |> optional(
      parsec(:expr)
      |> repeat(ignore(ws) |> ignore(ascii_char([?,])) |> ignore(ws) |> parsec(:expr))
    )
    |> ignore(ws)
    |> ignore(ascii_char([?)]))
    |> reduce(:build_singleword_funcall)

  # --- List literal ---
  list_literal =
    ignore(ascii_char([?[]))
    |> ignore(ws)
    |> optional(
      parsec(:expr)
      |> repeat(ignore(ws) |> ignore(ascii_char([?,])) |> ignore(ws) |> parsec(:expr))
    )
    |> ignore(ws)
    |> ignore(ascii_char([?]]))
    |> reduce(:build_list)

  # --- If-then-else ---
  if_then_else =
    ignore(string("if"))
    |> ignore(ascii_string([?\s, ?\t], min: 1))
    |> parsec(:expr)
    |> ignore(ascii_string([?\s, ?\t], min: 1))
    |> ignore(string("then"))
    |> ignore(ascii_string([?\s, ?\t], min: 1))
    |> parsec(:expr)
    |> ignore(ascii_string([?\s, ?\t], min: 1))
    |> ignore(string("else"))
    |> ignore(ascii_string([?\s, ?\t], min: 1))
    |> parsec(:expr)
    |> reduce(:build_if)

  # --- Parenthesized expression ---
  paren_expr =
    ignore(ascii_char([?(]))
    |> ignore(ws)
    |> parsec(:expr)
    |> ignore(ws)
    |> ignore(ascii_char([?)]))

  # --- Identifier with optional path/bracket suffixes ---
  ident_or_path =
    identifier
    |> repeat(
      choice([
        ignore(ascii_char([?.])) |> concat(identifier),
        ignore(ascii_char([?[]))
        |> ignore(ws)
        |> concat(
          choice([
            string_literal |> reduce(:wrap_literal),
            number_literal |> reduce(:wrap_literal)
          ])
        )
        |> ignore(ws)
        |> ignore(ascii_char([?]]))
        |> reduce(:mark_bracket)
      ])
    )
    |> reduce(:build_path_or_ident)

  # --- Primary expression (NO trailing ws consumed) ---
  primary =
    ignore(ws)
    |> choice([
      null_literal,
      true_literal,
      false_literal,
      if_then_else,
      number_literal |> reduce(:wrap_literal),
      string_literal |> reduce(:wrap_literal),
      list_literal,
      multiword_funcall,
      singleword_funcall,
      paren_expr,
      ident_or_path
    ])

  # --- Unary ---
  unary_neg =
    ignore(ascii_char([?-]))
    |> ignore(ws)
    |> parsec(:unary_expr)
    |> reduce(:build_neg)

  unary_not =
    ignore(string("not"))
    |> ignore(ascii_string([?\s, ?\t], min: 1))
    |> parsec(:unary_expr)
    |> reduce(:build_not)

  # --- Operator tokens ---
  exp_op = string("**") |> replace(:**)

  mul_op =
    choice([
      string("**") |> replace(:__skip__),
      ascii_char([?*]) |> replace(:*),
      ascii_char([?/]) |> replace(:/),
      ascii_char([?%]) |> replace(:%)
    ])

  add_op = choice([ascii_char([?+]) |> replace(:+), ascii_char([?-]) |> replace(:-)])

  cmp_op =
    choice([
      string("!=") |> replace(:!=),
      string("<=") |> replace(:<=),
      string(">=") |> replace(:>=),
      ascii_char([?=]) |> replace(:==),
      ascii_char([?<]) |> replace(:<),
      ascii_char([?>]) |> replace(:>)
    ])

  # --- Range expression (for `in` operator) ---
  range_expr =
    parsec(:addition)
    |> ignore(ws)
    |> ignore(string(".."))
    |> ignore(ws)
    |> parsec(:addition)
    |> reduce(:build_range)

  # --- Combinators (left-associative via repeat) ---

  defcombinatorp(:primary_expr, primary)

  defcombinatorp(
    :unary_expr,
    choice([
      unary_neg,
      unary_not,
      parsec(:primary_expr)
    ])
  )

  defcombinatorp(
    :exponent,
    parsec(:unary_expr)
    |> repeat(ignore(ws) |> concat(exp_op) |> ignore(ws) |> parsec(:unary_expr))
    |> reduce(:build_left_assoc)
  )

  defcombinatorp(
    :multiplication,
    parsec(:exponent)
    |> repeat(
      ignore(ws)
      |> lookahead_not(string("**"))
      |> concat(mul_op)
      |> ignore(ws)
      |> parsec(:exponent)
    )
    |> reduce(:build_left_assoc)
  )

  defcombinatorp(
    :addition,
    parsec(:multiplication)
    |> repeat(ignore(ws) |> concat(add_op) |> ignore(ws) |> parsec(:multiplication))
    |> reduce(:build_left_assoc)
  )

  defcombinatorp(
    :comparison,
    parsec(:addition)
    |> optional(
      choice([
        # `in` operator with range or list/expr
        ignore(ws)
        |> ignore(string("in"))
        |> ignore(ascii_string([?\s, ?\t], min: 1))
        |> choice([
          range_expr,
          parsec(:addition)
        ])
        |> reduce(:mark_in),
        # Regular comparison
        ignore(ws) |> concat(cmp_op) |> ignore(ws) |> parsec(:addition)
      ])
    )
    |> reduce(:build_comparison)
  )

  defcombinatorp(
    :conjunction,
    parsec(:comparison)
    |> repeat(
      ignore(ws)
      |> ignore(string("and"))
      |> ignore(ascii_string([?\s, ?\t], min: 1))
      |> parsec(:comparison)
    )
    |> reduce(:build_and)
  )

  defcombinatorp(
    :disjunction,
    parsec(:conjunction)
    |> repeat(
      ignore(ws)
      |> ignore(string("or"))
      |> ignore(ascii_string([?\s, ?\t], min: 1))
      |> parsec(:conjunction)
    )
    |> reduce(:build_or)
  )

  defcombinatorp(:expr, parsec(:disjunction))

  defparsec(:parse_expr, parsec(:expr) |> ignore(ws) |> eos())

  # --- Public API ---

  @doc """
  Parse a FEEL expression string into an AST.

  Returns `{:ok, ast}` on success or `{:error, message}` on failure.

  ## Examples

      iex> Rodar.Expression.Feel.Parser.parse("42")
      {:ok, {:literal, 42}}

      iex> Rodar.Expression.Feel.Parser.parse("x + 1")
      {:ok, {:binop, :+, {:path, ["x"]}, {:literal, 1}}}

  """
  @spec parse(String.t()) :: {:ok, tuple()} | {:error, String.t()}
  def parse(input) when is_binary(input) do
    case parse_expr(String.trim(input)) do
      {:ok, [ast], "", _, _, _} ->
        {:ok, ast}

      {:ok, _, rest, _, _, _} ->
        {:error, "unexpected input: #{inspect(rest)}"}

      {:error, message, rest, _, _, _} ->
        {:error, "parse error near #{inspect(String.slice(rest, 0..19))}: #{message}"}
    end
  end

  # --- AST builder helpers ---

  @doc false
  def build_integer([str]) do
    {:literal, String.to_integer(str)}
  end

  @doc false
  def build_float(parts) do
    str =
      Enum.map_join(parts, fn
        c when is_integer(c) -> <<c>>
        s when is_binary(s) -> s
      end)

    {:literal, String.to_float(str)}
  end

  @doc false
  def build_string(chars), do: {:literal, List.to_string(chars)}

  @doc false
  def build_identifier([first, rest]), do: first <> rest

  @doc false
  def wrap_literal([{:literal, _} = lit]), do: lit

  @doc false
  def mark_bracket([item]), do: {:bracket_key, item}

  @doc false
  def build_path_or_ident(parts) do
    {segments, result} = build_path_segments(parts, [])
    finalize_path(segments, result)
  end

  defp build_path_segments([], acc), do: {Enum.reverse(acc), nil}

  defp build_path_segments([{:bracket_key, key} | rest], acc) do
    base = finalize_path(Enum.reverse(acc), nil)
    {[], build_brackets(rest, {:bracket, base, key})}
  end

  defp build_path_segments([segment | rest], acc) when is_binary(segment) do
    build_path_segments(rest, [segment | acc])
  end

  defp build_brackets([], acc), do: acc

  defp build_brackets([{:bracket_key, key} | rest], acc) do
    build_brackets(rest, {:bracket, acc, key})
  end

  defp build_brackets([segment | rest], acc) when is_binary(segment) do
    {more_segments, result} = build_path_segments(rest, [segment])

    base =
      case more_segments do
        [] -> acc
        segs -> {:bracket, acc, {:path, segs}}
      end

    if result, do: result, else: base
  end

  defp finalize_path([], nil), do: {:path, []}
  defp finalize_path(segments, nil), do: {:path, segments}
  defp finalize_path(_segments, result), do: result

  @doc false
  def build_list(items), do: {:list, items}

  @doc false
  def build_if([condition, then_expr, else_expr]) do
    {:if, condition, then_expr, else_expr}
  end

  @doc false
  def build_multiword_funcall([name | args]), do: {:funcall, name, args}

  @doc false
  def build_singleword_funcall([name | args]), do: {:funcall, name, args}

  @doc false
  def build_neg([expr]), do: {:unary, :-, expr}

  @doc false
  def build_not([expr]), do: {:unary, :not, expr}

  @doc false
  def build_range([from, to]), do: {:range, from, to}

  @doc false
  def mark_in(parts), do: {:in_rhs, List.last(parts)}

  @doc false
  def build_comparison(parts) do
    case parts do
      [left, {:in_rhs, rhs}] -> {:in, left, rhs}
      [left, op, right] -> {:binop, op, left, right}
      [single] -> single
    end
  end

  @doc false
  def build_left_assoc([single]), do: single

  def build_left_assoc([first | rest]) do
    rest
    |> Enum.chunk_every(2)
    |> Enum.reduce(first, fn [op, right], acc ->
      {:binop, op, acc, right}
    end)
  end

  @doc false
  def build_and([single]), do: single

  def build_and([first | rest]) do
    Enum.reduce(rest, first, fn right, acc -> {:binop, :and, acc, right} end)
  end

  @doc false
  def build_or([single]), do: single

  def build_or([first | rest]) do
    Enum.reduce(rest, first, fn right, acc -> {:binop, :or, acc, right} end)
  end
end
