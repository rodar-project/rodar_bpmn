# Getting Started

## Installation

Add `rodar` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [{:rodar, github: "rodar-project/rodar"}]
end
```

Requires Elixir ~> 1.16 and OTP 27+.

## Quick Start

### 1. Load and Parse a BPMN Diagram

```elixir
diagram = Rodar.Engine.Diagram.load(File.read!("my_process.bpmn"))
{:bpmn_process, _attrs, _elements} = process = hd(diagram.processes)
```

You can also wire service task handlers at parse time. The easiest way is convention-based auto-discovery — scaffold handlers with `mix rodar.scaffold`, then load with the file path:

```elixir
# Auto-discovers handlers at MyApp.Workflow.MyProcess.Handlers.*
diagram = Rodar.Engine.Diagram.load(xml,
  bpmn_file: "my_process.bpmn",
  app_name: "MyApp"
)
```

Or wire handlers explicitly with `handler_map`:

```elixir
diagram = Rodar.Engine.Diagram.load(xml, handler_map: %{
  "Task_check" => MyApp.CheckInventory
})
```

See the [Task Handlers](task_handlers.md) guide for details on handler discovery, registration, and resolution priority.

### 2. Register and Run

```elixir
Rodar.Registry.register("my-process", process)
{:ok, pid} = Rodar.Process.create_and_run("my-process", %{"username" => "alice"})
```

### 3. Check Results

```elixir
Rodar.Process.status(pid)
# => :completed

context = Rodar.Process.get_context(pid)
Rodar.Context.get_data(context, "result")
```

## Basic Concepts

### Token-Based Execution

The engine uses a token-based model. A `Rodar.Token` struct tracks the execution pointer (current node, state, parent token for forks). Each BPMN node implements `token_in/2` to receive a token and routes it to the next node(s) via `Rodar.release_token/2`.

### Context

`Rodar.Context` is a GenServer that holds the process state: initial data, current data, process definition, node metadata, and execution history.

### Result Types

Node execution returns one of:

- `{:ok, context}` — success
- `{:error, message}` — error
- `{:manual, task_data}` — waiting for external input (user task, receive task)
- `{:fatal, reason}` — fatal error
- `{:not_implemented}` — unimplemented node type

### Lanes

Lanes assign flow nodes to roles, groups, or departments. They do not affect execution — the engine treats them as read-only annotations. Use `Rodar.Lane` to query lane assignments:

```elixir
{:bpmn_process, attrs, _elements} = hd(diagram.processes)
{:ok, lane} = Rodar.Lane.find_lane_for_node(attrs.lane_set, "UserTask_1")
lane.name
# => "HR Department"
```

### Validation

Validate your BPMN diagrams before execution:

```elixir
case Rodar.Validation.validate(elements) do
  {:ok, _} -> IO.puts("Valid!")
  {:error, issues} -> Enum.each(issues, &IO.puts(&1.message))
end
```

Or from the command line:

```shell
mix rodar.validate my_process.bpmn
```

## Next Steps

- [Process Lifecycle](process_lifecycle.md) — Instance creation, status transitions, suspend/resume
- [Events](events.md) — Start, end, intermediate, boundary events and the event bus
- [Gateways](gateways.md) — Exclusive, parallel, inclusive, complex, and event-based gateways
- [Expressions](expressions.md) — FEEL and Elixir sandbox expression evaluation
- [Task Handlers](task_handlers.md) — Register custom task implementations
- [Hooks](hooks.md) — Observe execution with lifecycle hooks
- [CLI Tools](cli.md) — Mix tasks for validation, inspection, and execution
