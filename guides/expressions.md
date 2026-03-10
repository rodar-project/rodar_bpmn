# Expressions

The engine supports two expression languages for condition evaluation on sequence flows, gateways, and conditional events: FEEL and sandboxed Elixir. The language is selected via the `language` attribute in BPMN XML condition expressions.

## Language Selection

In BPMN XML, set the `language` attribute on a `conditionExpression` element:

```xml
<!-- FEEL (default for BPMN 2.0) -->
<conditionExpression xsi:type="tFormalExpression" language="feel">
  amount > 1000
</conditionExpression>

<!-- Sandboxed Elixir -->
<conditionExpression xsi:type="tFormalExpression" language="elixir">
  data["amount"] > 1000
</conditionExpression>
```

You can also evaluate expressions programmatically:

```elixir
RodarBpmn.Expression.execute({:bpmn_expression, {"feel", "amount > 1000"}}, context)
RodarBpmn.Expression.execute({:bpmn_expression, {"elixir", "data[\"amount\"] > 1000"}}, context)
```

## Data Access

The two languages differ in how they access process data:

- **FEEL** receives the raw data map as bindings. Write `count > 5` directly.
- **Elixir sandbox** binds the data map to the `data` variable. Write `data["count"] > 5`.

## FEEL Syntax

FEEL supports arithmetic (`+`, `-`, `*`, `/`), comparisons (`>`, `<`, `>=`, `<=`, `=`, `!=`), boolean operators (`and`, `or`, `not`), string concatenation (`+`), path access (`order.total`), bracket access (`items[0]`), if-then-else, the `in` operator (lists and ranges), list literals, and function calls including space-separated names.

```elixir
RodarBpmn.Expression.Feel.eval("if x > 10 then \"high\" else \"low\"", %{"x" => 15})
# => {:ok, "high"}

RodarBpmn.Expression.Feel.eval("x in [1, 2, 3]", %{"x" => 2})
# => {:ok, true}

RodarBpmn.Expression.Feel.eval("string length(name)", %{"name" => "Alice"})
# => {:ok, 5}
```

## Built-in FEEL Functions

| Category | Functions |
|----------|-----------|
| Numeric | `abs(n)`, `floor(n)`, `ceiling(n)`, `round(n)`, `round(n, scale)`, `min(list)`, `max(list)`, `sum(list)`, `count(list)` |
| String | `string length(s)`, `contains(s, sub)`, `starts with(s, prefix)`, `ends with(s, suffix)`, `upper case(s)`, `lower case(s)`, `substring(s, start)`, `substring(s, start, length)` |
| Boolean | `not(b)` |
| Null | `is null(v)` |

All functions propagate `nil` -- if any argument is `nil`, the result is `nil`. The exceptions are `is null` (returns `true` for `nil`) and `not` (returns `nil` for `nil`).

## Elixir Sandbox

The Elixir evaluator parses expressions into AST and walks the tree against an allowlist before evaluation. Allowed operations include comparisons, boolean logic, math, string operations (`String.*`), collection functions (`Enum.*`, `Map.*`, `List.*`), data access, literals, `if`/`case`/`cond`, and pipes.

Dangerous operations are rejected at parse time:

```elixir
RodarBpmn.Expression.Sandbox.eval("System.cmd(\"ls\", [])")
# => {:error, "disallowed: module call System.cmd/2"}

RodarBpmn.Expression.Sandbox.eval("1 + 2")
# => {:ok, 3}
```

## Next Steps

- [Gateways](https://hexdocs.pm/rodar_bpmn/gateways.html) -- Conditional routing with expressions
- [Events](https://hexdocs.pm/rodar_bpmn/events.html) -- Timer, conditional, and message events
