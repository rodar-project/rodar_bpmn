# Jido Framework Integration

**Package**: `rodar_bpmn_jido`
**Namespace**: `RodarBpmn.Jido.*`

## Value Matrix

| Capability | Current (Core) | Jido-Enhanced |
|-----------|----------------|---------------|
| Task execution | Static handlers (`TaskHandler` behaviour) | AI agents with reasoning strategies |
| Expressions | FEEL + sandboxed Elixir | AI-augmented decision making |
| Service tasks | Synchronous function calls | Autonomous agent execution |
| Event handling | Pattern-matched callbacks | Signal-driven agent reactions |
| Subprocess delegation | Call activity (static) | Agent hierarchy orchestration |
| Error handling | Fixed error paths | Adaptive recovery strategies |

## Jido's Architecture

### Signal Dispatch Adapters

Jido provides 9 built-in signal dispatch adapters:

| Adapter | Transport | Use Case |
|---------|-----------|----------|
| `:pid` | Direct process message | In-process agent communication |
| `:named` | Named BEAM process | Cross-process, same node |
| `:pubsub` | Phoenix.PubSub | Distributed, multi-node |
| `:http` | Outbound HTTP | External service integration |
| `:webhook` | HTTP + HMAC signing | Secure external callbacks |
| `:logger` | Logger output | Observability, debugging |
| `:console` | IO output | Development, demos |
| `:noop` | Discard | Testing |
| `:bus` | Event bus (pending) | Stream processing |

Custom adapters implement the `Jido.Signal.Dispatch.Adapter` behaviour.

### Reasoning Strategies

Jido agents support 8 reasoning strategies:

1. **ReAct** — Reason + Act iteratively
2. **Chain of Thought (CoT)** — Step-by-step reasoning
3. **Tree of Thought (ToT)** — Explore multiple paths
4. **Plan and Execute** — Plan first, then execute
5. **Reflexion** — Self-critique and retry
6. **Tool Use** — Select and use tools
7. **Monte Carlo Tree Search** — Probabilistic exploration
8. **Custom** — User-defined strategies

### MCP Compatibility

The `jido_mcp` package already exists — Jido agents can be exposed as MCP servers. This means a BPMN workflow can reach Jido agents through either:

- **Direct path**: `rodar_bpmn_jido` (in-process, low latency)
- **MCP path**: `rodar_bpmn_mcp` → `jido_mcp` (protocol-level, framework-agnostic)

---

## Phase 4 — AI TaskHandlers

### Implementation

A `TaskHandler` that wraps Jido agents:

```elixir
defmodule RodarBpmn.Jido.TaskHandler do
  @behaviour Bpmn.TaskHandler

  @impl true
  def token_in(element, context) do
    # Extract agent config from BPMN element attributes
    agent_module = get_agent_module(element)
    strategy = get_strategy(element)  # :react, :chain_of_thought, etc.
    instructions = get_instructions(element)

    # Build agent input from process context
    input = build_agent_input(element, context)

    # Execute the Jido agent
    case run_agent(agent_module, strategy, instructions, input) do
      {:ok, result} ->
        # Map agent results back to process data
        context = map_result_to_context(result, element, context)
        {:ok, context}

      {:error, reason} ->
        {:error, "Agent execution failed: #{inspect(reason)}"}
    end
  end

  defp run_agent(agent_module, strategy, instructions, input) do
    agent_module
    |> Jido.Agent.new(instructions: instructions)
    |> Jido.Agent.run(input, strategy: strategy)
  end

  defp get_agent_module(element) do
    element
    |> get_in([:attrs, "jido:agent"])
    |> String.to_existing_atom()
  end

  defp get_strategy(element) do
    case get_in(element, [:attrs, "jido:strategy"]) do
      nil -> :react  # default
      strategy -> String.to_existing_atom(strategy)
    end
  end
end
```

### Registration

Register via the existing `Bpmn.TaskRegistry`:

```elixir
# Register for all AI-typed tasks
Bpmn.TaskRegistry.register(:ai_task, RodarBpmn.Jido.TaskHandler)

# Or register specific agents for specific task IDs
Bpmn.TaskRegistry.register("analyze-sentiment", RodarBpmn.Jido.SentimentAgent)
Bpmn.TaskRegistry.register("generate-summary", RodarBpmn.Jido.SummaryAgent)
```

### BPMN Extension Attributes

```xml
<bpmn:serviceTask id="analyze_feedback" name="Analyze Customer Feedback">
  <bpmn:extensionElements>
    <jido:agent
      module="MyApp.Agents.FeedbackAnalyzer"
      strategy="chain_of_thought"
      instructions="Analyze the customer feedback and classify sentiment"
      input="data.feedback_text"
      output="analysis_result" />
  </bpmn:extensionElements>
</bpmn:serviceTask>
```

### Agent Composition in Workflows

BPMN's flow control naturally orchestrates multi-agent pipelines:

```
[Start] → [Extract Data Agent] → [Parallel Gateway] → [Sentiment Agent]    → [Join] → [Decision Agent] → [End]
                                                     → [Summarize Agent]    →
                                                     → [Categorize Agent]   →
```

Each task is an independent Jido agent. BPMN handles sequencing, parallelism, error boundaries, and conditional routing — the agents focus purely on their domain logic.

