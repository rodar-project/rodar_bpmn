# Usage Rules for rodar_bpmn

> Elixir BPMN 2.0 execution engine. Parses BPMN 2.0 XML diagrams and executes
> processes using a token-based flow model.

## Understanding Rodar BPMN

Rodar BPMN is a token-based execution engine. BPMN XML is parsed into a process
map of `{:bpmn_type, %{attrs}}` tuples keyed by element ID. Tokens flow from
node to node; each handler module implements `token_in/2` and returns one of:

- `{:ok, context}` — node completed
- `{:error, message}` — execution error
- `{:manual, context}` — process paused (user task, receive task, manual task)
- `{:fatal, reason}` — unrecoverable error
- `{:not_implemented}` — no handler for this element

The **Context** is a GenServer (a PID), not a data structure. All state reads
and writes go through `RodarBpmn.Context` calls.

## Quick Start

```elixir
# GOOD: Standard workflow — parse, register, run
xml = File.read!("my_process.bpmn")
%{processes: [process | _]} = RodarBpmn.Engine.Diagram.load(xml)
{:bpmn_process, _attrs, _elements} = process
RodarBpmn.Registry.register("my_process", process)
{:ok, pid} = RodarBpmn.Process.create_and_run("my_process", %{order_id: "123"})

# BAD: Skipping registration — Process requires a registered definition
xml = File.read!("my_process.bpmn")
%{processes: [process | _]} = RodarBpmn.Engine.Diagram.load(xml)
# This will fail — "my_process" is not in the registry
{:ok, pid} = RodarBpmn.Process.create_and_run("my_process", %{})
```

## Process Lifecycle

Status transitions:

```
:created → :running → :completed
                    → :error
:running → :suspended → :running (resume)
any      → :terminated
```

```elixir
# GOOD: create_and_run handles start_link + activate in one step
{:ok, pid} = RodarBpmn.Process.create_and_run("my_process", %{key: "value"})
:completed = RodarBpmn.Process.status(pid)

# GOOD: Two-step when you need the pid before activation
{:ok, pid} = RodarBpmn.Process.start_link("my_process", %{})
:created = RodarBpmn.Process.status(pid)
:ok = RodarBpmn.Process.activate(pid)

# BAD: Calling activate on a non-:created process
{:ok, pid} = RodarBpmn.Process.create_and_run("my_process", %{})
# Already activated — this returns an error
{:error, _} = RodarBpmn.Process.activate(pid)

# BAD: Forgetting to activate after start_link
{:ok, pid} = RodarBpmn.Process.start_link("my_process", %{})
# Process is stuck in :created — nothing executes
```

## Context (State Management)

The context is a GenServer PID, not a value. Use `RodarBpmn.Context` functions
to read and write process data.

```elixir
# GOOD: Use Context API to read/write data
context = RodarBpmn.Process.get_context(pid)
RodarBpmn.Context.put_data(context, :status, "approved")
value = RodarBpmn.Context.get_data(context, :status)

# GOOD: Inside a service handler, data is passed as a map
def execute(attrs, data) do
  count = Map.get(data, :count, 0)
  {:ok, %{count: count + 1}}
end

# BAD: Treating context as a map — it's a PID
context = RodarBpmn.Process.get_context(pid)
# This will crash — context is a pid, not a map
context[:data]

# BAD: Trying to pattern-match on context
%{data: data} = context  # Crash — context is a pid
```

## Service Task Handlers

Service tasks use the `RodarBpmn.Activity.Task.Service.Handler` behaviour.
Handlers receive task attributes and current context data, and return a result
map that gets merged into context data.

```elixir
# GOOD: Implement the Handler behaviour
defmodule MyApp.CheckInventory do
  @behaviour RodarBpmn.Activity.Task.Service.Handler

  @impl true
  def execute(_attrs, data) do
    item_id = Map.get(data, :item_id)
    in_stock = Inventory.check(item_id)
    {:ok, %{in_stock: in_stock}}
  end
end
```

### Two ways to wire handlers

**Option 1: handler_map at parse time** — inject handler modules into the
parsed diagram. Best when you know the mapping upfront.

```elixir
# GOOD: Wire handlers at parse time via handler_map
handler_map = %{
  "Task_check_inventory" => MyApp.CheckInventory,
  "Task_charge_payment" => MyApp.ChargePayment
}

%{processes: [process | _]} = RodarBpmn.Engine.Diagram.load(xml, handler_map: handler_map)
RodarBpmn.Registry.register("order_process", process)
```

**Option 2: TaskRegistry at runtime** — register handlers dynamically. Best
for plugins or when task IDs aren't known at compile time.

```elixir
# GOOD: Register handler at runtime by task ID
RodarBpmn.TaskRegistry.register("Task_check_inventory", MyApp.CheckInventory)
```

**Lookup priority**: inline `:handler` attribute (from handler_map) → TaskRegistry by task ID → `{:not_implemented}`.

