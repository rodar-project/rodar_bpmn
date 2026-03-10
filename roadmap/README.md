# RodarBPMN Integration Roadmap

## Vision

RodarBPMN is a dependency-minimal BPMN 2.0 execution engine (4 runtime deps). The core stays lean and dependency-free. All integrations ship as **separate hex packages** that plug into existing extension points — no framework lock-in, no bloated core.

## Three Integration Vectors

```
External Agents ←→ MCP Server ←→ RodarBPMN Core ←→ MCP Client ←→ External Tools
                                        ↕                              ↕
                                   Ash (persistence)            Jido (AI agents)
```

### Bidirectional Agent Flow

The key architectural insight is that BPMN workflows participate in agent ecosystems in **two complementary directions**:

1. **Workflows driven by agents** — An MCP server exposes BPMN operations as tools. Any MCP-compatible agent (Claude, GPT, custom) can deploy, start, monitor, and interact with business processes.

2. **Workflows drive agents** — BPMN service tasks delegate to external tools via MCP client connections and Jido AI agents. The workflow becomes a universal orchestrator.

## Packages

| Package | Purpose | Core Changes |
|---------|---------|--------------|
| `rodar_bpmn_oban` | Durable timers, retryable tasks | One additive behaviour extraction (Timer.Scheduler) |
| `rodar_bpmn_ash` | Resources, APIs, state machine, audit | None |
| `rodar_bpmn_mcp` | MCP server (expose workflows) + MCP client (call tools) | None |
| `rodar_bpmn_jido` | AI agent task handlers, signal bridge | None |
| `rodar_bpmn_live` | LiveView UI: forms, task inbox, dashboard, process visualization | None |

## Extension Points Leveraged

Every integration builds on existing RodarBPMN extension points:

| Extension Point | Used By |
|-----------------|---------|
| `Bpmn.Event.Timer.Scheduler` behaviour* | Oban (durable timers) |
| `Bpmn.Persistence` behaviour | Ash (Postgres adapter) |
| `Bpmn.TaskHandler` behaviour | Oban (retryable tasks), MCP client, Jido agents |
| `Bpmn.TaskRegistry` | Oban, MCP client, Jido agents |
| `Bpmn.Hooks` | Ash (DB sync), Jido (signal bridge), LiveView real-time updates |
| `Bpmn.Event.Bus` | Jido (signal bridge) |
| `Bpmn.Telemetry` | Ash (audit), observability dashboards, LiveView metrics |
| `Bpmn.Process` API | MCP server, LiveView process management |
| `Bpmn.Observability` API | MCP server, LiveView dashboard |
| `Bpmn.Registry` | MCP server |
| `Bpmn.Context` API | LiveView form data |

*Extracted in Phase 1 — additive, non-breaking.

## Phased Rollout

| Phase | Focus | Package | Key Deliverables |
|-------|-------|---------|------------------|
| 1 | Durable Timers & Tasks | `rodar_bpmn_oban` | Timer.Scheduler behaviour, Oban workers, retryable task wrapper |
| 2 | Persistence & Resources | `rodar_bpmn_ash` | Postgres persistence, Ash resources, AshStateMachine, GraphQL/REST |
| 3 | Workflows ↔ Agents | `rodar_bpmn_mcp` | MCP server exposing BPMN tools + MCP client TaskHandler |
| 4 | AI Agents | `rodar_bpmn_jido` | Jido AI TaskHandlers, reasoning strategies |
| 5 | Deep Integrations | All | Jido signal bridge, AshPaperTrail audit, authorization policies |
| 6 | LiveView UI | `rodar_bpmn_live` | User task forms, task inbox, dashboard, process visualization |

**Rationale**: Oban first — it solves the single biggest production gap (ephemeral timers) with minimal dependencies (Oban + Ecto + Postgrex, no framework commitment). Ash builds on the same Ecto/Postgres infrastructure. MCP server needs stable APIs, so it follows Ash. Jido for deep AI. Advanced features last.

## Core Changes Required

**Only one change** to the `bpmn` core package across the entire roadmap:

- **Extract `Bpmn.Event.Timer.Scheduler` behaviour** from `lib/bpmn/event/timer.ex`
- Default implementation stays as `Process.send_after` (fully backward compatible)
- Enables Oban durable scheduling as an alternative
- Phase 1 work — the first thing built, unlocking production-grade timers

## Document Index

1. **[Oban Integration](oban-integration.md)** — Durable timers, retryable tasks, the production foundation
2. **[Ash Framework Integration](ash-integration.md)** — Persistence, resources, APIs, audit trail
3. **[MCP Integration (Bidirectional)](mcp-integration.md)** — MCP server exposing workflows + MCP client calling external tools
4. **[Jido Framework Integration](jido-integration.md)** — AI agent task handlers, reasoning strategies, signal bridge
5. **[LiveView Integration](liveview-integration.md)** — User task forms, task inbox, process management, real-time dashboard
6. **[Combined Architecture](architecture.md)** — Four-layer architecture, data flows, extension point mapping, testing strategy