---

## Phase 5 — Signal Bridge & Agent Subprocesses

### Bidirectional Signal Bridge

Bridge between `Bpmn.Event.Bus` and `Jido.Signal`:

```elixir
defmodule RodarBpmn.Jido.SignalBridge do
  @moduledoc """
  Bidirectional bridge between BPMN event bus and Jido signal system.
  """

  # BPMN → Jido: Forward BPMN events as Jido signals
  def forward_to_jido(context, event_type, opts \\ []) do
    Bpmn.Event.Bus.subscribe(context, event_type, fn event ->
      signal = to_jido_signal(event)
      Jido.Signal.dispatch(signal, opts[:adapter] || :pubsub)
    end)
  end

  # Jido → BPMN: Forward Jido signals as BPMN events
  def forward_to_bpmn(signal_pattern, context, event_type) do
    Jido.Signal.subscribe(signal_pattern, fn signal ->
      event = to_bpmn_event(signal)
      Bpmn.Event.Bus.publish(context, event_type, event)
    end)
  end

  defp to_jido_signal(%{type: type, name: name, data: data}) do
    %Jido.Signal{
      type: "bpmn.#{type}.#{name}",
      data: data,
      source: "rodar_bpmn"
    }
  end

  defp to_bpmn_event(%Jido.Signal{type: type, data: data}) do
    %{type: parse_bpmn_type(type), data: data}
  end
end
```

### Agent Subprocesses

Map BPMN subprocesses to Jido agent hierarchies:

```elixir
defmodule RodarBpmn.Jido.AgentSubprocess do
  @moduledoc """
  Maps BPMN embedded subprocesses to Jido agent hierarchies.
  The subprocess becomes a supervisor agent that coordinates child agents.
  """

  def execute(subprocess_element, context) do
    # Create a supervisor agent for the subprocess
    supervisor = Jido.Agent.Supervisor.new(
      agents: extract_child_agents(subprocess_element),
      strategy: :sequential  # or :parallel based on BPMN structure
    )

    case Jido.Agent.Supervisor.run(supervisor, context_to_input(context)) do
      {:ok, results} -> {:ok, merge_results(results, context)}
      {:error, reason} -> {:error, reason}
    end
  end
end
```

### Hooks Integration

Use existing `Bpmn.Hooks` for Jido observability:

```elixir
# Register hooks that notify Jido about BPMN execution events
Bpmn.Hooks.register(context, :before_node, fn event ->
  RodarBpmn.Jido.SignalBridge.emit_signal("bpmn.node.entering", event)
end)

Bpmn.Hooks.register(context, :on_error, fn event ->
  RodarBpmn.Jido.SignalBridge.emit_signal("bpmn.node.error", event)
end)
```

---

## MCP vs Direct Jido — When to Use Which

| Aspect | MCP Path (`rodar_bpmn_mcp` → `jido_mcp`) | Direct Path (`rodar_bpmn_jido`) |
|--------|-------------------------------------------|----------------------------------|
| Latency | Higher (HTTP/stdio protocol overhead) | Lower (in-process BEAM calls) |
| Coupling | Loose (protocol-level) | Tighter (library dependency) |
| Reach | Any MCP-compatible agent/tool | Jido agents only |
| Features | Standard MCP tool calling | Signal bridge, agent hierarchies, strategy selection |
| Deployment | Cross-process, cross-machine | Same BEAM node |
| Best for | General tool calling, external services | Performance-critical AI tasks, complex agent orchestration |

**Both paths can coexist.** Use direct Jido for compute-intensive AI tasks that benefit from low latency and rich agent features. Use MCP for general-purpose tool calling and cross-system integration.

## Jido-Ash Synergy

Jido has first-class Ash integration, enabling three-way data flow:

```
BPMN Process ←→ Jido Agent ←→ Ash Resources
     ↕                              ↕
  Event Bus                    Postgres DB
```

- Jido agents can read/write Ash resources directly
- BPMN process data syncs to Ash via hooks (Phase 2)
- Agent decisions are auditable through AshPaperTrail (Phase 5)

## Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| LLM latency | Slow workflow execution | Async task execution with `{:manual, _}` + callback on completion |
| Non-deterministic decisions | Unpredictable process paths | Logging all agent decisions; BPMN error boundaries for fallback paths |
| API stability (Jido v2.0.0) | Breaking changes | Pin version range; adapter pattern isolates core from Jido internals |
| Cost (LLM API calls) | Expensive workflows | Budget limits in agent config; caching for repeated queries |
| Token limits | Large context overflow | Summarization agents; chunked processing in subworkflows |

## Core Changes: None

- AI handlers implement existing `Bpmn.TaskHandler` behaviour
- Registration uses existing `Bpmn.TaskRegistry`
- Signal bridge uses existing `Bpmn.Event.Bus` subscribe/publish
- Hooks integration uses existing `Bpmn.Hooks` system

## Dependencies

```elixir
# mix.exs for rodar_bpmn_jido
defp deps do
  [
    {:bpmn, "~> 0.1"},       # core engine
    {:jido, "~> 2.0"},       # Jido framework
    {:jido_ai, "~> 0.5"},    # AI agent capabilities
  ]
end
```
