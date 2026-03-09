# Rodar BPMN Engine

[![CI](https://github.com/Around25/rodar-bpmn/actions/workflows/ci.yml/badge.svg)](https://github.com/Around25/rodar-bpmn/actions/workflows/ci.yml)
[![Hex Version](https://img.shields.io/hexpm/v/bpmn.svg)](https://hex.pm/packages/bpmn)

A BPMN 2.0 execution engine for Elixir. Parses BPMN 2.0 XML diagrams and executes processes using a token-based flow model.

## Table of contents

1. [Installation](#installation)
2. [Usage](#usage)
3. [Supported BPMN Elements](#supported-bpmn-elements)
4. [Architecture](#architecture)
5. [Development](#development)
6. [Contributing](CONTRIBUTING.md)
7. [Code of Conduct](CODE_OF_CONDUCT.md)
8. [License](#license)
9. [References](#references)

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

### Resuming a User Task

```elixir
# When a user task pauses execution, resume it with input data:
{:manual, task_data} = Bpmn.execute(start_event, context)

Bpmn.Activity.Task.User.resume(user_task_element, context, %{approved: true})
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
| Intermediate Event | Stub | |
| Boundary Event | Stub | |

### Gateways

| Element | Status | Notes |
|---------|--------|-------|
| Exclusive Gateway | Implemented | Condition evaluation, default flow |
| Parallel Gateway | Implemented | Fork/join with token synchronization |
| Inclusive Gateway | Stub | |
| Complex Gateway | Stub | |
| Event-Based Gateway | Stub | |

### Tasks

| Element | Status | Notes |
|---------|--------|-------|
| Script Task | Implemented | Elixir and JavaScript (via Node.js port) |
| User Task | Implemented | Pause/resume with `{:manual, task_data}` |
| Service Task | Implemented | Handler behaviour callback |
| Send Task | Stub | |
| Receive Task | Stub | |
| Manual Task | Stub | |

### Other

| Element | Status | Notes |
|---------|--------|-------|
| Sequence Flow | Implemented | Conditional expressions supported |
| Subprocess | Stub | |
| Embedded Subprocess | Stub | |

## Architecture

The engine uses a **token-based execution model**. Each BPMN node implements `token_in/2` to receive a token and routes it to the next node(s) via `Bpmn.release_token/2`.

Key modules:

- **`Bpmn`** — Main dispatcher; pattern-matches element type tuples to handler modules
- **`Bpmn.Context`** — Agent-based state management (process data, node metadata, token tracking)
- **`Bpmn.Expression`** — Evaluates condition expressions on sequence flows
- **`Bpmn.Engine.Diagram`** — Parses BPMN 2.0 XML via `erlsom`
- **`Bpmn.Port.Nodejs`** — GenServer managing a Node.js child process for JavaScript evaluation

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
