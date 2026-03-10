# Combined Architecture

## Four-Layer Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                      Applications & Agents                          │
│  Claude, GPT, Custom Agents, Phoenix LiveView, CLI Tools           │
└──────────────────────────────┬──────────────────────────────────────┘
                               │ MCP Protocol
┌──────────────────────────────┴──────────────────────────────────────┐
│                       Protocol Layer                                │
│  MCP Server (expose BPMN)         MCP Client (call tools)          │
│  └─ rodar_bpmn_mcp                └─ rodar_bpmn_mcp               │
└──────────────────────────────┬──────────────────────────────────────┘
                               │ Public APIs + Extension Points
┌──────────────────────────────┴──────────────────────────────────────┐
│                    Integration Packages                              │
│  rodar_bpmn_oban   rodar_bpmn_ash   rodar_bpmn_mcp  rodar_bpmn_jido│
│  └─ Durable Timers └─ Persistence   └─ Server+Client└─ AI Handlers │
│  └─ Retryable Tasks└─ Resources/APIs└─ TaskHandler   └─ Signal Bridge│
│                    └─ StateMachine  └─ Tool Registry └─ Agent Subprocess│
│  rodar_bpmn_live                                                     │
│  └─ Task Forms     └─ Task Inbox    └─ Dashboard     └─ Visualization│
└──────────────────────────────┬──────────────────────────────────────┘
                               │ Behaviours + Callbacks
┌──────────────────────────────┴──────────────────────────────────────┐
│                        Core Engine (bpmn)                           │
│  Diagram Parser │ Token Executor │ Context │ Event Bus │ Registry  │
│  0 new dependencies │ 1 additive change (Phase 5 only)             │
└─────────────────────────────────────────────────────────────────────┘
```

## Bidirectional Agent Flow

```
External Agents ←→ MCP Server ←→ RodarBPMN Core ←→ MCP Client ←→ External Tools
                                        ↕                              ↕
                                   Ash (persistence)            Jido (AI agents)
```

**Left-to-right (agents drive workflows)**:
1. Agent calls `bpmn.deploy` → MCP Server → `Bpmn.Registry.register/2`
2. Agent calls `bpmn.start` → MCP Server → `Bpmn.Process.create_and_run/2`
3. Agent calls `bpmn.complete_task` → MCP Server → Resume from `{:manual, _}`

**Right-to-left (workflows drive agents/tools)**:
1. BPMN service task fires → `Bpmn.TaskRegistry` → `RodarBpmn.MCP.TaskHandler`
2. MCP Client connects to external server → calls tool → maps result to context
3. Or: `Bpmn.TaskRegistry` → `RodarBpmn.Jido.TaskHandler` → Jido agent executes

**Downward (persistence)**:
1. Process state changes → `Bpmn.Hooks` `:after_node` → Ash resource sync
2. Process dehydrates → `Bpmn.Persistence` → `RodarBpmn.Ash.Persistence` → Postgres

## Extension Point Mapping

| Extension Point | Module | Oban | Ash | MCP | Jido | LiveView |
|-----------------|--------|------|-----|-----|------|----------|
| `Bpmn.Event.Timer.Scheduler`* | `lib/bpmn/event/timer.ex` | Durable timers | — | — | — | — |
| `Bpmn.Persistence` behaviour | `lib/bpmn/persistence.ex` | — | Postgres adapter | — | — | — |
| `Bpmn.TaskHandler` behaviour | `lib/bpmn/task_handler.ex` | Retryable task wrapper | — | MCP client handler | AI agent handler | — |
| `Bpmn.TaskRegistry` | `lib/bpmn/task_registry.ex` | Register task wrapper | — | Register MCP handler | Register AI handlers | — |
| `Bpmn.Hooks` | `lib/bpmn/hooks.ex` | — | DB sync on events | — | Signal bridge | Real-time updates |
| `Bpmn.Event.Bus` | `lib/bpmn/event/bus.ex` | — | — | — | Signal bridge | — |
| `Bpmn.Telemetry` | `lib/bpmn/telemetry.ex` | — | Audit metrics | — | Observability | Live metrics |
| `Bpmn.Process` API | `lib/bpmn/process.ex` | — | State machine sync | MCP server tools | — | Process management |
| `Bpmn.Observability` API | `lib/bpmn/observability.ex` | — | Dashboard queries | MCP server tools | — | Dashboard |
| `Bpmn.Registry` | `lib/bpmn/registry.ex` | — | Definition storage | MCP deploy tool | — | — |
| `Bpmn.Context` API | `lib/bpmn/context.ex` | — | — | — | — | Form data |

*Phase 1 — the single additive core change, extracted for `rodar_bpmn_oban`.

## Data Flow Diagrams

### Ash Integration Data Flow

```
BPMN Process Instance
    │
    ├── token_in/2 → execute/3 → Hooks.notify(:after_node)
    │                                     │
    │                              Ash.Sync.record_node_completion()
    │                                     │
    │                              ProcessInstance resource (Postgres)
    │
    ├── {:manual, _} → auto_dehydrate
    │                       │
    │                  Bpmn.Persistence.save/2
    │                       │
    │                  Ash.Persistence.save/2 → ProcessSnapshot (Postgres)
    │
    └── End Event → Hooks.notify(:on_complete)
                          │
                   Ash.Sync.mark_completed() → ProcessInstance.complete
