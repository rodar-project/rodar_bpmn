# Hooks

The hook system lets you observe BPMN execution without modifying the engine or handlers. Hooks are per-context (not global) and observational-only — they cannot alter execution flow.

## Hook Events

| Event | When | Metadata |
|-------|------|----------|
| `:before_node` | Before a node is dispatched | `%{node_id, node_type, token}` |
| `:after_node` | After a node completes | `%{node_id, node_type, token, result}` |
| `:on_error` | When dispatch returns `{:error, _}` | `%{node_id, error}` |
| `:on_complete` | When an end event fires | `%{node_id}` |

## Registering Hooks

```elixir
{:ok, context} = Bpmn.Context.start_link(process, %{})

# Log every node entry
Bpmn.Hooks.register(context, :before_node, fn meta ->
  IO.puts("Entering node: #{meta.node_id} (#{meta.node_type})")
  :ok
end)

# Track completion
Bpmn.Hooks.register(context, :on_complete, fn meta ->
  IO.puts("Process completed at: #{meta.node_id}")
  :ok
end)
```

## Multiple Hooks

You can register multiple hooks for the same event. They are called in registration order:

```elixir
Bpmn.Hooks.register(context, :after_node, &MyApp.Metrics.record/1)
Bpmn.Hooks.register(context, :after_node, &MyApp.AuditLog.write/1)
```

## Removing Hooks

Remove all hooks for a specific event:

```elixir
Bpmn.Hooks.unregister(context, :before_node)
```

## Error Safety

Hook exceptions are caught and logged — they never break execution flow. This ensures that a faulty observer cannot crash the process.

## Hooks vs Telemetry

Both systems observe execution, but serve different purposes:

- **Hooks** are per-context, registered at runtime, and receive rich metadata including the token and result objects. Use for application-level logic (audit logging, metrics, debugging).
- **Telemetry** is global, uses `:telemetry` events, and integrates with the broader Erlang/Elixir observability ecosystem. Use for infrastructure monitoring (Prometheus, StatsD).
