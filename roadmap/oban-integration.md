# Oban Integration — Durable Timers & Retryable Tasks

**Package**: `rodar_bpmn_oban`
**Namespace**: `RodarBpmn.Oban.*`

## Why Oban First

Oban solves the single biggest production gap in the core engine: **ephemeral timers**. Today, all timers use `Process.send_after`, which means:

- A 24-hour timer vanishes if the node restarts
- Timer cycle counters (`R3/PT10S`) are lost on crash
- Service tasks that call external systems have no retry mechanism
- There's no way to inspect or manage pending timers

Oban fixes all of this with just Ecto + Postgres — no framework commitment required. It's the lightest path to production-grade durability.

## Value Matrix

| Capability | Current (Core) | Oban-Enhanced |
|-----------|----------------|---------------|
| Timer events | `Process.send_after` (in-memory) | Persisted to Postgres, survives restarts |
| Timer cycles | In-memory counter | Persistent, resumable across crashes |
| Scheduled start events | Only while node is up | Cron-like, always fires |
| Service task retry | None (BPMN error boundary only) | Configurable backoff before error path |
| Task visibility | None | Queryable, cancellable, pausable |
| Dead letter handling | Silent failure | Oban dead jobs, inspectable |

## Core Change Required

**One additive change**: Extract `Bpmn.Event.Timer.Scheduler` behaviour from `lib/bpmn/event/timer.ex`.

This is the same change referenced across the roadmap, but Oban is the **primary consumer** — it doesn't need Ash to provide durable timers.

### Behaviour Definition (in core)

```elixir
defmodule Bpmn.Event.Timer.Scheduler do
  @moduledoc """
  Behaviour for timer scheduling backends.
  Default uses Process.send_after (in-memory).
  """

  @callback schedule(pid(), term(), non_neg_integer()) :: reference() | term()
  @callback schedule_cycle(pid(), term(), non_neg_integer(), pos_integer() | :infinity) :: reference() | term()
  @callback cancel(reference() | term()) :: :ok
end

defmodule Bpmn.Event.Timer.Scheduler.Default do
  @behaviour Bpmn.Event.Timer.Scheduler

  @impl true
  def schedule(pid, message, delay_ms) do
    Process.send_after(pid, message, delay_ms)
  end

  @impl true
  def schedule_cycle(pid, message, interval_ms, remaining) do
    Process.send_after(pid, {:timer_cycle_fire, message, interval_ms, remaining}, interval_ms)
  end

  @impl true
  def cancel(ref) when is_reference(ref) do
    Process.cancel_timer(ref)
    :ok
  end
end
```

Configuration (existing pattern, same as persistence adapter):

```elixir
# Default (unchanged behavior):
config :bpmn, :timer_scheduler, Bpmn.Event.Timer.Scheduler.Default

# With Oban:
config :bpmn, :timer_scheduler, RodarBpmn.Oban.Scheduler
```

## Phase 1 — Durable Timer Scheduler

### Oban Worker

```elixir
defmodule RodarBpmn.Oban.TimerWorker do
  use Oban.Worker,
    queue: :bpmn_timers,
    max_attempts: 3

  @impl true
  def perform(%Oban.Job{args: %{"type" => "timer_fired"} = args}) do
    context_pid = find_context(args["process_id"])
    node_id = args["node_id"]
    outgoing = args["outgoing"]

    send(context_pid, {:timer_fired, node_id, outgoing})
    :ok
  end

  def perform(%Oban.Job{args: %{"type" => "timer_cycle_fired"} = args}) do
    context_pid = find_context(args["process_id"])
    message = deserialize_message(args["message"])
    interval_ms = args["interval_ms"]
    remaining = args["remaining"]

    send(context_pid, {:timer_cycle_fired, message, interval_ms, remaining})
    :ok
  end

  defp find_context(process_id) do
    # Look up the context PID via ProcessRegistry
    [{pid, _}] = Registry.lookup(Bpmn.ProcessRegistry, process_id)
    pid
  end
end
```

### Scheduler Implementation

```elixir
defmodule RodarBpmn.Oban.Scheduler do
  @behaviour Bpmn.Event.Timer.Scheduler

  @impl true
  def schedule(pid, message, delay_ms) do
    {process_id, node_id, outgoing} = parse_timer_message(message)

    %{
      type: "timer_fired",
      process_id: process_id,
      node_id: node_id,
      outgoing: outgoing
    }
    |> RodarBpmn.Oban.TimerWorker.new(scheduled_at: seconds_from_now(delay_ms))
    |> Oban.insert!()
  end

  @impl true
  def schedule_cycle(pid, message, interval_ms, remaining) do
    %{
      type: "timer_cycle_fired",
      message: serialize_message(message),
      interval_ms: interval_ms,
      remaining: remaining
    }
    |> RodarBpmn.Oban.TimerWorker.new(scheduled_at: seconds_from_now(interval_ms))
    |> Oban.insert!()
  end

  @impl true
  def cancel(job_id) when is_integer(job_id) do
    Oban.cancel_job(job_id)
    :ok
  end

  defp seconds_from_now(ms) do
    DateTime.add(DateTime.utc_now(), ms, :millisecond)
  end
end
```

