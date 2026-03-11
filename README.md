# Rodar BPMN Engine

[![CI](https://github.com/rodgco/rodar-bpmn/actions/workflows/ci.yml/badge.svg)](https://github.com/rodgco/rodar-bpmn/actions/workflows/ci.yml)
[![Hex Version](https://img.shields.io/hexpm/v/rodar_bpmn.svg)](https://hex.pm/packages/rodar_bpmn)

A BPMN 2.0 execution engine for Elixir. Parses BPMN 2.0 XML diagrams and executes processes using a token-based flow model.

## Table of contents

1. [Installation](#installation)
2. [Usage](#usage)
3. [Supported BPMN Elements](#supported-bpmn-elements)
4. [Architecture](#architecture)
5. [Task Handlers](#task-handlers)
6. [Hooks](#hooks)
7. [Validation](#validation)
8. [Collaboration](#collaboration)
9. [Observability](#observability)
10. [CLI Tools](#cli-tools)
11. [Development](#development)
12. [Versioning & Releases](#versioning--releases)
13. [Contributing](CONTRIBUTING.md)
14. [Code of Conduct](CODE_OF_CONDUCT.md)
15. [License](#license)
16. [References](#references)

## Installation

The package is [available on Hex](https://hex.pm/packages/rodar_bpmn) and can be installed
by adding `rodar_bpmn` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [{:rodar_bpmn, "~> 1.0.0"}]
end
```

Requires Elixir ~> 1.16 and OTP 27+.

## Usage

### Quick Start (Using Process Registry)

```elixir
# 1. Load and parse a BPMN diagram
diagram = RodarBpmn.Engine.Diagram.load(File.read!("my_process.bpmn"))
{:bpmn_process, _attrs, _elements} = process = hd(diagram.processes)

# 2. Register the process definition
RodarBpmn.Registry.register("my-process", process)

# 3. Create and run a process instance
{:ok, pid} = RodarBpmn.Process.create_and_run("my-process", %{"username" => "alice"})

# 4. Check status and access results
RodarBpmn.Process.status(pid)
# => :completed

context = RodarBpmn.Process.get_context(pid)
RodarBpmn.Context.get_data(context, "result")
```

### Manual Execution

```elixir
# 1. Load and parse a BPMN diagram
diagram = RodarBpmn.Engine.Diagram.load(File.read!("my_process.bpmn"))
[{:bpmn_process, _attrs, elements}] = diagram.processes

# 2. Create an execution context with initial data
{:ok, context} = RodarBpmn.Context.start_link(elements, %{"username" => "alice"})

# 3. Find and execute the start event
start_event = elements["StartEvent_1"]
result = RodarBpmn.execute(start_event, context)

case result do
  {:ok, context}       -> # Process completed successfully
  {:manual, task_data} -> # Waiting for user input (user task)
  {:error, message}    -> # Error occurred
  {:not_implemented}   -> # Reached an unimplemented node
end
```

### Resuming Paused Tasks

User tasks, manual tasks, and receive tasks all pause execution and return `{:manual, task_data}`. Resume them with input data:

```elixir
# User task — waiting for user input
RodarBpmn.Activity.Task.User.resume(user_task_element, context, %{approved: true})

# Manual task — waiting for external completion signal
RodarBpmn.Activity.Task.Manual.resume(manual_task_element, context, %{signed: true})

# Receive task — waiting for an external message
RodarBpmn.Activity.Task.Receive.resume(receive_task_element, context, %{payment_id: "PAY-123"})
```

### Event Bus (Message and Signal Events)

The event bus enables communication between process nodes via messages, signals, and escalations:

```elixir
# Subscribe a catch event to wait for a message
RodarBpmn.Event.Bus.subscribe(:message, "order_received", %{
  context: context,
  node_id: "catch1",
  outgoing: ["flow_out"]
})

# Publish a message (delivers to first subscriber, point-to-point)
RodarBpmn.Event.Bus.publish(:message, "order_received", %{data: %{order_id: "123"}})

# Publish a signal (broadcasts to ALL subscribers)
RodarBpmn.Event.Bus.publish(:signal, "system_alert", %{data: %{level: "warning"}})

# Send tasks auto-publish when messageRef is set
# Receive tasks auto-subscribe when messageRef is set
```

#### Message Correlation Keys

When multiple process instances wait for the same message name, correlation keys route messages to the correct instance:

```elixir
# Subscriber includes correlation metadata
RodarBpmn.Event.Bus.subscribe(:message, "payment_confirmed", %{
  context: context,
  node_id: "catch1",
  outgoing: ["flow_out"],
  correlation: %{key: "order_id", value: "ORD-123"}
})

# Publisher includes matching correlation — routes to the correct subscriber
RodarBpmn.Event.Bus.publish(:message, "payment_confirmed", %{
  data: %{amount: 99},
  correlation: %{key: "order_id", value: "ORD-123"}
})
```

In BPMN XML, set `correlationKey` on a `messageEventDefinition` to automatically extract the correlation value from context data:

```xml
<bpmn:messageEventDefinition messageRef="payment_confirmed" correlationKey="order_id" />
```

### Triggered Start Events

Auto-create process instances when a message or signal fires:

```elixir
# Register a process that has a message start event
RodarBpmn.Registry.register("order-process", process_definition)
RodarBpmn.Event.Start.Trigger.register("order-process")

# Publishing the matching message auto-creates a new instance
RodarBpmn.Event.Bus.publish(:message, "new_order", %{data: %{"item" => "widget"}})
# => A new "order-process" instance runs with %{"item" => "widget"} as init data
```

### Service Tasks

Define a handler module implementing the `RodarBpmn.Activity.Task.Service.Handler` behaviour:

```elixir
defmodule MyApp.CheckInventory do
  @behaviour RodarBpmn.Activity.Task.Service.Handler

  @impl true
  def execute(_attrs, data) do
    # Your business logic here
    {:ok, %{in_stock: true, quantity: 42}}
  end
end
```

## Supported BPMN Elements

### Events

| Element                         | Status      | Notes                                                                     |
| ------------------------------- | ----------- | ------------------------------------------------------------------------- |
| Start Event                     | Implemented | Routes token to outgoing flows                                            |
| End Event (plain)               | Implemented | Normal process completion                                                 |
| End Event (error)               | Implemented | Sets error state in context                                               |
| End Event (terminate)           | Implemented | Marks process as terminated                                               |
| Intermediate Throw Event        | Implemented | Publishes message/signal/escalation to event bus                          |
| Intermediate Catch Event        | Implemented | Subscribes to event bus or conditional evaluation; returns `{:manual, _}` |
| Boundary Event (error)          | Implemented | Activated by parent activity on error                                     |
| Boundary Event (message)        | Implemented | Subscribes to event bus                                                   |
| Boundary Event (signal)         | Implemented | Subscribes to event bus                                                   |
| Boundary Event (timer)          | Implemented | Schedules via `Process.send_after`                                        |
| Boundary Event (escalation)     | Implemented | Subscribes to event bus                                                   |
| Boundary Event (conditional)    | Implemented | Subscribes to context data changes; fires when condition becomes true     |
| Boundary Event (compensate)     | Implemented | Passive — handler registration in dispatcher                              |
| Intermediate Throw (compensate) | Implemented | Triggers compensation; supports `activityRef` and `waitForCompletion`     |
| End Event (compensate)          | Implemented | Triggers compensation on process end                                      |

### Gateways

| Element             | Status      | Notes                                                           |
| ------------------- | ----------- | --------------------------------------------------------------- |
| Exclusive Gateway   | Implemented | Condition evaluation, default flow                              |
| Parallel Gateway    | Implemented | Fork/join with token synchronization                            |
| Inclusive Gateway   | Implemented | Fork/join with condition evaluation and activated-path tracking |
| Complex Gateway     | Implemented | Expression-based activation rules; configurable join condition  |
| Event-Based Gateway | Implemented | Returns `{:manual, _}` with downstream catch event info         |

### Tasks

| Element      | Status      | Notes                                                                 |
| ------------ | ----------- | --------------------------------------------------------------------- |
| Script Task  | Implemented | Elixir (sandboxed AST evaluation), FEEL                               |
| User Task    | Implemented | Pause/resume with `{:manual, task_data}`                              |
| Service Task | Implemented | Handler behaviour callback                                            |
| Send Task    | Implemented | Publishes to event bus if `messageRef` present                        |
| Receive Task | Implemented | Subscribes to event bus if `messageRef` present; auto-resume on match |
| Manual Task  | Implemented | Pause/resume like User Task; type `:manual_task`                      |

### Other

| Element                    | Status      | Notes                                                                                                           |
| -------------------------- | ----------- | --------------------------------------------------------------------------------------------------------------- |
| Sequence Flow              | Implemented | Conditional expressions supported (Elixir + FEEL)                                                               |
| Call Activity (Subprocess) | Implemented | Looks up external process from registry, executes in child context                                              |
| Embedded Subprocess        | Implemented | Executes nested elements within parent context; error boundary event propagation                                |
| Event Bus                  | Implemented | Registry-based pub/sub for message (point-to-point with correlation keys), signal/escalation (broadcast)        |
| Compensation               | Implemented | Tracks completed activities; executes handlers in reverse order via `RodarBpmn.Compensation`                    |
| Triggered Start Events     | Implemented | Auto-create process instances on matching message/signal via `RodarBpmn.Event.Start.Trigger`                    |
| Timer                      | Implemented | ISO 8601 duration (`PT5S`, `PT1H30M`) and cycle parsing (`R3/PT10S`, `R/PT1M`), `Process.send_after` scheduling |
| Telemetry                  | Implemented | `:telemetry` events for node execution, process lifecycle, token creation, event bus                            |
| Observability              | Implemented | Query APIs for running/waiting instances, execution history, health checks                                      |
| Validation                 | Implemented | 9 structural rules + collaboration validation; opt-in at `activate/1`                                           |
| Collaboration              | Implemented | Multi-pool/multi-participant orchestration with message flow wiring                                             |

## Task Handlers

Register custom task types or override specific task instances:

```elixir
defmodule MyApp.ApprovalHandler do
  @behaviour RodarBpmn.TaskHandler

  @impl true
  def token_in({_type, %{id: _id, outgoing: outgoing}}, context) do
    RodarBpmn.Context.put_data(context, "approved", true)
    RodarBpmn.release_token(outgoing, context)
  end
end

# Register for a custom type atom
RodarBpmn.TaskRegistry.register(:approval_task, MyApp.ApprovalHandler)

# Or override a specific task by ID
RodarBpmn.TaskRegistry.register("Task_approval_1", MyApp.ApprovalHandler)
```

Lookup priority: task ID (string) first, then task type (atom), then built-in handlers.

## Hooks

Per-context hooks for observing execution without modifying flow:

```elixir
{:ok, context} = RodarBpmn.Context.start_link(process, %{})

RodarBpmn.Hooks.register(context, :before_node, fn meta ->
  IO.puts("Entering: #{meta.node_id}")
  :ok
end)

RodarBpmn.Hooks.register(context, :on_complete, fn meta ->
  IO.puts("Done at: #{meta.node_id}")
  :ok
end)
```

Events: `:before_node`, `:after_node`, `:on_error`, `:on_complete`. Hook exceptions are caught and logged — they never break execution.

## Architecture

The engine uses a **token-based execution model**. A `RodarBpmn.Token` struct tracks the execution pointer (current node, state, parent token for forks). Each BPMN node implements `token_in/2` to receive a token and routes it to the next node(s) via `RodarRodarBpmn.release_token/2`.

### Key Modules

- **`RodarBpmn`** — Main dispatcher; pattern-matches element type tuples to handler modules. `execute/2` (simple) and `execute/3` (with token tracking and execution history).
- **`RodarBpmn.Token`** — Execution token struct with ID, current node, state, and parent tracking. Supports `fork/1` for parallel branches.
- **`RodarBpmn.Context`** — GenServer-based state management (process data, node metadata, gateway token tracking, execution history).
- **`RodarBpmn.Registry`** — Process definition registry using Elixir's `Registry` module. Register, lookup, and manage BPMN process definitions.
- **`RodarBpmn.Process`** — Process lifecycle GenServer. Create instances, activate, suspend, resume, terminate. Tracks status transitions.
- **`RodarBpmn.Expression`** — Evaluates condition expressions on sequence flows. Routes to the Elixir sandbox or FEEL evaluator based on language.
- **`RodarBpmn.Expression.Sandbox`** — AST-restricted Elixir expression evaluator (replaces `Code.eval_string`).
- **`RodarBpmn.Expression.Feel`** — FEEL (Friendly Enough Expression Language) evaluator. NimbleParsec-based parser with null propagation, three-valued boolean logic, and built-in functions.
- **`RodarBpmn.Engine.Diagram`** — Parses BPMN 2.0 XML via `erlsom`.
- **`RodarBpmn.Event.Bus`** — Registry-based pub/sub for BPMN events (message, signal, escalation).
- **`RodarBpmn.Event.Timer`** — ISO 8601 duration parsing and timer scheduling.
- **`RodarBpmn.Telemetry`** — Telemetry event definitions and helpers; wraps node execution with `:telemetry.span/3`.
- **`RodarBpmn.Telemetry.LogHandler`** — Default handler that converts telemetry events to structured `Logger` output.
- **`RodarBpmn.Observability`** — Read-only query APIs for running instances, waiting tasks, execution history, and health checks.
- **`RodarBpmn.Validation`** — Structural validation for process maps. 9 rules + collaboration validation. Opt-in via config.
- **`RodarBpmn.Collaboration`** — Multi-participant orchestration. Starts processes, wires message flows, activates all.
- **`RodarBpmn.TaskHandler`** — Behaviour for custom task handlers. Register by type atom or task ID string via `RodarBpmn.TaskRegistry`.
- **`RodarBpmn.Hooks`** — Per-context hook system for observing execution (before/after node, on error, on complete).
- **`RodarBpmn.Compensation`** — Tracks completed activities and their compensation handlers. Executes in reverse completion order.

### Supervision Tree

```
RodarBpmn.Supervisor (one_for_one)
├── RodarBpmn.ProcessRegistry (Elixir Registry, :unique keys)
├── RodarBpmn.EventRegistry (Elixir Registry, :duplicate keys — event bus pub/sub)
├── RodarBpmn.Registry (GenServer for process definitions)
├── RodarBpmn.TaskRegistry (GenServer for custom task handler registrations)
├── RodarBpmn.ContextSupervisor (DynamicSupervisor for context processes)
├── RodarBpmn.ProcessSupervisor (DynamicSupervisor for process instances)
└── RodarBpmn.Event.Start.Trigger (GenServer for signal/message-triggered start events)
```

## Validation

Validate parsed process maps for structural issues before execution:

```elixir
{:bpmn_process, _attrs, elements} = hd(diagram.processes)

case RodarBpmn.Validation.validate(elements) do
  {:ok, _} -> IO.puts("Process is valid")
  {:error, issues} -> Enum.each(issues, &IO.puts(&1.message))
end
```

Enable automatic validation on `RodarBpmn.Process.activate/1`:

```elixir
# In config/config.exs
config :rodar_bpmn, :validate_on_activate, true
```

Checks 9 rules: start/end event existence and connectivity, sequence flow ref integrity, orphan nodes, gateway outgoing counts, exclusive gateway defaults (warning), and boundary event attachment.

For collaboration diagrams, validate cross-process constraints:

```elixir
RodarBpmn.Validation.validate_collaboration(diagram.collaboration, diagram.processes)
```

## Collaboration

Orchestrate multi-pool BPMN diagrams with message flows between participants:

```elixir
# Parse a collaboration diagram with multiple pools
diagram = RodarBpmn.Engine.Diagram.load(File.read!("order_fulfillment.bpmn"))

# Start all participants — registers, wires message flows, activates
{:ok, result} = RodarBpmn.Collaboration.start(diagram)
# => %{collaboration_id: "Collab_1", instances: %{"OrderProcess" => pid1, "PaymentProcess" => pid2}}

# Check individual process status
RodarBpmn.Process.status(result.instances["OrderProcess"])

# Stop all processes
RodarBpmn.Collaboration.stop(result)
```

Message flows are pre-wired via `RodarBpmn.Event.Bus` before process activation, ensuring messages aren't lost if a throw event fires before its corresponding catch event subscribes.

## Observability

### Telemetry Events

The engine emits `:telemetry` events for all key operations. Attach your own handlers or use the built-in log handler:

```elixir
# Attach the default log handler
RodarBpmn.Telemetry.LogHandler.attach()

# Or attach a custom handler to specific events
:telemetry.attach_many("my-handler", RodarBpmn.Telemetry.events(), &MyHandler.handle/4, nil)
```

Events emitted:

| Event                                   | Measurements  | Metadata                                             |
| --------------------------------------- | ------------- | ---------------------------------------------------- |
| `[:rodar_bpmn, :node, :start]`          | `system_time` | `node_id`, `node_type`, `token_id`                   |
| `[:rodar_bpmn, :node, :stop]`           | `duration`    | `node_id`, `node_type`, `token_id`, `result`         |
| `[:rodar_bpmn, :node, :exception]`      | `duration`    | `node_id`, `node_type`, `token_id`, `kind`, `reason` |
| `[:rodar_bpmn, :process, :start]`       | `system_time` | `instance_id`, `process_id`                          |
| `[:rodar_bpmn, :process, :stop]`        | `duration`    | `instance_id`, `process_id`, `status`                |
| `[:rodar_bpmn, :token, :create]`        | `system_time` | `token_id`, `parent_id`, `node_id`                   |
| `[:rodar_bpmn, :event_bus, :publish]`   | `system_time` | `event_type`, `event_name`, `subscriber_count`       |
| `[:rodar_bpmn, :event_bus, :subscribe]` | `system_time` | `event_type`, `event_name`, `node_id`                |

### Dashboard Queries

```elixir
# List all running process instances
RodarBpmn.Observability.running_instances()
# => [%{pid: #PID<0.123.0>, instance_id: "abc-123", status: :suspended}, ...]

# List only suspended (waiting) instances
RodarBpmn.Observability.waiting_instances()

# Get execution history for a process
RodarBpmn.Observability.execution_history(pid)

# Health check
RodarBpmn.Observability.health()
# => %{supervisor_alive: true, process_count: 3, context_count: 3,
#       registry_definitions: 2, event_subscriptions: 5}
```

### Structured Logging

Logger metadata is automatically set during execution:

- `rodar_bpmn_node_id`, `rodar_bpmn_node_type`, `rodar_bpmn_token_id` — set in `RodarRodarBpmn.execute/3`
- `rodar_bpmn_instance_id`, `rodar_bpmn_process_id` — set in `RodarBpmn.Process` init

## CLI Tools

### Validate a BPMN file

```shell
mix rodar_bpmn.validate path/to/process.bpmn
```

### Inspect parsed structure

```shell
mix rodar_bpmn.inspect path/to/process.bpmn
```

### Execute a process

```shell
mix rodar_bpmn.run path/to/process.bpmn
mix rodar_bpmn.run path/to/process.bpmn --data '{"username": "alice"}'
```

## Development

```shell
mix deps.get          # Fetch dependencies
mix compile           # Compile the project
mix test              # Run tests
mix credo             # Lint
mix dialyzer          # Static analysis
mix docs              # Generate documentation
mix rodar_bpmn.validate <file>   # Validate a BPMN file
mix rodar_bpmn.inspect <file>    # Inspect parsed structure
mix rodar_bpmn.run <file>        # Execute a process
```

### BPMN Conformance Tests

The engine is validated against the [BPMN MIWG](https://www.omg.org/cgi-bin/doc?bmi/) reference test suite, ensuring interoperability with diagrams from Camunda, Signavio, Bizagi, and other BPMN tools.

```shell
mix test test/rodar_bpmn/conformance/                    # Run all conformance tests
mix test test/rodar_bpmn/conformance/parse_test.exs      # MIWG parse verification
mix test test/rodar_bpmn/conformance/execution_test.exs  # 12 execution patterns
mix test test/rodar_bpmn/conformance/coverage_test.exs   # Element type coverage
```

Tests cover:

- **Parse conformance** — MIWG reference files (A.1.0–B.2.0) parse correctly regardless of namespace prefix
- **Execution patterns** — 12 standard BPMN patterns (sequential, gateways, timers, messages, signals, error boundaries, compensation, subprocesses, event-based routing)
- **Element coverage** — Reports supported element types against the most complex MIWG reference (B.2.0)

## Versioning & Releases

This project follows [Semantic Versioning](https://semver.org/). The current version lives in the `VERSION` file at the project root and is read by `mix.exs` at compile time.

- **Development** happens on `develop` with a `-dev` suffix (e.g., `1.0.0-dev`)
- **Releases** are cut on `main` after merging `develop`:
  1. Merge `develop` into `main`
  2. Run `mix rodar_bpmn.release <patch|minor|major>` on `main`
  3. Merge `main` back into `develop` to pick up the version bump
- **Changelog** follows [Keep a Changelog](https://keepachangelog.com/) format in `CHANGELOG.md`
- **Git tags** use the `v{version}` format (e.g., `v1.0.0`)

### Create a release

```shell
mix rodar_bpmn.release patch          # Release current version, bump patch
mix rodar_bpmn.release minor          # Release current version, bump minor
mix rodar_bpmn.release major          # Release current version, bump major
mix rodar_bpmn.release patch --dry-run  # Preview without making changes
```

## Acknowledgments

This project is based on [Hashiru BPMN](https://github.com/around25/hashiru-bpmn) by [Around25](https://around25.com). We are grateful for the foundation they built — the original BPMN 2.0 XML parser and token-based execution model that this engine extends.

## License

Copyright (c) 2026 - Rodrigo Couto

Licensed under the Apache 2.0 license.

## References

- [BPMN 2.0 Specification](https://www.omg.org/spec/BPMN/2.0/About-BPMN/)
- [Elixir](https://elixir-lang.org/)
