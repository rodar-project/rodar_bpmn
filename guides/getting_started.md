# Getting Started

## Installation

Add `rodar_bpmn` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [{:rodar_bpmn, github: "rodar-project/rodar-bpmn"}]
end
```

Requires Elixir ~> 1.16 and OTP 27+.

## Quick Start

### 1. Load and Parse a BPMN Diagram

```elixir
diagram = RodarBpmn.Engine.Diagram.load(File.read!("my_process.bpmn"))
{:bpmn_process, _attrs, _elements} = process = hd(diagram.processes)
```

### 2. Register and Run

```elixir
RodarBpmn.Registry.register("my-process", process)
{:ok, pid} = RodarBpmn.Process.create_and_run("my-process", %{"username" => "alice"})
```

### 3. Check Results

```elixir
RodarBpmn.Process.status(pid)
# => :completed

context = RodarBpmn.Process.get_context(pid)
RodarBpmn.Context.get_data(context, "result")
```

## Basic Concepts

### Token-Based Execution

The engine uses a token-based model. A `RodarBpmn.Token` struct tracks the execution pointer (current node, state, parent token for forks). Each BPMN node implements `token_in/2` to receive a token and routes it to the next node(s) via `RodarBpmn.release_token/2`.

### Context

`RodarBpmn.Context` is a GenServer that holds the process state: initial data, current data, process definition, node metadata, and execution history.

### Result Types

Node execution returns one of:

- `{:ok, context}` — success
- `{:error, message}` — error
- `{:manual, task_data}` — waiting for external input (user task, receive task)
- `{:fatal, reason}` — fatal error
- `{:not_implemented}` — unimplemented node type

### Validation

Validate your BPMN diagrams before execution:

```elixir
case RodarBpmn.Validation.validate(elements) do
  {:ok, _} -> IO.puts("Valid!")
  {:error, issues} -> Enum.each(issues, &IO.puts(&1.message))
end
```

Or from the command line:

```shell
mix rodar_bpmn.validate my_process.bpmn
```

## Next Steps

- [Process Lifecycle](process_lifecycle.md) — Instance creation, status transitions, suspend/resume
- [Events](events.md) — Start, end, intermediate, boundary events and the event bus
- [Gateways](gateways.md) — Exclusive, parallel, inclusive, complex, and event-based gateways
- [Expressions](expressions.md) — FEEL and Elixir sandbox expression evaluation
- [Task Handlers](task_handlers.md) — Register custom task implementations
- [Hooks](hooks.md) — Observe execution with lifecycle hooks
- [CLI Tools](cli.md) — Mix tasks for validation, inspection, and execution