```

### MCP Server Data Flow

```
AI Agent (Claude/GPT)
    │
    ├── MCP tool call: bpmn.start({definition: "order", data: {amount: 100}})
    │       │
    │       └── MCP.Server.handle_tool("bpmn.start", params)
    │               │
    │               └── Bpmn.Process.create_and_run("order", %{amount: 100})
    │                       │
    │                       └── {:ok, pid} → {:ok, %{instance_id: ..., status: "started"}}
    │
    └── MCP tool call: bpmn.status({instance_id: "..."})
            │
            └── MCP.Server.handle_tool("bpmn.status", params)
                    │
                    └── Bpmn.Process.status(pid) → %{state: :active, ...}
```

### MCP Client Data Flow

```
BPMN Process Execution
    │
    ├── ServiceTask "query_database"
    │       │
    │       └── TaskRegistry.lookup("query_database")
    │               │
    │               └── RodarBpmn.MCP.TaskHandler.token_in/2
    │                       │
    │                       ├── Parse extension attributes (server, tool, input mapping)
    │                       ├── MCP.Client.connect("stdio:///path/to/db-server")
    │                       ├── MCP.Client.call_tool(client, "query", %{sql: "..."})
    │                       └── Context.put_data(context, :query_result, result)
    │
    └── Next node receives context with :query_result
```

### Jido Agent Data Flow

```
BPMN Process Execution
    │
    ├── ServiceTask "analyze_sentiment"
    │       │
    │       └── TaskRegistry.lookup("analyze_sentiment")
    │               │
    │               └── RodarBpmn.Jido.TaskHandler.token_in/2
    │                       │
    │                       ├── Parse jido: extension attributes
    │                       ├── Jido.Agent.new(SentimentAnalyzer, instructions: ...)
    │                       ├── Jido.Agent.run(agent, input, strategy: :chain_of_thought)
    │                       └── Context.put_data(context, :sentiment, result)
    │
    └── ExclusiveGateway routes based on sentiment score
```

## Core Changes Required

**Only one change** across the entire roadmap:

### Phase 1: Extract `Bpmn.Event.Timer.Scheduler` Behaviour

**File**: `lib/bpmn/event/timer.ex`

**Current state**:
```elixir
def schedule(context_pid, node_id, duration_ms) do
  ref = Process.send_after(context_pid, {:timer_fired, node_id, outgoing}, duration_ms)
  # ...
end
```

**After extraction** (additive, non-breaking):
```elixir
# New behaviour (additive)
defmodule Bpmn.Event.Timer.Scheduler do
  @callback schedule(pid(), term(), non_neg_integer()) :: reference()
  @callback cancel(reference()) :: :ok
end

# Default implementation (existing behavior, no change)
defmodule Bpmn.Event.Timer.Scheduler.Default do
  @behaviour Bpmn.Event.Timer.Scheduler
  def schedule(pid, msg, delay), do: Process.send_after(pid, msg, delay)
  def cancel(ref), do: Process.cancel_timer(ref) && :ok
end

# Existing code uses configured scheduler (defaults to Default)
defp scheduler do
  Application.get_env(:bpmn, :timer_scheduler, Bpmn.Event.Timer.Scheduler.Default)
end
```

This is:
- **Additive** — new modules, existing API unchanged
- **Non-breaking** — default implementation preserves current behavior
- **Configurable** — swap via application config, same pattern as persistence adapter

## Dependency Graph

```
                         ┌──────────────────┐
                         │    Application   │
                         └─┬───┬───┬───┬──┬─┘
                           │   │   │   │  │
         ┌─────────────────┘   │   │   │  └──────────────────┐
         ▼                     ▼   ▼   ▼                     ▼