### What This Gives You

- Timers persist across node restarts — a 24-hour timer just works
- Failed timer deliveries retry with backoff (process might be rehydrating)
- Timer jobs are queryable: `Oban.Job |> where(queue: "bpmn_timers") |> Repo.all()`
- Cancellation is durable — cancelled timers stay cancelled
- Cycle timers resume from where they left off

## Phase 1.5 — Retryable Service Tasks

Beyond timers, Oban can wrap service/send task execution for durability:

### Async Task Worker

```elixir
defmodule RodarBpmn.Oban.TaskWorker do
  use Oban.Worker,
    queue: :bpmn_tasks,
    max_attempts: 5,
    backoff: :exponential

  @impl true
  def perform(%Oban.Job{args: args}) do
    handler = String.to_existing_atom(args["handler"])
    element = deserialize(args["element"])
    context_pid = find_context(args["process_id"])

    case handler.token_in(element, context_pid) do
      {:ok, _context} -> :ok
      {:error, reason} -> {:error, reason}  # triggers Oban retry
    end
  end
end
```

### TaskHandler Wrapper

```elixir
defmodule RodarBpmn.Oban.TaskHandler do
  @behaviour Bpmn.TaskHandler

  @impl true
  def token_in(element, context) do
    # Enqueue as Oban job instead of executing synchronously
    %{
      handler: get_attr(element, "oban:handler"),
      element: serialize(element),
      process_id: get_process_id(context)
    }
    |> RodarBpmn.Oban.TaskWorker.new()
    |> Oban.insert!()

    # Return {:manual, _} — process waits until Oban job completes and resumes
    {:manual, context}
  end
end
```

This means any existing `TaskHandler` can be wrapped in Oban for retry and durability — including the MCP client and Jido handlers from later phases.

## Relationship to Other Packages

### Oban vs AshOban

| Aspect | `rodar_bpmn_oban` | AshOban (via `rodar_bpmn_ash`) |
|--------|-------------------|-------------------------------|
| Dependencies | Oban + Ecto + Postgrex | Full Ash stack + AshOban |
| Setup | Add Oban to supervision tree | Ash resource definitions |
| Timer scheduling | Direct Oban worker | AshOban triggers on resource changes |
| Best for | Standalone durable timers | Already using Ash for everything |

**They don't conflict.** If you later adopt `rodar_bpmn_ash`, the Ash package can use the same Oban instance under the hood. The `Timer.Scheduler` behaviour means only one implementation is active at a time.

### Enables Other Packages

```
rodar_bpmn_oban (Phase 1)
    │
    ├── rodar_bpmn_mcp (Phase 3) — MCP client tasks wrapped in Oban for retry
    ├── rodar_bpmn_jido (Phase 4) — AI agent tasks wrapped in Oban for retry
    └── rodar_bpmn_ash (Phase 2+) — can share the Oban/Ecto infrastructure
```

## Configuration

```elixir
# config/config.exs
config :rodar_bpmn_oban, Oban,
  repo: MyApp.Repo,
  queues: [
    bpmn_timers: 10,
    bpmn_tasks: 5
  ]

# Swap the timer scheduler
config :bpmn, :timer_scheduler, RodarBpmn.Oban.Scheduler
```

## Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Process PID lookup after restart | Timer fires but context PID changed | Look up via ProcessRegistry; rehydrate if needed |
| Oban job serialization | Must serialize BEAM terms to JSON | Use `:erlang.term_to_binary` + Base64 for complex terms |
| Timer precision | Oban polls (default 1s), not instant | Acceptable for BPMN timers (seconds-to-days); configure poll interval for tighter needs |
| Ecto/Postgres required | Infrastructure dependency | Only for this package — core remains infrastructure-free |

## Dependencies

```elixir
# mix.exs for rodar_bpmn_oban
defp deps do
  [
    {:bpmn, "~> 0.1"},         # core engine
    {:oban, "~> 2.18"},        # job processing
    {:ecto_sql, "~> 3.10"},    # database layer
    {:postgrex, "~> 0.17"}     # Postgres driver
  ]
end
```

## Testing

```elixir
# Use Oban's testing mode
config :rodar_bpmn_oban, Oban, testing: :inline

# Timer tests verify job insertion
test "schedule/3 inserts an Oban job" do
  RodarBpmn.Oban.Scheduler.schedule(self(), {:timer_fired, "node1", ["flow1"]}, 60_000)

  assert_enqueued worker: RodarBpmn.Oban.TimerWorker,
    args: %{"type" => "timer_fired", "node_id" => "node1"}
end

# Integration tests verify end-to-end timer flow
test "timer fires after Oban processes the job" do
  # ... start process with timer event ...
  assert_receive {:timer_fired, "timer_node", _}, 5_000
end
```
