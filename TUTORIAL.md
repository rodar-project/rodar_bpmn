# Hashiru BPMN Tutorial

Hashiru BPMN is an Elixir execution engine for BPMN 2.0 process definitions. It parses BPMN XML files into Elixir data structures and executes them by passing tokens through process nodes.

## BPMN Primer for Elixir Developers

If you're familiar with OTP but new to BPMN, here are the core concepts:

- **Process** — A workflow definition (think of it as a directed graph of steps).
- **Start Event** — The entry point of a process. Every process has at least one.
- **End Event** — Marks the end of a process path.
- **Task** — A unit of work (script, service call, user interaction, etc.).
- **Gateway** — A branching/merging point. An exclusive gateway routes the token down exactly one path based on conditions.
- **Sequence Flow** — A directed edge connecting two nodes, optionally with a condition expression.
- **Token** — An execution pointer that travels through the process graph. When a node completes, it releases a token to the next node(s) via outgoing sequence flows.

## Current Status

This library is at version `0.1.0-dev` targeting Elixir ~> 1.16 with OTP 27+. The following are fully implemented: start events, end events (plain, error, terminate), sequence flows with condition expressions, exclusive/parallel/inclusive gateways, script/user/service/manual/send/receive tasks, and embedded subprocesses. Complex gateways, event-based gateways, intermediate events, and boundary events are defined but awaiting the Phase 5 event bus.

## Setup

Add the dependency to your `mix.exs`:

```elixir
def deps do
  [{:bpmn, "~> 0.1.0-dev"}]
end
```

Then fetch and compile:

```bash
mix deps.get && mix compile
```

The OTP application starts automatically — `Bpmn.Application` launches a supervisor tree that includes `Bpmn.Port.Supervisor` (for the Node.js port used by script tasks).

## Loading a BPMN Diagram

Use `Bpmn.Engine.Diagram.load/1` to parse a BPMN 2.0 XML string into an Elixir map:

```elixir
xml = File.read!("./priv/bpmn/examples/user_login.bpmn")
diagram = Bpmn.Engine.Diagram.load(xml)
```

The returned map has this shape:

```elixir
%{
  id: "Definitions_1",
  expression_language: "...",
  type_language: "...",
  processes: [
    {:bpmn_process, %{id: "user-login", name: "Login", ...}, %{
      "StartEvent_1" => {:bpmn_event_start, %{id: "StartEvent_1", outgoing: [...], ...}},
      "SequenceFlow_0u2ggjm" => {:bpmn_sequence_flow, %{id: "SequenceFlow_0u2ggjm", ...}},
      "ExclusiveGateway_1eglp8f" => {:bpmn_gateway_exclusive, %{id: "ExclusiveGateway_1eglp8f", ...}},
      ...
    }}
  ],
  item_definitions: %{}
}
```

Key points:

- `processes` is a list of `{:bpmn_process, attrs, elements}` tuples.
- `elements` is a map from node ID (string) to its tuple representation.
- Each node tuple follows the pattern `{:bpmn_<type>, %{id: ..., incoming: [...], outgoing: [...], ...}}`.

### The `user_login.bpmn` Example

The included `priv/bpmn/examples/user_login.bpmn` models a login flow:

1. **START** (StartEvent_1) — Entry point, expects `username` and `password`.
2. **CHECK USER EXISTS** (Task_1ymg9vn) — Script task that looks up the user.
3. **USER EXISTS?** (ExclusiveGateway_1eglp8f) — Routes based on whether a user was found.
4. If NO → **Error End Event** (EndEvent_1s3wrav) with an error event definition.
5. If YES → **GENERATE TOKEN** (Task_0iy3d09) → **MIXPANEL EVENT** (Task_1y7eqry) → **END** (EndEvent_0y3z10o).

### Internal Tuple Representation

Each parsed element becomes a tagged tuple with atom keys. For example, the start event:

```elixir
{:bpmn_event_start, %{
  id: "StartEvent_1",
  name: "START",
  incoming: [],
  outgoing: ["SequenceFlow_0u2ggjm"],
  conditionalEventDefinition: nil,
  errorEventDefinition: nil,
  ...
}}
```

A sequence flow with a condition:

```elixir
{:bpmn_sequence_flow, %{
  id: "SequenceFlow_1keu1zs",
  name: "NO",
  sourceRef: "ExclusiveGateway_1eglp8f",
  targetRef: "EndEvent_1s3wrav",
  conditionExpression: {:bpmn_condition_expression, %{expression: "!Boolean(data.user)"}},
  isImmediate: nil
}}
```

## Creating an Execution Context

The execution context is an Agent that tracks process state. Create one with `Bpmn.Context.start_link/2`:

