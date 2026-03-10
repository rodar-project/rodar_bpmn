# Ash Framework Integration

**Package**: `rodar_bpmn_ash`
**Namespace**: `RodarBpmn.Ash.*`

## Value Matrix

| Capability | Current (Core) | Ash-Enhanced |
|-----------|----------------|--------------|
| Persistence | ETS adapter (dev/test only) | AshPostgres (production Postgres) |
| APIs | None (Elixir-only) | Auto-generated GraphQL + REST |
| Process lifecycle | GenServer state machine | AshStateMachine (declarative) |
| Audit trail | Telemetry events (ephemeral) | AshPaperTrail (persistent history) |
| Authorization | None | Ash policies (role-based) |
| Data layer | In-memory context | Postgres-backed resources |

> **Note**: Durable timers are handled by [`rodar_bpmn_oban`](oban-integration.md) (Phase 1), which shares the same Ecto/Postgres infrastructure. Ash builds on top of that foundation.

## Phase 2a — Postgres Persistence

**Goal**: Production-ready persistence with zero core changes. Builds on the Ecto/Postgres infrastructure already established by `rodar_bpmn_oban` (Phase 1).

### Implementation

Implement the existing `Bpmn.Persistence` behaviour using an AshPostgres resource:

```elixir
# The behaviour already exists in the core:
# lib/bpmn/persistence.ex
#   save/2, load/1, delete/1, list/0

defmodule RodarBpmn.Ash.Persistence do
  @behaviour Bpmn.Persistence

  @impl true
  def save(id, snapshot), do: ...

  @impl true
  def load(id), do: ...

  @impl true
  def delete(id), do: ...

  @impl true
  def list(), do: ...
end
```

### Ash Resource

```elixir
defmodule RodarBpmn.Ash.ProcessSnapshot do
  use Ash.Resource,
    domain: RodarBpmn.Ash.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "bpmn_process_snapshots"
    repo MyApp.Repo
  end

  attributes do
    uuid_primary_key :id
    attribute :process_id, :string, allow_nil?: false
    attribute :definition_id, :string
    attribute :state, :atom  # :active, :suspended, :completed, :terminated
    attribute :snapshot_data, :binary  # erlang term_to_binary output
    attribute :metadata, :map
    timestamps()
  end

  actions do
    defaults [:read, :destroy]
    create :save do ... end
    read :by_process_id do ... end
  end
end
```

### Configuration

Swap from ETS to Postgres with a config change:

```elixir
# Before (dev/test):
config :bpmn, :persistence,
  adapter: Bpmn.Persistence.Adapter.ETS

# After (production):
config :bpmn, :persistence,
  adapter: RodarBpmn.Ash.Persistence
```

### Core Changes: None

The `Bpmn.Persistence` behaviour and `Bpmn.Persistence.Serializer` handle all serialization. The Ash adapter simply stores and retrieves the binary snapshots.

## Phase 2b — Ash Resources & APIs

**Goal**: Structured resources with auto-generated APIs and declarative state machines.

### Three Resources

#### ProcessDefinition

Stores registered BPMN process definitions (XML + parsed structure):

```elixir
defmodule RodarBpmn.Ash.ProcessDefinition do
  use Ash.Resource, ...

  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false
    attribute :version, :integer, default: 1
    attribute :xml_source, :string  # original BPMN XML
    attribute :parsed_structure, :map  # JSON-safe parsed map
    attribute :is_active, :boolean, default: true
    timestamps()
  end

  actions do
    create :deploy do ... end  # validates XML, parses, registers in Bpmn.Registry
    update :activate do ... end
    update :deactivate do ... end
  end
end
```

#### ProcessInstance

Tracks running process instances with AshStateMachine for lifecycle:

```elixir
defmodule RodarBpmn.Ash.ProcessInstance do
  use Ash.Resource, ...
  use AshStateMachine

  state_machine do
    initial_states [:created]
    default_initial_state :created

    transitions do
      transition :activate, from: :created, to: :active
      transition :suspend, from: :active, to: :suspended
      transition :resume, from: :suspended, to: :active
      transition :complete, from: :active, to: :completed
      transition :terminate, from: [:active, :suspended], to: :terminated
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :definition_id, :uuid
    attribute :state, :atom
    attribute :data, :map  # current process data
    attribute :started_at, :utc_datetime
    attribute :completed_at, :utc_datetime
  end
end
```

