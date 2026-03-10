# Process Lifecycle

`RodarBpmn.Process` manages the full lifecycle of a BPMN process instance as a GenServer, from creation through completion or termination.

## Creating Instances

Register a process definition, then create and run an instance:

```elixir
diagram = RodarBpmn.Engine.Diagram.load(File.read!("order.bpmn"))
process = hd(diagram.processes)

RodarBpmn.Registry.register("order-process", process)
{:ok, pid} = RodarBpmn.Process.create_and_run("order-process", %{"customer" => "alice"})
```

`create_and_run/2` starts the instance under `RodarBpmn.ProcessSupervisor` and activates it immediately. For more control, use `start_link/2` and `activate/1` separately:

```elixir
{:ok, pid} = RodarBpmn.Process.start_link("order-process", %{"customer" => "alice"})
:ok = RodarBpmn.Process.activate(pid)
```

## Status Transitions

Process instances move through these states:

```
:created --> :running --> :completed
                     --> :error
:running --> :suspended --> :running (resume)
any      --> :terminated
```

Query the current status at any time:

```elixir
RodarBpmn.Process.status(pid)
# => :running
```

## Suspend and Resume

Suspend a running instance to pause execution, then resume later:

```elixir
:ok = RodarBpmn.Process.suspend(pid)
RodarBpmn.Process.status(pid)
# => :suspended

:ok = RodarBpmn.Process.resume(pid)
RodarBpmn.Process.status(pid)
# => :running
```

Suspension is useful for manual intervention, debugging, or migration between definition versions.

## Dehydration and Rehydration

Dehydration serializes a process instance to persistent storage so it can be restored later. This is essential for long-running processes that survive restarts.

```elixir
{:ok, instance_id} = RodarBpmn.Process.dehydrate(pid)

# Later, restore the instance from storage
{:ok, new_pid} = RodarBpmn.Process.rehydrate(instance_id)
```

### Auto-Dehydrate

When a process reaches a manual wait state (user task, receive task), it can automatically dehydrate. Enable this in your config:

```elixir
config :rodar_bpmn, :persistence,
  adapter: RodarBpmn.Persistence.Adapter.ETS,
  auto_dehydrate: true
```

With auto-dehydrate enabled, any `{:manual, _}` result triggers automatic serialization.

## Subprocesses

### Embedded Subprocesses

Embedded subprocesses execute inline within the parent process, sharing the same context. They support boundary events for error handling and interruption.

### Call Activities

Call activities reference an external process definition registered in `RodarBpmn.Registry`. The engine creates a child context, executes the called process, and merges results back into the parent.

## Accessing Context

Retrieve the context pid from a running process to inspect or modify data:

```elixir
context = RodarBpmn.Process.get_context(pid)
RodarBpmn.Context.get_data(context, "result")
```

## Next Steps

- [Events](events.md) -- Event types, the event bus, timers, and boundary events
- [Persistence](persistence.md) -- Storage adapters and serialization details
- [Versioning](versioning.md) -- Process definition versioning and migration
