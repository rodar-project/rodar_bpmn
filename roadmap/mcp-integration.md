# MCP Integration (Bidirectional)

**Package**: `rodar_bpmn_mcp`
**Namespace**: `RodarBpmn.MCP.*`

## Two Complementary Roles

MCP (Model Context Protocol) integration is **bidirectional**:

1. **MCP Server** — Expose BPMN operations as tools that any agent can call
2. **MCP Client** — BPMN tasks call external MCP tools during workflow execution

```
┌─────────────┐     MCP Protocol     ┌──────────────┐     MCP Protocol     ┌─────────────┐
│  AI Agents  │ ──────────────────→  │  RodarBPMN   │ ──────────────────→  │  External   │
│  (Claude,   │    MCP Server        │    Core       │    MCP Client        │  MCP Tools  │
│   GPT, etc) │ ←──────────────────  │              │ ←──────────────────  │  (DB, Slack, │
└─────────────┘                      └──────────────┘                      │   Email...) │
                                                                           └─────────────┘
```

Both roles ship in a single package. The server makes BPMN orchestratable by agents; the client makes any MCP tool usable as a BPMN service task.

---

## MCP Server — Expose Workflows to Agents

### Value Proposition

Any MCP-compatible agent can orchestrate business processes without framework-specific code. Deploy a workflow, start instances, monitor progress, complete tasks — all through standard MCP tool calls.

### Tools Exposed

Each tool wraps an existing public API — no new core functionality needed:

| MCP Tool | Core API | Description |
|----------|----------|-------------|
| `bpmn.deploy` | `Bpmn.Engine.Diagram.load/1` + `Bpmn.Registry.register/2` | Register a process definition from XML |
| `bpmn.start` | `Bpmn.Process.create_and_run/2` | Start a new process instance with initial data |
| `bpmn.status` | `Bpmn.Process.status/1` | Query instance status and current state |
| `bpmn.complete_task` | Resume from `{:manual, _}` | Complete a waiting user/manual task |
| `bpmn.list_instances` | `Bpmn.Observability.running_instances/0` + `waiting_instances/0` | List all running and waiting instances |
| `bpmn.history` | `Bpmn.Context.get_history/1` | Get execution history for an instance |
| `bpmn.suspend` | `Bpmn.Process.suspend/1` | Pause a running instance |
| `bpmn.resume` | `Bpmn.Process.resume/1` | Resume a suspended instance |
| `bpmn.terminate` | `Bpmn.Process.terminate/1` | Terminate an instance |
| `bpmn.inspect` | `Bpmn.Engine.Diagram.load/1` | Parse and describe BPMN diagram structure |

### Resources Exposed (Read-Only Context)

MCP resources provide agents with contextual information:

- **Process definitions** — XML source and parsed structure for registered definitions
- **Instance state** — Current data, tokens, and execution position for running instances

### Implementation