#### TaskInstance

Tracks user/manual tasks awaiting completion:

```elixir
defmodule RodarBpmn.Ash.TaskInstance do
  use Ash.Resource, ...

  attributes do
    uuid_primary_key :id
    attribute :instance_id, :uuid  # belongs_to ProcessInstance
    attribute :node_id, :string
    attribute :task_type, :atom
    attribute :state, :atom  # :waiting, :completed, :cancelled
    attribute :input_data, :map
    attribute :output_data, :map
    attribute :assigned_to, :string
    timestamps()
  end
end
```

### Hooks-Based DB Sync

Use the existing `Bpmn.Hooks` system to keep Ash resources in sync with the GenServer runtime:

```elixir
# Register hooks when a process starts
Bpmn.Hooks.register(context, :after_node, fn event ->
  RodarBpmn.Ash.Sync.record_node_completion(event)
end)

Bpmn.Hooks.register(context, :on_complete, fn event ->
  RodarBpmn.Ash.Sync.mark_instance_completed(event)
end)
```

### Auto-Generated APIs

```elixir
defmodule RodarBpmn.Ash.Api.GraphQL do
  use AshGraphql, domain: RodarBpmn.Ash.Domain

  queries do
    list :list_instances, RodarBpmn.Ash.ProcessInstance
    get :get_instance, RodarBpmn.Ash.ProcessInstance
    list :list_tasks, RodarBpmn.Ash.TaskInstance
  end

  mutations do
    create :deploy_process, RodarBpmn.Ash.ProcessDefinition, :deploy
    update :complete_task, RodarBpmn.Ash.TaskInstance, :complete
  end
end

defmodule RodarBpmn.Ash.Api.JsonApi do
  use AshJsonApi, domain: RodarBpmn.Ash.Domain
  # REST endpoints auto-generated from resource actions
end
```

### Core Changes: None

All sync happens through Hooks (observational-only, already exists).

## Phase 5 — Audit & Authorization

> **Note**: Durable timers are provided by [`rodar_bpmn_oban`](oban-integration.md) (Phase 1). The `Timer.Scheduler` behaviour extraction happens there. If you're already using Oban for timers, AshOban can optionally manage the same Oban instance through Ash resource triggers — but this is not required.

### Audit Trail via AshPaperTrail

```elixir
defmodule RodarBpmn.Ash.ProcessInstance do
  use AshPaperTrail

  paper_trail do
    on_actions [:activate, :suspend, :resume, :complete, :terminate]
    store_action_name? true
    change_tracking_mode :changes_only
  end
end
```

### Authorization Policies

```elixir
policies do
  policy action(:deploy) do
    authorize_if actor_attribute_equals(:role, :admin)
  end

  policy action(:complete_task) do
    authorize_if relates_to_actor_via([:assigned_to])
  end
end
```

## Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| GenServer/DB state divergence | Data inconsistency | Hooks fire synchronously before token release; periodic reconciliation job |
| Ash version coupling | Breaking upgrades | Pin Ash version range in mix.exs; CI matrix testing |
| Opaque binary serialization | Can't query snapshot internals | Phase 2 resources store structured data alongside snapshots |
| Migration complexity | Upgrade friction | Ash generators for migrations; version-stamped snapshots |

## Dependencies

```elixir
# mix.exs for rodar_bpmn_ash
defp deps do
  [
    {:bpmn, "~> 0.1"},              # core engine
    {:ash, "~> 3.0"},               # framework
    {:ash_postgres, "~> 2.0"},      # data layer
    {:ash_state_machine, "~> 0.2"}, # Phase 2b
    {:ash_graphql, "~> 1.0"},       # Phase 2b (optional)
    {:ash_json_api, "~> 1.0"},      # Phase 2b (optional)
    {:ash_paper_trail, "~> 0.3"}    # Phase 5
  ]
end
```
