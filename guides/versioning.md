# Versioning and Migration

The engine supports multiple versions of process definitions and safe migration of running instances between versions.

## Registering Versioned Definitions

Each call to `register/2` auto-increments the version number. Use `register/3` to get the assigned version back:

```elixir
{:ok, v1} = RodarBpmn.Registry.register("order-process", definition_v1, [])
# => {:ok, 1}

{:ok, v2} = RodarBpmn.Registry.register("order-process", definition_v2, [])
# => {:ok, 2}
```

You can also assign an explicit version:

```elixir
{:ok, 5} = RodarBpmn.Registry.register("order-process", definition, version: 5)
```

## Looking Up Definitions

`lookup/1` returns the latest version. `lookup/2` fetches a specific version:

```elixir
{:ok, latest_def} = RodarBpmn.Registry.lookup("order-process")
{:ok, v1_def} = RodarBpmn.Registry.lookup("order-process", 1)
```

## Listing and Inspecting Versions

```elixir
RodarBpmn.Registry.versions("order-process")
# => [%{version: 1, deprecated: false}, %{version: 2, deprecated: false}]

RodarBpmn.Registry.latest_version("order-process")
# => {:ok, 2}
```

## Deprecating Versions

Mark a version as deprecated to flag it as no longer recommended. Running instances on deprecated versions continue to work:

```elixir
:ok = RodarBpmn.Registry.deprecate("order-process", 1)

RodarBpmn.Registry.versions("order-process")
# => [%{version: 1, deprecated: true}, %{version: 2, deprecated: false}]
```

## Compatibility Checks

Before migrating a running instance, check whether its active node positions exist in the target version:

```elixir
case RodarBpmn.Migration.check_compatibility(instance_pid, 2) do
  :compatible ->
    IO.puts("Safe to migrate")

  {:incompatible, issues} ->
    Enum.each(issues, fn issue ->
      IO.puts("Issue: #{issue.type} at node #{issue.node_id}")
    end)
end
```

The compatibility check verifies:

- All active nodes exist in the target definition
- Outgoing flows from active nodes are present
- Gateway token state references valid nodes

## Migrating Instances

`migrate/2` suspends the instance (if running), swaps the process definition, updates the version tracker, and resumes:

```elixir
:ok = RodarBpmn.Migration.migrate(instance_pid, 2)
```

To skip compatibility checks when you know the migration is safe:

```elixir
:ok = RodarBpmn.Migration.migrate(instance_pid, 2, force: true)
```

## Querying by Version

Use `RodarBpmn.Observability.instances_by_version/2` to find instances running on a specific version:

```elixir
RodarBpmn.Observability.instances_by_version("order-process", 1)
# => [%{pid: #PID<...>, instance_id: "abc", status: :running, ...}]
```

## Next Steps

- [Process Lifecycle](https://hexdocs.pm/rodar_bpmn/process_lifecycle.html) -- Process states and lifecycle management
- [Persistence](persistence.md) -- Saving and restoring process snapshots
- [Observability](observability.md) -- Monitoring instances and health checks
