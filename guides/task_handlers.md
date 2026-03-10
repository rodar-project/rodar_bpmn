# Task Handlers

The `Bpmn.TaskHandler` behaviour lets you register custom task types or override specific task instances without modifying the engine.

## Defining a Handler

Implement the `Bpmn.TaskHandler` behaviour with a `token_in/2` callback:

```elixir
defmodule MyApp.ApprovalHandler do
  @behaviour Bpmn.TaskHandler

  @impl true
  def token_in({_type, %{id: id}} = _element, context) do
    # Your business logic here
    Bpmn.Context.put_data(context, "approved", true)
    Bpmn.release_token(["next_flow"], context)
  end
end
```

The callback receives the BPMN element tuple and the context pid, and should return a standard result tuple (`{:ok, context}`, `{:error, reason}`, `{:manual, data}`).

## Registering Handlers

### By Type (atom)

Register a handler for all tasks of a custom type:

```elixir
Bpmn.TaskRegistry.register(:my_approval_task, MyApp.ApprovalHandler)
```

Any element with type `:my_approval_task` will be dispatched to this handler.

### By Task ID (string)

Register a handler for a specific task instance:

```elixir
Bpmn.TaskRegistry.register("Task_approval_1", MyApp.ApprovalHandler)
```

### Lookup Priority

When dispatching, the engine checks:

1. **Task ID** (string) — specific override for one task instance
2. **Task type** (atom) — generic handler for all tasks of that type
3. **Built-in handlers** — the engine's default dispatch

This lets you override individual tasks while keeping a generic handler for the type.

## Managing Registrations

```elixir
# List all registered handlers
Bpmn.TaskRegistry.list()
# => [{:my_task, MyApp.Handler}, {"Task_1", MyApp.Other}]

# Remove a registration
Bpmn.TaskRegistry.unregister(:my_task)

# Check if a handler exists
case Bpmn.TaskRegistry.lookup(:my_task) do
  {:ok, module} -> # handler found
  :error -> # no handler registered
end
```

## Example: Custom HTTP Task

```elixir
defmodule MyApp.HttpTask do
  @behaviour Bpmn.TaskHandler

  @impl true
  def token_in({_type, %{id: _id, outgoing: outgoing} = attrs}, context) do
    url = Map.get(attrs, :url, Bpmn.Context.get_data(context, "request_url"))
    # Perform HTTP request...
    Bpmn.Context.put_data(context, "response", %{status: 200})
    Bpmn.release_token(outgoing, context)
  end
end

# Register for all :http_task elements
Bpmn.TaskRegistry.register(:http_task, MyApp.HttpTask)
```
