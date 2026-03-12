# Observability

The engine provides two complementary observability mechanisms: telemetry events for infrastructure monitoring and query APIs for operational dashboards.

## Telemetry Events

All events use the `[:rodar, ...]` prefix:

| Event | Measurements | Metadata |
|-------|-------------|----------|
| `[:rodar, :node, :start]` | `%{system_time}` | `%{node_id, node_type, token_id}` |
| `[:rodar, :node, :stop]` | `%{duration}` | `%{node_id, node_type, token_id, result}` |
| `[:rodar, :node, :exception]` | `%{duration}` | `%{node_id, node_type, token_id, kind, reason}` |
| `[:rodar, :process, :start]` | `%{system_time}` | `%{instance_id, process_id}` |
| `[:rodar, :process, :stop]` | `%{duration}` | `%{instance_id, process_id, status}` |
| `[:rodar, :token, :create]` | `%{system_time}` | `%{token_id, parent_id, node_id}` |
| `[:rodar, :event_bus, :publish]` | `%{system_time}` | `%{event_type, event_name, subscriber_count}` |
| `[:rodar, :event_bus, :subscribe]` | `%{system_time}` | `%{event_type, event_name, node_id}` |

## Attaching Handlers

Attach to all engine events at once using `Rodar.Telemetry.events/0`:

```elixir
:telemetry.attach_many(
  "my-metrics",
  Rodar.Telemetry.events(),
  &MyApp.Metrics.handle_event/4,
  nil
)
```

Or attach to specific events:

```elixir
:telemetry.attach(
  "node-timer",
  [:rodar, :node, :stop],
  fn _event, %{duration: d}, meta, _config ->
    duration_ms = System.convert_time_unit(d, :native, :millisecond)
    MyApp.Metrics.record_node_duration(meta.node_id, duration_ms)
  end,
  nil
)
```

## Built-in Log Handler

The default log handler writes telemetry events to `Logger` at appropriate levels (debug for nodes/tokens, info for processes, error for exceptions):

```elixir
# Attach in Application.start/2
Rodar.Telemetry.LogHandler.attach()

# Detach when no longer needed
Rodar.Telemetry.LogHandler.detach()
```

## Dashboard Queries

`Rodar.Observability` provides read-only query APIs that tap into existing supervisors and registries:

```elixir
# All running process instances with pid, status, process_id, definition_version
Rodar.Observability.running_instances()

# Instances waiting for external input (suspended)
Rodar.Observability.waiting_instances()

# Filter by process ID and optional version
Rodar.Observability.instances_by_version("order-process", 2)

# Execution history for a specific instance
Rodar.Observability.execution_history(process_pid)
# => [%{node_id: "start_1", token_id: "abc", result: :ok, ...}, ...]
```

Each history entry includes a `result` field that reflects how the node itself completed:

- `:ok` — node completed successfully (including nodes that called `release_token` to forward execution downstream)
- `:manual` — node suspended execution (user task, receive task, etc.)
- `:error` — node encountered an error
- `:fatal` — unrecoverable failure
- `:not_implemented` — no handler for this element type

A node that calls `release_token` is always classified as `:ok`, even when a downstream node suspends or errors. This ensures that execution history accurately reflects each node's own outcome rather than the propagated result of the entire chain.

```elixir
# Engine health check
Rodar.Observability.health()
# => %{supervisor_alive: true, process_count: 5, context_count: 5,
#       registry_definitions: 3, event_subscriptions: 12}
```

## Hooks vs Telemetry

Both systems observe execution but serve different purposes:

- **Hooks** (`Rodar.Hooks`) are per-context, registered at runtime, and receive rich metadata including token and result objects. Use for application-level logic like audit logging or business metrics.
- **Telemetry** (`Rodar.Telemetry`) is global, uses the standard `:telemetry` library, and integrates with the Erlang/Elixir observability ecosystem (Prometheus, StatsD, OpenTelemetry). Use for infrastructure monitoring.

## Next Steps

- [Hooks](hooks.md) -- Per-context lifecycle observation
- [Process Lifecycle](https://hexdocs.pm/rodar/process_lifecycle.html) -- Process states and management