Built on the [`mcp`](https://hex.pm/packages/mcp) Elixir MCP SDK:

```elixir
defmodule RodarBpmn.MCP.Server do
  use MCP.Server

  # Tool definitions
  tool "bpmn.deploy",
    description: "Deploy a BPMN 2.0 process definition",
    input_schema: %{
      type: "object",
      properties: %{
        xml: %{type: "string", description: "BPMN 2.0 XML content"},
        name: %{type: "string", description: "Process definition name"}
      },
      required: ["xml", "name"]
    }

  tool "bpmn.start",
    description: "Start a new process instance",
    input_schema: %{
      type: "object",
      properties: %{
        definition_id: %{type: "string", description: "Registered process definition ID"},
        data: %{type: "object", description: "Initial process data"}
      },
      required: ["definition_id"]
    }

  tool "bpmn.status",
    description: "Get the current status of a process instance",
    input_schema: %{
      type: "object",
      properties: %{
        instance_id: %{type: "string", description: "Process instance ID"}
      },
      required: ["instance_id"]
    }

  tool "bpmn.complete_task",
    description: "Complete a waiting user or manual task",
    input_schema: %{
      type: "object",
      properties: %{
        instance_id: %{type: "string", description: "Process instance ID"},
        task_id: %{type: "string", description: "Task node ID"},
        data: %{type: "object", description: "Task completion data"}
      },
      required: ["instance_id", "task_id"]
    }

  # ... additional tools follow the same pattern

  @impl true
  def handle_tool("bpmn.deploy", %{"xml" => xml, "name" => name}) do
    with {:ok, process_map} <- Bpmn.Engine.Diagram.load(xml) do
      Bpmn.Registry.register(name, process_map)
      {:ok, %{definition_id: name, elements: map_size(process_map)}}
    end
  end

  @impl true
  def handle_tool("bpmn.start", %{"definition_id" => id} = params) do
    data = Map.get(params, "data", %{})
    case Bpmn.Process.create_and_run(id, data) do
      {:ok, pid} ->
        {:ok, %{instance_id: inspect(pid), status: "started"}}
      error ->
        {:error, inspect(error)}
    end
  end

  # ... handlers for each tool
end
```

### Agent Interaction Example

A Claude agent orchestrating an order approval workflow:

```
Agent: Call bpmn.deploy with the order-approval.bpmn XML
Agent: Call bpmn.start with definition_id "order-approval", data: {amount: 5000, requester: "alice"}
Agent: Call bpmn.status to check — sees task "manager_review" is waiting
Agent: Call bpmn.complete_task with task_id "manager_review", data: {approved: true}
Agent: Call bpmn.history to verify the process completed successfully
```

---

## MCP Client — BPMN Tasks Call External Tools

### Value Proposition

**Any MCP-connected tool becomes a BPMN service task.** A workflow can call database queries, send emails, post to Slack, invoke AI agents — anything available as an MCP tool — without custom handler code.

### TaskHandler Implementation

A new `TaskHandler` that connects to external MCP servers:

```elixir
defmodule RodarBpmn.MCP.TaskHandler do
  @behaviour Bpmn.TaskHandler

  @impl true
  def token_in(element, context) do
    # Extract MCP config from BPMN element extension attributes
    server_url = get_attr(element, "mcp:server")
    tool_name = get_attr(element, "mcp:tool")
    input_mapping = get_attr(element, "mcp:input")

    # Build tool input from process context data
    input = build_input(input_mapping, context)

    # Connect to external MCP server and call the tool
    with {:ok, client} <- MCP.Client.connect(server_url),
         {:ok, result} <- MCP.Client.call_tool(client, tool_name, input) do
      # Map result back to process data
      context = Bpmn.Context.put_data(context, :task_result, result)
      {:ok, context}
    else
      {:error, reason} -> {:error, "MCP tool call failed: #{inspect(reason)}"}
    end
  end

  defp get_attr(element, key) do
    get_in(element, [:attrs, key])
  end

  defp build_input(mapping, context) do
    # Map process data fields to tool input parameters
    # mapping is a JSON string like {"query": "data.sql_query"}
    mapping
    |> Jason.decode!()
    |> Enum.map(fn {k, path} -> {k, resolve_path(path, context)} end)
    |> Map.new()
  end
end
```

### Registration

Register via the existing `Bpmn.TaskRegistry`:

```elixir
# Register the MCP handler for service tasks marked with mcp: attributes
Bpmn.TaskRegistry.register(:mcp_service, RodarBpmn.MCP.TaskHandler)

# Or register for a specific task ID
Bpmn.TaskRegistry.register("call-database", RodarBpmn.MCP.TaskHandler)
```

### BPMN Extension Attributes

Service tasks specify their MCP target using extension attributes in the BPMN XML:

```xml
<bpmn:serviceTask id="query_database" name="Query Customer Data">
  <bpmn:extensionElements>
    <mcp:toolCall
      server="stdio:///path/to/db-mcp-server"
      tool="query"
      input='{"sql": "data.sql_query"}'
      output="query_result" />
  </bpmn:extensionElements>
</bpmn:serviceTask>
```

### Use Cases

| BPMN Service Task | MCP Server | Tool Called |
|-------------------|------------|------------|
| Query customer data | Database MCP | `query` |
| Send notification | Slack MCP | `send_message` |
| Generate report | AI agent MCP | `generate_report` |
| Send email | Email MCP | `send_email` |
| Create ticket | Jira MCP | `create_issue` |
| Fetch weather | Weather MCP | `get_forecast` |

**This makes BPMN a universal orchestrator** — any tool in the growing MCP ecosystem becomes available as a service task without writing custom handler code.

---

## Combined Server + Client

The most powerful pattern combines both directions. An AI agent orchestrates a workflow (via MCP server), and that workflow calls other tools (via MCP client):

```
Claude Agent
    │
    ├── bpmn.deploy (MCP server tool)
    ├── bpmn.start  (MCP server tool)
    │       │
    │       ├── [BPMN: query_database task] → Database MCP (MCP client call)
    │       ├── [BPMN: analyze_data task]   → AI Agent MCP (MCP client call)
    │       ├── [BPMN: send_notification]   → Slack MCP (MCP client call)
    │       └── [BPMN: manager_review]      → waiting...
    │
    ├── bpmn.status → "waiting on manager_review"
    ├── bpmn.complete_task
    └── bpmn.history → full execution trace
```

## Core Changes: None

- MCP server wraps existing public APIs
- MCP client implements existing `Bpmn.TaskHandler` behaviour
- Registration uses existing `Bpmn.TaskRegistry`
- No modifications to core modules

## Dependencies

```elixir
# mix.exs for rodar_bpmn_mcp
defp deps do
  [
    {:bpmn, "~> 0.1"},     # core engine
    {:mcp, "~> 1.0"},      # Elixir MCP SDK (server + client)
    {:jason, "~> 1.4"}     # JSON encoding for tool I/O
  ]
end
```
