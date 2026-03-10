# Getting Started

## Installation

Add `bpmn` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [{:bpmn, "~> 0.1.0-dev"}]
end
```

Requires Elixir ~> 1.16 and OTP 27+.

## Quick Start

### 1. Load and Parse a BPMN Diagram

```elixir
diagram = Bpmn.Engine.Diagram.load(File.read!("my_process.bpmn"))
{:bpmn_process, _attrs, _elements} = process = hd(diagram.processes)
```

### 2. Register and Run

```elixir
Bpmn.Registry.register("my-process", process)
{:ok, pid} = Bpmn.Process.create_and_run("my-process", %{"username" => "alice"})
```

### 3. Check Results

```elixir
Bpmn.Process.status(pid)
# => :completed

context = Bpmn.Process.get_context(pid)
Bpmn.Context.get_data(context, "result")
```

## Basic Concepts

### Token-Based Execution

The engine uses a token-based model. A `Bpmn.Token` struct tracks the execution pointer (current node, state, parent token for forks). Each BPMN node implements `token_in/2` to receive a token and routes it to the next node(s) via `Bpmn.release_token/2`.

### Context

`Bpmn.Context` is a GenServer that holds the process state: initial data, current data, process definition, node metadata, and execution history.

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
case Bpmn.Validation.validate(elements) do
  {:ok, _} -> IO.puts("Valid!")
  {:error, issues} -> Enum.each(issues, &IO.puts(&1.message))
end
```

Or from the command line:

```shell
mix bpmn.validate my_process.bpmn
```

## Next Steps

- [Task Handlers](task_handlers.md) — Register custom task implementations
- [Hooks](hooks.md) — Observe execution with lifecycle hooks
- [CLI Tools](cli.md) — Mix tasks for validation, inspection, and execution