```elixir
# BAD: Using TaskHandler behaviour for service tasks
defmodule MyApp.CheckInventory do
  # Wrong behaviour — TaskHandler is for custom element types
  @behaviour RodarBpmn.TaskHandler

  @impl true
  def token_in(elem, context) do
    # ...
  end
end

# BAD: Forgetting to wire the handler — returns {:not_implemented}
# No handler_map, no TaskRegistry entry — this service task does nothing
RodarBpmn.Registry.register("order_process", process)
{:ok, pid} = RodarBpmn.Process.create_and_run("order_process", %{})
```

## Custom Task Handlers

For custom element types (not service tasks), use the `RodarBpmn.TaskHandler`
behaviour. These handle the raw token flow.

```elixir
# GOOD: Custom task handler for a non-standard element type
defmodule MyApp.ApprovalHandler do
  @behaviour RodarBpmn.TaskHandler

  @impl true
  def token_in({_type, %{id: id, outgoing: outgoing}} = _element, context) do
    RodarBpmn.Context.put_data(context, "approved_by", id)
    RodarBpmn.release_token(outgoing, context)
  end
end

# Register by custom type atom or by specific task ID
RodarBpmn.TaskRegistry.register(:my_custom_task, MyApp.ApprovalHandler)
RodarBpmn.TaskRegistry.register("Task_approval_1", MyApp.ApprovalHandler)

# BAD: Forgetting to release the token — process stalls
defmodule MyApp.BadHandler do
  @behaviour RodarBpmn.TaskHandler

  @impl true
  def token_in(_element, context) do
    RodarBpmn.Context.put_data(context, "key", "value")
    # Missing release_token — execution stops here
    {:ok, context}
  end
end
```

## Manual Tasks & Resuming

User tasks, manual tasks, and receive tasks return `{:manual, context}`,
suspending the process. You must explicitly resume execution.

```elixir
# GOOD: Handle :manual result and resume later
{:ok, pid} = RodarBpmn.Process.create_and_run("approval_process", %{})
:suspended = RodarBpmn.Process.status(pid)

# Later, when the user completes the task:
context = RodarBpmn.Process.get_context(pid)
RodarBpmn.Context.put_data(context, :approved, true)

# Resume by releasing the token to the outgoing flow
RodarBpmn.release_token(outgoing_flow_ids, context)

# BAD: Calling Process.resume/1 to continue from a manual task
# resume/1 only changes status from :suspended to :running
# It does NOT re-execute or release the token
RodarBpmn.Process.resume(pid)  # Status changes but nothing executes
```

## Event Bus

The event bus supports message, signal, and escalation events with different
delivery semantics.

```elixir
# GOOD: Message events are point-to-point (one subscriber receives)
RodarBpmn.Event.Bus.subscribe(:message, "order_received", %{
  context: context,
  node_id: "catch_1",
  outgoing: ["flow_out"]
})
RodarBpmn.Event.Bus.publish(:message, "order_received", %{order_id: "123"})

# GOOD: Signal events broadcast to all subscribers
RodarBpmn.Event.Bus.subscribe(:signal, "system_shutdown", %{context: ctx1})
RodarBpmn.Event.Bus.subscribe(:signal, "system_shutdown", %{context: ctx2})
# Both subscribers receive this
RodarBpmn.Event.Bus.publish(:signal, "system_shutdown", %{})

# GOOD: Use correlation keys to route messages to specific instances
RodarBpmn.Event.Bus.subscribe(:message, "payment_received", %{
  context: context,
  correlation: %{key: "order_id", value: "ORD-123"}
})
RodarBpmn.Event.Bus.publish(:message, "payment_received", %{
  correlation: %{key: "order_id", value: "ORD-123"}
})

# BAD: Using :message when you want broadcast — only one subscriber gets it
RodarBpmn.Event.Bus.publish(:message, "notify_all", %{})
# Use :signal for broadcast instead

# BAD: Mismatching correlation keys — message won't route correctly
RodarBpmn.Event.Bus.subscribe(:message, "payment", %{
  correlation: %{key: "order_id", value: "ORD-123"}
})
RodarBpmn.Event.Bus.publish(:message, "payment", %{
  correlation: %{key: "payment_id", value: "PAY-456"}  # Wrong key!
})
```

## Expressions

BPMN condition expressions support two languages: FEEL and Elixir. They have
different binding conventions.

```elixir
# GOOD: FEEL expressions receive data directly — write naturally
# If context data is %{count: 10, status: "active"}
# In BPMN XML: <conditionExpression language="feel">count > 5</conditionExpression>

# GOOD: Elixir expressions access data through the "data" binding
# In BPMN XML: <conditionExpression language="elixir">data["count"] > 5</conditionExpression>

# BAD: Using Elixir syntax in a FEEL expression
# language="feel": data["count"] > 5  — FEEL doesn't have data["..."] syntax

# BAD: Using FEEL syntax in an Elixir expression
# language="elixir": count > 5  — "count" is not bound; use data["count"]
```

## Persistence

Persistence requires explicit configuration. Without it, dehydrate/rehydrate
won't work.

