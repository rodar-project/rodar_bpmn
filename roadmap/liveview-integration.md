# LiveView Integration — UI for BPMN Workflows

**Package**: `rodar_bpmn_live`
**Namespace**: `RodarBpmn.Live.*`

## Why a Dedicated Package

A LiveView integration is much broader than a dashboard. It covers the full spectrum of user interaction with BPMN workflows:

- **User task forms** — Dynamic forms rendered from BPMN user task definitions
- **Task inbox** — Pending tasks per user/role, claim-and-complete workflow
- **Process management** — Start, stop, suspend, resume, migrate instances
- **Real-time dashboard** — Token positions, execution history, health checks
- **Process visualization** — BPMN diagram rendering with live token overlay

Each of these is a distinct LiveView component that composes into larger applications. Shipping as a separate package keeps the core dependency-free while giving Phoenix applications a rich BPMN UI out of the box.

## Value Matrix

| Capability | Current (Core) | LiveView-Enhanced |
|-----------|----------------|-------------------|
| User task completion | Programmatic `Process.resume/3` | Form submission in browser |
| Task visibility | `Observability.waiting_instances/0` | Filterable inbox per user/role |
| Process management | `Process.activate/1`, `suspend/1`, etc. | Point-and-click UI |
| Execution monitoring | `Observability.running_instances/0` | Real-time dashboard with auto-refresh |
| Process visualization | None | BPMN diagram with live token positions |
| Execution history | `Observability.execution_history/1` | Timeline view with node details |

## Core Changes Required

**None.** All functionality builds on existing public APIs and extension points.

## Extension Points Leveraged

| Extension Point | Usage |
|-----------------|-------|
| `Bpmn.Process` API | Start, stop, suspend, resume, migrate instances |
| `Bpmn.Observability` API | Running/waiting instances, execution history, health |
| `Bpmn.Hooks` | Real-time push updates via `:after_node`, `:on_complete` hooks |
| `Bpmn.Telemetry` | Live metrics display (node execution times, throughput) |
| `Bpmn.Context` API | Read/write form data for user tasks |
| `Bpmn.Registry` | List deployed definitions, version info |

## Package Structure

```
rodar_bpmn_live/
├── lib/rodar_bpmn_live/
│   ├── components/
│   │   ├── task_form.ex          # Dynamic form from user task definition
│   │   ├── task_inbox.ex         # Pending task list with filters
│   │   ├── process_list.ex       # Running/completed instances table
│   │   ├── process_detail.ex     # Single instance: status, history, actions
│   │   ├── diagram.ex            # BPMN diagram renderer (SVG)
│   │   └── health.ex             # System health summary
│   ├── hooks/
│   │   └── live_updater.ex       # Bpmn.Hooks handler → PubSub → LiveView
│   ├── router.ex                 # Optional plug-and-play routes
│   └── telemetry_listener.ex     # Telemetry → LiveView metric updates
├── assets/                        # JS hooks for diagram interactivity
└── mix.exs
```

## Component Details

### Task Form (`RodarBpmn.Live.Components.TaskForm`)

Renders a dynamic form based on user task metadata. On submission, calls `Bpmn.Process.resume/3` with form data to continue the suspended instance.

```elixir
# In a host application's LiveView
<.live_component
  module={RodarBpmn.Live.Components.TaskForm}
  id={"task-#{instance_id}"}
  instance_id={@instance_id}
  task_id={@task_id}
/>
```

Data flow:
1. Component reads task metadata from `Bpmn.Context` (field definitions, labels, validation)
2. Renders form fields with Phoenix form helpers
3. On submit, validates input and calls `Bpmn.Process.resume/3`
4. PubSub notification updates inbox and dashboard

### Task Inbox (`RodarBpmn.Live.Components.TaskInbox`)

Lists pending user/manual tasks. Supports filtering by user, role, or process definition. Tasks can be claimed (assigned to a user) and completed (opens task form).

```elixir
<.live_component
  module={RodarBpmn.Live.Components.TaskInbox}
  id="inbox"
  user={@current_user}
  filters={%{role: "approver"}}
/>
```

### Process Management (`RodarBpmn.Live.Components.ProcessList` / `ProcessDetail`)

Table of process instances with status, definition version, and actions. Detail view shows execution history timeline, current token positions, and management actions (suspend, resume, terminate, migrate).

### Real-Time Dashboard

Composes health, process list, and metrics into a single view. Uses `Bpmn.Hooks` via PubSub for live updates — no polling.

```elixir
# In live_updater.ex — bridges Bpmn.Hooks to Phoenix.PubSub
def after_node(context, node_id, result) do
  instance_id = Context.get_meta(context, :instance_id)
  Phoenix.PubSub.broadcast(pubsub, "bpmn:instance:#{instance_id}", {:node_completed, node_id, result})
  Phoenix.PubSub.broadcast(pubsub, "bpmn:dashboard", {:instance_updated, instance_id})
end
```

### BPMN Diagram Visualization

Renders the process diagram as SVG with token positions overlaid. Uses diagram coordinates from parsed BPMN XML (BPMNDiagram/BPMNPlane elements). Live tokens shown as animated markers.

## Phased Delivery

| Sub-phase | Deliverable | Dependencies |
|-----------|-------------|--------------|
| 6a | Task form + inbox components | Core only |
| 6b | Process management UI | Core only |
| 6c | Real-time dashboard | Core + PubSub bridge |
| 6d | BPMN diagram visualization | Core + diagram coordinates in parser |

Sub-phases 6a and 6b can proceed in parallel. 6c requires the PubSub bridge (hooks → PubSub). 6d may require parser enhancements to extract BPMNDiagram layout information.

## Dependencies

```
rodar_bpmn_live
├── bpmn (core)              # Required — all extension points
├── phoenix_live_view ~> 1.0 # Required — LiveView components
├── phoenix ~> 1.7           # Required — PubSub, router
└── rodar_bpmn_ash           # Optional — historical queries, richer task metadata
```

## Testing Strategy

| Area | Approach |
|------|----------|
| Components | LiveView test helpers (`live/2`, `render_component/2`), assert DOM structure |
| Hooks bridge | Subscribe to PubSub topic, trigger Bpmn.Hooks, assert message received |
| Task form | Render form, submit with valid/invalid data, assert process resumed or error shown |
| Integration | Full cycle: start process → hits user task → render form → submit → process completes |
