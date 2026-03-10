# Observability

The engine provides two complementary observability mechanisms: telemetry events for infrastructure monitoring and query APIs for operational dashboards.

## Telemetry Events

All events use the `[:rodar_bpmn, ...]` prefix:

| Event | Measurements | Metadata |
|-------|-------------|----------|
| `[:rodar_bpmn, :node, :start]` | `%{system_time}` | `%{node_id, node_type, token_id}` |
| `[:rodar_bpmn, :node, :stop]` | `%{duration}` | `%{node_id, node_type, token_id, result}` |
| `[:rodar_bpmn, :node, :exception]` | `%{duration}` | `%{node_id, node_type, token_id, kind, reason}` |
| `[:rodar_bpmn, :process, :start]` | `%{system_time}` | `%{instance_id, process_id}` |
| `[:rodar_bpmn, :process, :stop]` | `%{duration}` | `%{instance_id, process_id, status}` |
| `[:rodar_bpmn, :token, :create]` | `%{system_time}` | `%{token_id, parent_id, node_id}` |
| `[:rodar_bpmn, :event_bus, :publish]` | `%{system_time}` | `%{event_type, event_name, subscriber_count}` |
| `[:rodar_bpmn, :event_bus, :subscribe]` | `%{system_time}` | `%{event_type, event_name, node_id}` |

## Attaching Handlers

Attach to all engine events at once using `RodarBpmn.Telemetry.events/0`:

```elixir
:telemetry.attach_many(
  "my-metrics",
  RodarBpmn.Telemetry.events(),
  &MyApp.Metrics.handle_event/4,
  nil
)
```

Or attach to specific events:

```elixir
:telemetry.attach(
  "node-timer",
  [:rodar_bpmn, :node, :stop],
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
RodarBpmn.Telemetry.LogHandler.attach()

# Detach when no longer needed
RodarBpmn.Telemetry.LogHandler.detach()
```

## Dashboard Queries

`RodarBpmn.Observability` provides read-only query APIs that tap into existing supervisors and registries:

```elixir
# All running process instances with pid, status, process_id, definition_version
RodarBpmn.Observability.running_instances()

# Instances waiting for external input (suspended)
RodarBpmn.Observability.waiting_instances()

# Filter by process ID and optional version
RodarBpmn.Observability.instances_by_version("order-process", 2)

# Execution history for a specific instance
RodarBpmn.Observability.execution_history(process_pid)

# Engine health check
RodarBpmn.Observability.health()
# => %{supervisor_alive: true, process_count: 5, context_count: 5,
#       registry_definitions: 3, event_subscriptions: 12}
```

## Hooks vs Telemetry

Both systems observe execution but serve different purposes:

- **Hooks** (`RodarBpmn.Hooks`) are per-context, registered at runtime, and receive rich metadata including token and result objects. Use for application-level logic like audit logging or business metrics.
- **Telemetry** (`RodarBpmn.Telemetry`) is global, uses the standard `:telemetry` library, and integrates with the Erlang/Elixir observability ecosystem (Prometheus, StatsD, OpenTelemetry). Use for infrastructure monitoring.

## Next Steps

- [Hooks](hooks.md) -- Per-context lifecycle observation
- [Process Lifecycle](https://hexdocs.pm/rodar_bpmn/process_lifecycle.html) -- Process states and management
