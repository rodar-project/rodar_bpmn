# Rodar BPMN Engine

[![CI](https://github.com/Around25/rodar-bpmn/actions/workflows/ci.yml/badge.svg)](https://github.com/Around25/rodar-bpmn/actions/workflows/ci.yml)
[![Hex Version](https://img.shields.io/hexpm/v/bpmn.svg)](https://hex.pm/packages/bpmn)

A BPMN 2.0 execution engine for Elixir. Parses BPMN 2.0 XML diagrams and executes processes using a token-based flow model.

## Table of contents

1. [Installation](#installation)
2. [Usage](#usage)
3. [Supported BPMN Elements](#supported-bpmn-elements)
4. [Architecture](#architecture)
5. [Validation](#validation)
6. [Collaboration](#collaboration)
7. [Observability](#observability)
8. [Development](#development)
9. [Contributing](CONTRIBUTING.md)
10. [Code of Conduct](CODE_OF_CONDUCT.md)
11. [License](#license)
12. [References](#references)

## Installation

The package is [available on Hex](https://hex.pm/packages/bpmn) and can be installed
by adding `bpmn` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [{:bpmn, "~> 0.1.0-dev"}]
end
```

Requires Elixir ~> 1.16 and OTP 27+.

## Usage

### Quick Start (Using Process Registry)

```elixir
# 1. Load and parse a BPMN diagram
diagram = Bpmn.Engine.Diagram.load(File.read!("my_process.bpmn"))
{:bpmn_process, _attrs, _elements} = process = hd(diagram.processes)

# 2. Register the process definition
Bpmn.Registry.register("my-process", process)

# 3. Create and run a process instance
{:ok, pid} = Bpmn.Process.create_and_run("my-process", %{"username" => "alice"})

# 4. Check status and access results
Bpmn.Process.status(pid)
# => :completed

context = Bpmn.Process.get_context(pid)
Bpmn.Context.get_data(context, "result")
```

### Manual Execution

```elixir
# 1. Load and parse a BPMN diagram
diagram = Bpmn.Engine.Diagram.load(File.read!("my_process.bpmn"))
[{:bpmn_process, _attrs, elements}] = diagram.processes

# 2. Create an execution context with initial data
{:ok, context} = Bpmn.Context.start_link(elements, %{"username" => "alice"})

# 3. Find and execute the start event
start_event = elements["StartEvent_1"]
result = Bpmn.execute(start_event, context)

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
Bpmn.Activity.Task.User.resume(user_task_element, context, %{approved: true})

# Manual task — waiting for external completion signal
Bpmn.Activity.Task.Manual.resume(manual_task_element, context, %{signed: true})

# Receive task — waiting for an external message
Bpmn.Activity.Task.Receive.resume(receive_task_element, context, %{payment_id: "PAY-123"})
```

### Event Bus (Message and Signal Events)

The event bus enables communication between process nodes via messages, signals, and escalations:

```elixir
# Subscribe a catch event to wait for a message
Bpmn.Event.Bus.subscribe(:message, "order_received", %{
  context: context,
  node_id: "catch1",
  outgoing: ["flow_out"]
})

# Publish a message (delivers to first subscriber, point-to-point)
Bpmn.Event.Bus.publish(:message, "order_received", %{data: %{order_id: "123"}})

# Publish a signal (broadcasts to ALL subscribers)
Bpmn.Event.Bus.publish(:signal, "system_alert", %{data: %{level: "warning"}})

# Send tasks auto-publish when messageRef is set
# Receive tasks auto-subscribe when messageRef is set
```

### Service Tasks

Define a handler module implementing the `Bpmn.Activity.Task.Service.Handler` behaviour:

```elixir
defmodule MyApp.CheckInventory do
  @behaviour Bpmn.Activity.Task.Service.Handler

  @impl true
  def execute(_attrs, data) do
    # Your business logic here
    {:ok, %{in_stock: true, quantity: 42}}
  end
end
```

## Supported BPMN Elements

### Events

| Element | Status | Notes |
|---------|--------|-------|
| Start Event | Implemented | Routes token to outgoing flows |
| End Event (plain) | Implemented | Normal process completion |
| End Event (error) | Implemented | Sets error state in context |
| End Event (terminate) | Implemented | Marks process as terminated |
| Intermediate Throw Event | Implemented | Publishes message/signal/escalation to event bus |
| Intermediate Catch Event | Implemented | Subscribes to event bus; returns `{:manual, _}` |
| Boundary Event (error) | Implemented | Activated by parent activity on error |
| Boundary Event (message) | Implemented | Subscribes to event bus |
| Boundary Event (signal) | Implemented | Subscribes to event bus |
| Boundary Event (timer) | Implemented | Schedules via `Process.send_after` |
| Boundary Event (escalation) | Implemented | Subscribes to event bus |

### Gateways

| Element | Status | Notes |
|---------|--------|-------|
| Exclusive Gateway | Implemented | Condition evaluation, default flow |
| Parallel Gateway | Implemented | Fork/join with token synchronization |
| Inclusive Gateway | Implemented | Fork/join with condition evaluation and activated-path tracking |
| Complex Gateway | Implemented | Expression-based activation rules; configurable join condition |
| Event-Based Gateway | Implemented | Returns `{:manual, _}` with downstream catch event info |

### Tasks

| Element | Status | Notes |
|---------|--------|-------|
| Script Task | Implemented | Elixir (sandboxed AST evaluation) |
| User Task | Implemented | Pause/resume with `{:manual, task_data}` |
| Service Task | Implemented | Handler behaviour callback |
| Send Task | Implemented | Publishes to event bus if `messageRef` present |
| Receive Task | Implemented | Subscribes to event bus if `messageRef` present; auto-resume on match |
| Manual Task | Implemented | Pause/resume like User Task; type `:manual_task` |

### Other

| Element | Status | Notes |
|---------|--------|-------|
| Sequence Flow | Implemented | Conditional expressions supported |
| Call Activity (Subprocess) | Implemented | Looks up external process from registry, executes in child context |
| Embedded Subprocess | Implemented | Executes nested elements within parent context; error boundary event propagation |
| Event Bus | Implemented | Registry-based pub/sub for message (point-to-point), signal/escalation (broadcast) |
| Timer | Implemented | ISO 8601 duration parsing (`PT5S`, `PT1H30M`), `Process.send_after` scheduling |
| Telemetry | Implemented | `:telemetry` events for node execution, process lifecycle, token creation, event bus |
| Observability | Implemented | Query APIs for running/waiting instances, execution history, health checks |
| Validation | Implemented | 9 structural rules + collaboration validation; opt-in at `activate/1` |
| Collaboration | Implemented | Multi-pool/multi-participant orchestration with message flow wiring |

## Architecture

The engine uses a **token-based execution model**. A `Bpmn.Token` struct tracks the execution pointer (current node, state, parent token for forks). Each BPMN node implements `token_in/2` to receive a token and routes it to the next node(s) via `Bpmn.release_token/2`.

### Key Modules

- **`Bpmn`** — Main dispatcher; pattern-matches element type tuples to handler modules. `execute/2` (simple) and `execute/3` (with token tracking and execution history).
- **`Bpmn.Token`** — Execution token struct with ID, current node, state, and parent tracking. Supports `fork/1` for parallel branches.
- **`Bpmn.Context`** — GenServer-based state management (process data, node metadata, gateway token tracking, execution history).
- **`Bpmn.Registry`** — Process definition registry using Elixir's `Registry` module. Register, lookup, and manage BPMN process definitions.
- **`Bpmn.Process`** — Process lifecycle GenServer. Create instances, activate, suspend, resume, terminate. Tracks status transitions.
- **`Bpmn.Expression`** — Evaluates condition expressions on sequence flows using the sandboxed evaluator.
- **`Bpmn.Expression.Sandbox`** — AST-restricted Elixir expression evaluator (replaces `Code.eval_string`).
- **`Bpmn.Engine.Diagram`** — Parses BPMN 2.0 XML via `erlsom`.
- **`Bpmn.Event.Bus`** — Registry-based pub/sub for BPMN events (message, signal, escalation).
- **`Bpmn.Event.Timer`** — ISO 8601 duration parsing and timer scheduling.
- **`Bpmn.Telemetry`** — Telemetry event definitions and helpers; wraps node execution with `:telemetry.span/3`.
- **`Bpmn.Telemetry.LogHandler`** — Default handler that converts telemetry events to structured `Logger` output.
- **`Bpmn.Observability`** — Read-only query APIs for running instances, waiting tasks, execution history, and health checks.
- **`Bpmn.Validation`** — Structural validation for process maps. 9 rules + collaboration validation. Opt-in via config.
- **`Bpmn.Collaboration`** — Multi-participant orchestration. Starts processes, wires message flows, activates all.

### Supervision Tree

```
Bpmn.Supervisor (one_for_one)
├── Bpmn.ProcessRegistry (Elixir Registry, :unique keys)
├── Bpmn.EventRegistry (Elixir Registry, :duplicate keys — event bus pub/sub)
├── Bpmn.Registry (GenServer for process definitions)
├── Bpmn.ContextSupervisor (DynamicSupervisor for context processes)
└── Bpmn.ProcessSupervisor (DynamicSupervisor for process instances)
```

## Validation

Validate parsed process maps for structural issues before execution:

```elixir
{:bpmn_process, _attrs, elements} = hd(diagram.processes)

case Bpmn.Validation.validate(elements) do
  {:ok, _} -> IO.puts("Process is valid")
  {:error, issues} -> Enum.each(issues, &IO.puts(&1.message))
end
```

Enable automatic validation on `Bpmn.Process.activate/1`:

```elixir
# In config/config.exs
config :bpmn, :validate_on_activate, true
```

Checks 9 rules: start/end event existence and connectivity, sequence flow ref integrity, orphan nodes, gateway outgoing counts, exclusive gateway defaults (warning), and boundary event attachment.

For collaboration diagrams, validate cross-process constraints:

```elixir
Bpmn.Validation.validate_collaboration(diagram.collaboration, diagram.processes)
```

## Collaboration

Orchestrate multi-pool BPMN diagrams with message flows between participants:

```elixir
# Parse a collaboration diagram with multiple pools
diagram = Bpmn.Engine.Diagram.load(File.read!("order_fulfillment.bpmn"))

# Start all participants — registers, wires message flows, activates
{:ok, result} = Bpmn.Collaboration.start(diagram)
# => %{collaboration_id: "Collab_1", instances: %{"OrderProcess" => pid1, "PaymentProcess" => pid2}}

# Check individual process status
Bpmn.Process.status(result.instances["OrderProcess"])

# Stop all processes
Bpmn.Collaboration.stop(result)
```

Message flows are pre-wired via `Bpmn.Event.Bus` before process activation, ensuring messages aren't lost if a throw event fires before its corresponding catch event subscribes.

## Observability

### Telemetry Events

The engine emits `:telemetry` events for all key operations. Attach your own handlers or use the built-in log handler:

```elixir
# Attach the default log handler
Bpmn.Telemetry.LogHandler.attach()

# Or attach a custom handler to specific events
:telemetry.attach_many("my-handler", Bpmn.Telemetry.events(), &MyHandler.handle/4, nil)
```

Events emitted:

| Event | Measurements | Metadata |
|-------|-------------|----------|
| `[:bpmn, :node, :start]` | `system_time` | `node_id`, `node_type`, `token_id` |
| `[:bpmn, :node, :stop]` | `duration` | `node_id`, `node_type`, `token_id`, `result` |
| `[:bpmn, :node, :exception]` | `duration` | `node_id`, `node_type`, `token_id`, `kind`, `reason` |
| `[:bpmn, :process, :start]` | `system_time` | `instance_id`, `process_id` |
| `[:bpmn, :process, :stop]` | `duration` | `instance_id`, `process_id`, `status` |
| `[:bpmn, :token, :create]` | `system_time` | `token_id`, `parent_id`, `node_id` |
| `[:bpmn, :event_bus, :publish]` | `system_time` | `event_type`, `event_name`, `subscriber_count` |
| `[:bpmn, :event_bus, :subscribe]` | `system_time` | `event_type`, `event_name`, `node_id` |

### Dashboard Queries

```elixir
# List all running process instances
Bpmn.Observability.running_instances()
# => [%{pid: #PID<0.123.0>, instance_id: "abc-123", status: :suspended}, ...]

# List only suspended (waiting) instances
Bpmn.Observability.waiting_instances()

# Get execution history for a process
Bpmn.Observability.execution_history(pid)

# Health check
Bpmn.Observability.health()
# => %{supervisor_alive: true, process_count: 3, context_count: 3,
#       registry_definitions: 2, event_subscriptions: 5}
```

### Structured Logging

Logger metadata is automatically set during execution:

- `bpmn_node_id`, `bpmn_node_type`, `bpmn_token_id` — set in `Bpmn.execute/3`
- `bpmn_instance_id`, `bpmn_process_id` — set in `Bpmn.Process` init

## Development

```shell
mix deps.get          # Fetch dependencies
mix compile           # Compile the project
mix test              # Run tests
mix credo             # Lint
mix dialyzer          # Static analysis
mix docs              # Generate documentation
```

## License

Copyright (c) 2017 Around 25 SRL

Licensed under the Apache 2.0 license.

## References

- [BPMN 2.0 Specification](https://www.omg.org/spec/BPMN/2.0/About-BPMN/)
- [Elixir](https://elixir-lang.org/)
- [Roadmap](ROADMAP.md)