```elixir
# Extract the first process's element map
{:bpmn_process, _attrs, elements} = hd(diagram.processes)

# Start a context with the process elements and initial data
{:ok, context} = Bpmn.Context.start_link(elements, %{"username" => "alice", "password" => "secret"})
```

The first argument is the process element map (used to look up nodes during execution). The second is the initial data, accessible later via the context.

### Reading and Writing Context State

```elixir
# Read top-level keys — :init, :data, :process, :nodes
Bpmn.Context.get(context, :init)
# => %{"username" => "alice", "password" => "secret"}

Bpmn.Context.get(context, :process)
# => %{"StartEvent_1" => {:bpmn_start_event, %{...}}, ...}

# Read/write the data map (mutable state during execution)
Bpmn.Context.put_data(context, "user", %{"name" => "Alice"})
Bpmn.Context.get_data(context, "user")
# => %{"name" => "Alice"}

# Node metadata tracking
Bpmn.Context.put_meta(context, "StartEvent_1", %{active: false, completed: true})
Bpmn.Context.get_meta(context, "StartEvent_1")
# => %{active: false, completed: true}

Bpmn.Context.node_completed?(context, "StartEvent_1")
# => true

Bpmn.Context.node_active?(context, "StartEvent_1")
# => false
```

## Executing a Process

Execution starts by calling `Bpmn.execute/2` with a node tuple and a context. The `execute/2` function pattern-matches on the node's tag to dispatch to the appropriate module:

```elixir
# Get the start event from the process
start_event = elements["StartEvent_1"]
# => {:bpmn_event_start, %{outgoing: ["SequenceFlow_0u2ggjm"], ...}}

# Execute it
result = Bpmn.execute(start_event, context)
```

### How Execution Propagates

1. `Bpmn.execute/2` matches `{:bpmn_event_start, _}` and calls `Bpmn.Event.Start.token_in/2`.
2. `token_in/2` extracts the `outgoing` sequence flow IDs.
3. It calls `Bpmn.release_token/2` with those IDs and the context.
4. `release_token/2` looks up each target node in the process map via `Bpmn.next/2` and calls `Bpmn.execute/2` on it.
5. This continues recursively until a terminal node is reached.

When there are multiple outgoing targets (e.g., from a parallel gateway), `release_token/2` uses `Task.async_stream/2` to execute branches concurrently.

### Result Tuples

Node execution returns one of:

| Result | Meaning |
|--------|---------|
| `{:ok, context}` | Completed successfully; context contains updated state |
| `{:error, message}` | Execution error (e.g., node not found) |
| `{:error, message, fields}` | Validation/execution error with field details |
| `{:manual, data}` | Process paused at an external manual activity |
| `{:fatal, data}` | Fatal error in execution |
| `{:not_implemented}` | Reached a stub/unimplemented node |
| `{false}` | A conditional sequence flow evaluated to false |

## Working with Sequence Flows and Expressions

Sequence flows connect nodes. When a sequence flow has a `conditionExpression`, `Bpmn.SequenceFlow` evaluates it before proceeding.

### Conditional Evaluation

`Bpmn.Expression.execute/2` evaluates expressions against the context data:

```elixir
{:ok, context} = Bpmn.Context.start_link(%{}, %{})
Bpmn.Context.put_data(context, "count", 4)

# Expression is a tuple: {:bpmn_expression, {language, expression_string}}
Bpmn.Expression.execute({:bpmn_expression, {"elixir", "data[\"count\"]==4"}}, context)
# => {:ok, true}

Bpmn.Expression.execute({:bpmn_expression, {"elixir", "1==2"}}, context)
# => {:ok, false}
```

