defmodule Rodar.Expression.Sandbox do
  @moduledoc """
  Sandboxed Elixir expression evaluator using AST restriction.

  Parses Elixir expressions into AST, walks the tree to reject dangerous
  operations, then evaluates only safe expressions. This replaces direct
  `Code.eval_string` calls to prevent arbitrary code execution.

  ## Allowed operations

  - Comparisons: `==`, `!=`, `>`, `<`, `>=`, `<=`, `===`, `!==`
  - Boolean: `and`, `or`, `not`, `&&`, `||`, `!`
  - Math: `+`, `-`, `*`, `/`, `rem`, `div`, `abs`
  - String: `<>`, `String.length/1`, `String.contains?/2`, `String.starts_with?/2`,
    `String.ends_with?/2`, `String.trim/1`, `String.upcase/1`, `String.downcase/1`,
    `String.split/2`
  - Data access: `data["key"]`, `data.key`, `Access.get/2`
  - Collections: `length/1`, `Enum.count/1`, `Enum.member?/2`, `Enum.any?/1`,
    `Enum.all?/1`, `Map.get/2`, `Map.get/3`, `Map.has_key?/2`, `List.first/1`,
    `List.last/1`
  - Literals: numbers, strings, atoms (`:true`, `:false`, `:nil` only), lists, maps, tuples
  - Control: `if`/`else`, `case`, `cond`
  - Pipes: `|>`

  ## Examples

      iex> Rodar.Expression.Sandbox.eval("1 + 2")
      {:ok, 3}

      iex> Rodar.Expression.Sandbox.eval("data[\\"x\\"] > 5", %{"data" => %{"x" => 10}})
      {:ok, true}

      iex> Rodar.Expression.Sandbox.eval("System.cmd(\\"ls\\", [])")
      {:error, "disallowed: module call System.cmd/2"}

      iex> Rodar.Expression.Sandbox.eval("File.read!(\\"/etc/passwd\\")")
      {:error, "disallowed: module call File.read!/1"}

  """

  @allowed_operators [
    # Comparison
    :==,
    :!=,
    :>,
    :<,
    :>=,
    :<=,
    :===,
    :!==,
    # Boolean
    :and,
    :or,
    :not,
    :&&,
    :||,
    :!,
    # Math
    :+,
    :-,
    :*,
    :/,
    # String concat
    :<>,
    # Pipe
    :|>,
    # Access
    :.,
    # Other
    :..,
    :in
  ]

  @allowed_kernel_functions [
    :rem,
    :div,
    :abs,
    :length,
    :is_nil,
    :is_number,
    :is_binary,
    :is_boolean,
    :is_list,
    :is_map,
    :is_atom,
    :is_integer,
    :is_float,
    :to_string,
    :hd,
    :tl,
    :elem,
    :tuple_size,
    :map_size,
    :min,
    :max,
    :not,
    :round,
    :trunc
  ]

  @allowed_module_calls %{
    String => [
      :length,
      :contains?,
      :starts_with?,
      :ends_with?,
      :trim,
      :upcase,
      :downcase,
      :split,
      :replace,
      :slice,
      :at,
      :to_integer,
      :to_float
    ],
    Enum => [
      :count,
      :member?,
      :any?,
      :all?,
      :at,
      :empty?,
      :find,
      :filter,
      :map,
      :reduce,
      :sort,
      :reverse,
      :sum,
      :min,
      :max,
      :zip,
      :flat_map,
      :join
    ],
    Map => [:get, :has_key?, :keys, :values, :put, :delete, :merge, :new],
    List => [:first, :last, :flatten, :wrap],
    Access => [:get],
    Kernel => @allowed_kernel_functions
  }

  @allowed_atoms [true, false, nil]

  @doc """
  Evaluate an expression string in a sandboxed environment.

  The `bindings` map is made available as variables in the expression.
  Typically contains `"data"` key with process context data.
  """
  @spec eval(String.t(), map()) :: {:ok, any()} | {:error, String.t()}
  def eval(expr, bindings \\ %{})

  def eval("", _bindings), do: {:ok, nil}

  def eval(expr, bindings) when is_binary(expr) do
    with {:ok, ast} <- parse(expr),
         true <- safe?(ast) do
      eval_quoted(ast, bindings)
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp parse(expr) do
    case Code.string_to_quoted(expr) do
      {:ok, ast} -> {:ok, ast}
      {:error, {_line, message, token}} -> {:error, "parse error: #{message}#{token}"}
    end
  end

  defp eval_quoted(ast, bindings) do
    binding_list = Enum.map(bindings, fn {k, v} -> {String.to_atom(k), v} end)

    try do
      {result, _binding} = Code.eval_quoted(ast, binding_list)
      {:ok, result}
    rescue
      e -> {:error, "runtime error: #{Exception.message(e)}"}
    end
  end

  @doc """
  Check if an AST is safe to evaluate.

  Returns `true` if the AST contains only allowed operations,
  or `{:error, reason}` if a disallowed operation is found.
  """
  @spec safe?(Macro.t()) :: true | {:error, String.t()}
  def safe?(ast) do
    case check_node(ast) do
      :ok -> true
      {:error, _} = err -> err
    end
  end

  # Literals
  defp check_node(literal) when is_number(literal), do: :ok
  defp check_node(literal) when is_binary(literal), do: :ok
  defp check_node(literal) when literal in @allowed_atoms, do: :ok

  # Disallow arbitrary atoms
  defp check_node(atom) when is_atom(atom) do
    if atom in @allowed_atoms do
      :ok
    else
      {:error, "disallowed: atom :#{atom}"}
    end
  end

  # Variables (e.g., `data`)
  defp check_node({name, _meta, context}) when is_atom(name) and is_atom(context), do: :ok

  # Operators
  defp check_node({op, _meta, args}) when op in @allowed_operators and is_list(args) do
    check_all(args)
  end

  # Kernel functions (called without module prefix)
  defp check_node({func, _meta, args}) when func in @allowed_kernel_functions and is_list(args) do
    check_all(args)
  end

  # Module calls: Module.function(args)
  defp check_node({{:., _meta1, [{:__aliases__, _meta2, module_parts}, func]}, _meta3, args})
       when is_list(args) do
    module = Module.concat(module_parts)
    arity = length(args)
    allowed_funcs = Map.get(@allowed_module_calls, module)

    cond do
      is_nil(allowed_funcs) ->
        {:error, "disallowed: module call #{inspect(module)}.#{func}/#{arity}"}

      func in allowed_funcs ->
        check_all(args)

      true ->
        {:error, "disallowed: module call #{inspect(module)}.#{func}/#{arity}"}
    end
  end

  # Dot access: data.field
  defp check_node({{:., _meta1, [Access, :get]}, _meta2, args}) when is_list(args) do
    check_all(args)
  end

  # Block expressions
  defp check_node({:__block__, _meta, args}) when is_list(args) do
    check_all(args)
  end

  # if/else
  defp check_node({:if, _meta, [condition, blocks]}) do
    with :ok <- check_node(condition) do
      check_keyword_blocks(blocks)
    end
  end

  # case
  defp check_node({:case, _meta, [expr, [do: clauses]]}) do
    with :ok <- check_node(expr) do
      check_clauses(clauses)
    end
  end

  # cond
  defp check_node({:cond, _meta, [[do: clauses]]}) do
    check_clauses(clauses)
  end

  # Tuples (2-element are literals, others use {})
  defp check_node({a, b}) do
    with :ok <- check_node(a) do
      check_node(b)
    end
  end

  defp check_node({:{}, _meta, args}) when is_list(args) do
    check_all(args)
  end

  # Lists
  defp check_node(list) when is_list(list) do
    check_all(list)
  end

  # Map literal: %{key => value}
  defp check_node({:%{}, _meta, pairs}) when is_list(pairs) do
    check_all(pairs)
  end

  # Arrow clauses in case/cond
  defp check_node({:->, _meta, [pattern, body]}) do
    with :ok <- check_all(pattern) do
      check_node(body)
    end
  end

  # when guards in case clauses
  defp check_node({:when, _meta, args}) when is_list(args) do
    check_all(args)
  end

  # Pin operator (used in patterns)
  defp check_node({:^, _meta, [arg]}) do
    check_node(arg)
  end

  # Underscore variable in patterns
  defp check_node({:_, _meta, _context}), do: :ok

  # Catch-all: reject anything else
  defp check_node(node) do
    {:error, "disallowed: #{inspect(node)}"}
  end

  defp check_all(nodes) when is_list(nodes) do
    Enum.reduce_while(nodes, :ok, fn node, :ok ->
      case check_node(node) do
        :ok -> {:cont, :ok}
        {:error, _} = err -> {:halt, err}
      end
    end)
  end

  defp check_keyword_blocks(blocks) when is_list(blocks) do
    Enum.reduce_while(blocks, :ok, fn
      {_key, block}, :ok ->
        case check_node(block) do
          :ok -> {:cont, :ok}
          {:error, _} = err -> {:halt, err}
        end
    end)
  end

  defp check_clauses(clauses) when is_list(clauses) do
    check_all(clauses)
  end
end