┌────────────────┐ ┌────────────────┐ ┌──────────────┐ ┌─────────────────┐
│rodar_bpmn_oban │ │rodar_bpmn_ash  │ │rodar_bpmn_mcp│ │ rodar_bpmn_jido │
│                │ │                │ │              │ │                 │
│ oban           │ │ ash            │ │ mcp          │ │ jido            │
│ ecto_sql       │ │ ash_postgres   │ │ jason        │ │ jido_ai         │
│ postgrex       │ │ ash_state_mach │ │              │ │                 │
│                │ │ ash_graphql*   │ │              │ │                 │
│                │ │ ash_json_api*  │ │              │ │                 │
│                │ │ ash_paper_trail**│ │              │ │                 │
└───────┬────────┘ └───────┬────────┘ └──────┬───────┘ └────────┬────────┘
        │                  │                 │                   │
        │    ┌─────────────────────┐         │                   │
        │    │  rodar_bpmn_live    │         │                   │
        │    │                     │         │                   │
        │    │  phoenix_live_view  │         │                   │
        │    │  phoenix            │         │                   │
        │    └──────────┬──────────┘         │                   │
        │               │                    │                   │
        └───────────────┴────────────────────┴───────────────────┘
                                     ▼
                            ┌─────────────────┐
                            │   bpmn (core)   │
                            │                 │
                            │ erlsom          │
                            │ nimble_parsec   │
                            │ telemetry       │
                            │ uuid            │
                            │                 │
                            │ 0 new deps      │
                            └─────────────────┘

  * Optional (Phase 2b)
  ** Phase 5
```

## Implementation Timeline

| Phase | Focus | Est. Effort | Prerequisites |
|-------|-------|-------------|---------------|
| **Phase 1** | Oban Durable Timers & Tasks | Small | Timer.Scheduler behaviour extraction (one core change) |
| **Phase 2** | Ash Persistence, Resources + APIs | Medium | Phase 1 (shares Ecto/Postgres infrastructure) |
| **Phase 3** | MCP Server + Client | Medium | Phase 2 (APIs inform tool design) |
| **Phase 4** | Jido AI TaskHandlers | Medium | None (parallel with Phase 3) |
| **Phase 5** | Deep Integrations | Large | All previous phases |
| **Phase 6** | LiveView UI | Medium | Phase 5 (stable APIs); optionally Phase 2 (Ash persistence for historical queries) |

### Phase Dependencies

```
Phase 1 (Oban Timers & Tasks)
    │
    ├── Shares Ecto/Postgres ──→ Phase 2 (Ash Persistence + Resources + APIs) ──┐
    │                                │                                           │
    │                                ▼                                           ▼
    │                          Phase 3 (MCP Server + Client)              Phase 4 (Jido AI Handlers)
    │                                │                                           │
    │                                └──────────────┬────────────────────────────┘
    │                                               ▼
    └──────────────────────────────────→ Phase 5 (Deep Integrations)
                                                    │
                                                    ▼
                                        Phase 6 (LiveView UI)
```

Phases 3 and 4 can proceed in parallel once Phase 2 is complete. Phase 4 has no hard dependency on Phase 2 — it only needs the core. Phase 6 benefits from stable APIs (post-Phase 5) and optionally leverages Ash persistence (Phase 2) for querying historical data.

## Testing Strategy

### Per-Package Testing

| Package | Test Approach |
|---------|---------------|
| `rodar_bpmn_oban` | Oban testing mode (`:inline`); assert job insertion; integration tests for timer fire + task completion |
| `rodar_bpmn_ash` | Ash test helpers + Ecto sandbox; test against real Postgres; snapshot round-trip tests |
| `rodar_bpmn_mcp` | Mock MCP client/server; integration tests with in-process MCP transport; tool call round-trips |
| `rodar_bpmn_jido` | Mock Jido agents (deterministic responses); integration tests with real agents behind feature flag |

### Integration Testing

```elixir
# Full-stack test: Agent → MCP Server → BPMN → MCP Client → External Tool
test "agent orchestrates workflow that calls external tool" do
  # 1. Deploy a process via MCP server
  {:ok, _} = MCP.Server.handle_tool("bpmn.deploy", %{"xml" => xml, "name" => "test"})

  # 2. Start instance via MCP server
  {:ok, %{instance_id: id}} = MCP.Server.handle_tool("bpmn.start", %{
    "definition_id" => "test",
    "data" => %{"input" => "value"}
  })

  # 3. Verify MCP client task executed
  assert_receive {:mcp_tool_called, "external_tool", _input}

  # 4. Verify process completed
  {:ok, status} = MCP.Server.handle_tool("bpmn.status", %{"instance_id" => id})
  assert status.state == :completed
end
```

### Core Regression Testing

All integration packages must pass the core test suite:

```shell
# Run core tests to verify no regressions
cd deps/bpmn && mix test

# Run package tests
mix test

# Run integration tests (requires external services)
MIX_ENV=integration mix test --only integration
```

### Property-Based Testing

For serialization round-trips (Ash persistence) and signal bridge (Jido):

```elixir
property "snapshot round-trip preserves all data" do
  check all data <- process_data_generator() do
    snapshot = Bpmn.Persistence.Serializer.snapshot(data)
    serialized = Bpmn.Persistence.Serializer.serialize(snapshot)

    # Save to Postgres and load back
    :ok = RodarBpmn.Ash.Persistence.save("test", serialized)
    {:ok, loaded} = RodarBpmn.Ash.Persistence.load("test")

    restored = Bpmn.Persistence.Serializer.deserialize(loaded)
    assert restored == snapshot
  end
end
```