Internally, the expression string is wrapped in an anonymous function that receives `data` (the context's data map) and evaluated with `Code.eval_string/1`. This means any valid Elixir expression that references `data` will work.

### How Exclusive Gateways Route Tokens

In the `user_login.bpmn` example, the exclusive gateway has two outgoing sequence flows with conditions:

- `SequenceFlow_1keu1zs` (NO): `!Boolean(data.user)` — routes to error end event
- `SequenceFlow_0v8qyt9` (YES): `Boolean(data.user)` — routes to token generation

When `Bpmn.SequenceFlow.token_in/2` receives a flow with a condition, it evaluates the expression. If `{:ok, true}`, execution continues to the target. If `{:ok, false}`, it returns `{false}` and that path is skipped.

The **Exclusive Gateway** evaluates conditions on outgoing flows and routes the token to the first match (or default flow). The **Inclusive Gateway** evaluates all outgoing flows and releases tokens to every flow whose condition is true, then synchronizes at the join using activated-path tracking. The **Parallel Gateway** releases tokens to all outgoing flows and waits for all incoming tokens at the join.

## Script Tasks and the Node.js Port

### Script Task Execution

`Bpmn.Activity.Task.Script` handles script tasks. When a script task has `outputs`, `type`, and `script` attributes, it delegates JavaScript execution to the Node.js port. For other script tasks, it returns `{:not_implemented}`.

### The Node.js Port GenServer

`Bpmn.Port.Nodejs` is a GenServer that communicates with a Node.js process via Erlang ports:

```elixir
# Evaluate a JavaScript string
Bpmn.Port.Nodejs.eval_string("1+1", %{some: "context"})
# => %{"context" => %{"some" => "context"}, "script" => "1+1", "type" => "string"}

# Execute a JavaScript file
Bpmn.Port.Nodejs.eval_script("path/to/script.js", %{some: "context"})
```

Communication happens over JSON (using Jason for encoding/decoding). The Node.js process receives a JSON payload with `type` (`"string"` or `"file"`), `script`, and `context`, then returns the result as JSON.

## Putting It All Together

Here's a complete IEx session demonstrating the end-to-end flow:

```elixir
# 1. Load the BPMN diagram
xml = File.read!("./priv/bpmn/examples/user_login.bpmn")
diagram = Bpmn.Engine.Diagram.load(xml)

# 2. Extract the process elements
{:bpmn_process, attrs, elements} = hd(diagram.processes)
attrs.id
# => "user-login"

# 3. Create an execution context with initial data
{:ok, context} = Bpmn.Context.start_link(elements, %{"username" => "alice", "password" => "secret"})

# 4. Verify initial data is accessible
Bpmn.Context.get(context, :init)
# => %{"username" => "alice", "password" => "secret"}

# 5. Look up the start event
start_event = elements["StartEvent_1"]
# => {:bpmn_event_start, %{outgoing: ["SequenceFlow_0u2ggjm"], ...}}

# 6. Execute the process
result = Bpmn.execute(start_event, context)
# The start event releases a token to SequenceFlow_0u2ggjm,
# which leads to the "CHECK USER EXISTS" script task.
# Since script tasks are partially implemented, you'll likely see
# {:not_implemented} as the result.

# 7. To test with a simpler process, build one manually:
process = %{
  "flow1" => {:bpmn_sequence_flow, %{
    id: "flow1",
    name: "",
    sourceRef: "start",
    targetRef: "end1",
    conditionExpression: nil,
    isImmediate: nil
  }}
}
{:ok, ctx} = Bpmn.Context.start_link(process, %{})

# Execute the start event — it releases to flow1, which leads to end1
start = {:bpmn_event_start, %{incoming: [], outgoing: ["flow1"]}}
Bpmn.execute(start, ctx)
# The sequence flow will try to find "end1" in the process but since
# we didn't define it, this returns {:error, "Unable to find node 'end1'"}
```

## Implemented Modules

**Events:**
- `Bpmn.Event.Start` — Routes token to outgoing flows
- `Bpmn.Event.End` — Normal completion, error (sets error state), and terminate (stops parallel branches)

**Tasks:**
- `Bpmn.Activity.Task.Script` — Elixir and JavaScript execution (via Node.js port)
- `Bpmn.Activity.Task.User` — Pauses execution, returns `{:manual, task_data}`, `resume/3` to continue
- `Bpmn.Activity.Task.Service` — Invokes a handler module implementing `Bpmn.Activity.Task.Service.Handler`
- `Bpmn.Activity.Task.Manual` — Pauses execution like User Task, type `:manual_task`
- `Bpmn.Activity.Task.Send` — Fire-and-forget; stores message metadata, releases token immediately
- `Bpmn.Activity.Task.Receive` — Pauses execution like User Task, type `:receive_task`

**Gateways:**
- `Bpmn.Gateway.Exclusive` — Evaluates conditions, routes to first match or default flow
- `Bpmn.Gateway.Parallel` — Fork: tokens to all outgoing; Join: waits for all incoming
- `Bpmn.Gateway.Inclusive` — Fork: tokens to all matching conditions; Join: waits for activated paths only

**Other:**
- `Bpmn.SequenceFlow` — Conditional expression evaluation
- `Bpmn.Activity.Subprocess.Embedded` — Executes nested elements within parent context

## Not Yet Implemented (Stubs)

The following modules are defined but return `{:not_implemented}`, awaiting the Phase 5 event bus or other prerequisites:

- `Bpmn.Event.Intermediate` — Intermediate throw/catch events
- `Bpmn.Event.Boundary` — Boundary events (parser support added)
- `Bpmn.Gateway.Exclusive.Event` — Event-based exclusive gateway
- `Bpmn.Gateway.Complex` — Complex gateway
- `Bpmn.Activity.Subprocess` — Call activity (needs process registry)
- `Bpmn.Process` — Process activation and token management

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines on extending the library.