```elixir
# GOOD: Configure persistence in your app config
# config/config.exs
config :rodar_bpmn, :persistence,
  adapter: RodarBpmn.Persistence.Adapter.ETS,
  auto_dehydrate: true

# GOOD: Manual dehydrate and rehydrate
{:ok, instance_id} = RodarBpmn.Process.dehydrate(pid)
# Later...
{:ok, new_pid} = RodarBpmn.Process.rehydrate(instance_id)

# GOOD: auto_dehydrate saves automatically when process hits {:manual, _}
# Just configure auto_dehydrate: true and it happens on suspend

# BAD: Assuming persistence works without configuration
# No persistence config → adapter defaults but ETS adapter must be in supervision tree
{:ok, instance_id} = RodarBpmn.Process.dehydrate(pid)  # May fail

# BAD: Expecting auto-dehydrate on {:ok, _} — it only fires on {:manual, _}
# Completed processes are NOT auto-dehydrated
```

## Validation

Validation is opt-in. You can validate explicitly or enable it as a gate
before process activation.

```elixir
# GOOD: Explicit validation before registration
%{processes: [{:bpmn_process, _attrs, elements} | _]} = RodarBpmn.Engine.Diagram.load(xml)
process_map = Map.new(elements, fn {_type, %{id: id}} = elem -> {id, elem} end)
{:ok, _} = RodarBpmn.Validation.validate(process_map)

# GOOD: Enable validation gate on activate
# config/config.exs
config :rodar_bpmn, :validate_on_activate, true
# Now Process.activate/1 validates before running

# BAD: Passing the raw Diagram.load/1 result to validate/1
# validate/1 expects a process_map (%{id => element}), not the diagram struct
diagram = RodarBpmn.Engine.Diagram.load(xml)
RodarBpmn.Validation.validate(diagram)  # Wrong shape!
```

## Version Management

The registry supports versioned process definitions for safe updates.

```elixir
# GOOD: Register multiple versions, look up specific ones
RodarBpmn.Registry.register("my_process", process_v1)  # version 1
RodarBpmn.Registry.register("my_process", process_v2)  # version 2

{:ok, latest} = RodarBpmn.Registry.lookup("my_process")       # v2
{:ok, v1} = RodarBpmn.Registry.lookup("my_process", 1)        # v1

# GOOD: Migrate running instances to a new version
:ok = RodarBpmn.Migration.migrate(process_pid, 2)

# BAD: Assuming register/2 replaces — it creates a new version
RodarBpmn.Registry.register("my_process", process_v1)
RodarBpmn.Registry.register("my_process", process_v2)
# Both versions exist; lookup/1 returns v2, but v1 is still accessible
```

## Common Patterns

```elixir
# GOOD: Full end-to-end pattern
xml = File.read!("order_process.bpmn")

diagram = RodarBpmn.Engine.Diagram.load(xml,
  handler_map: %{
    "Task_validate" => MyApp.ValidateOrder,
    "Task_charge" => MyApp.ChargePayment
  }
)

[process | _] = diagram.processes
RodarBpmn.Registry.register("order_process", process)
{:ok, pid} = RodarBpmn.Process.create_and_run("order_process", %{order_id: "123"})

case RodarBpmn.Process.status(pid) do
  :completed -> :done
  :suspended -> :waiting_for_manual_task
  :error -> :handle_error
end
```

## Lanes (Role/Group Assignment)

Lanes are structural metadata that assign flow nodes to roles, groups, or
departments. They do not affect execution — the engine treats them as read-only
annotations stored in the process attrs (`:lane_set` key).

```elixir
# GOOD: Query lane assignment for a node (e.g., route a manual task)
%{processes: [process | _]} = RodarBpmn.Engine.Diagram.load(xml)
{:bpmn_process, attrs, _elements} = process

# Find which lane a specific node belongs to
{:ok, lane} = RodarBpmn.Lane.find_lane_for_node(attrs.lane_set, "UserTask_1")
lane.name  # => "HR Department"

# Build a lookup map for all nodes
node_map = RodarBpmn.Lane.node_lane_map(attrs.lane_set)
node_map["UserTask_1"].name  # => "HR Department"

# Get a flat list of all lanes (including nested)
all = RodarBpmn.Lane.all_lanes(attrs.lane_set)

# Validate lane refs against the process
{:ok, _} = RodarBpmn.Validation.validate_lanes(attrs.lane_set, elements)

# BAD: Trying to access lane_set from the elements map
# Lane set is in the process *attrs*, not in the elements map
elements["LaneSet_1"]  # => nil — lanes are not elements

# BAD: Assuming lane_set is always present
# lane_set is nil when the BPMN has no lanes
attrs.lane_set.lanes  # => KeyError if no lanes in the process

# GOOD: Handle nil gracefully (all Lane functions accept nil)
RodarBpmn.Lane.find_lane_for_node(nil, "task1")  # => :error
RodarBpmn.Lane.node_lane_map(nil)                 # => %{}
RodarBpmn.Lane.all_lanes(nil)                      # => []
```
