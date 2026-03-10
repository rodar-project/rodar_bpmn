# Persistence

The persistence layer lets you save and restore running process instances across restarts. It uses a behaviour-based adapter pattern so you can plug in any storage backend.

## Configuration

Configure the persistence adapter and auto-dehydrate setting in your application config:

```elixir
config :rodar_bpmn, :persistence,
  adapter: RodarBpmn.Persistence.Adapter.ETS,
  auto_dehydrate: true
```

When `auto_dehydrate` is `true`, process instances automatically save their state whenever they reach a `{:manual, _}` result (e.g., a user task or receive task waiting for external input).

## Dehydration and Rehydration

Dehydration captures a full snapshot of a running process. Rehydration restores it.

```elixir
# Save a running process
{:ok, snapshot} = RodarBpmn.Process.dehydrate(process_pid)

# Later, restore it
{:ok, restored_pid} = RodarBpmn.Process.rehydrate(snapshot)
RodarBpmn.Process.status(restored_pid)
# => :suspended
```

Rehydrated processes resume in `:suspended` status. Call `RodarBpmn.Process.resume/1` to continue execution.

## Snapshot Contents

The `RodarBpmn.Persistence.Serializer` handles converting live process state to a persistable format:

- **Token structs** are converted to plain maps (and reconstructed on deserialization)
- **MapSets** (e.g., gateway token tracking) become sorted lists
- **Timer refs** are stripped (timers are not portable across restarts)
- **PIDs** in node metadata are removed

Binary serialization uses `:erlang.term_to_binary/1` with `:safe` deserialization to prevent atom creation from untrusted data.

## Writing a Custom Adapter

Implement the `RodarBpmn.Persistence` behaviour with four callbacks:

```elixir
defmodule MyApp.PostgresPersistence do
  @behaviour RodarBpmn.Persistence

  @impl true
  def save(instance_id, snapshot) do
    binary = RodarBpmn.Persistence.Serializer.serialize(snapshot)
    # Store binary in your database
    :ok
  end

  @impl true
  def load(instance_id) do
    # Fetch binary from your database
    case fetch_from_db(instance_id) do
      {:ok, binary} -> {:ok, RodarBpmn.Persistence.Serializer.deserialize(binary)}
      nil -> {:error, :not_found}
    end
  end

  @impl true
  def delete(instance_id) do
    # Remove from your database
    :ok
  end

  @impl true
  def list do
    # Return all stored instance IDs
    ["instance-1", "instance-2"]
  end
end
```

Then configure your adapter:

```elixir
config :rodar_bpmn, :persistence, adapter: MyApp.PostgresPersistence
```

## ETS Adapter

The built-in `RodarBpmn.Persistence.Adapter.ETS` stores snapshots in a named ETS table (`:rodar_bpmn_persistence`). It is started automatically by the supervision tree when persistence is configured. Suitable for development and testing -- data is lost on application restart.

## Next Steps

- [Process Lifecycle](https://hexdocs.pm/rodar_bpmn/process_lifecycle.html) -- Process states, suspension, and termination
- [Versioning and Migration](versioning.md) -- Versioned definitions and instance migration
