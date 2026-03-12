defmodule Mix.Tasks.Rodar.Run do
  @moduledoc """
  Execute a BPMN process from an XML file with step-by-step output.

  ## Usage

      mix rodar.run path/to/process.bpmn
      mix rodar.run path/to/process.bpmn --data '{"username": "alice"}'
      mix rodar.run path/to/process.bpmn --non-interactive

  Parses the BPMN file, analyzes the process for service tasks and data keys,
  registers passthrough handlers for unhandled service tasks, and drives
  execution directly with step-by-step output via hooks.

  ## Flags

  - `--data` — JSON string of initial process data
  - `--non-interactive` — skip user task prompts (for CI/testing)
  """

  use Mix.Task

  alias Mix.Tasks.Rodar.Run.Analyzer
  alias Mix.Tasks.Rodar.Run.PassthroughHandler
  alias Rodar.Activity.Task.User
  alias Rodar.Context
  alias Rodar.Engine.Diagram
  alias Rodar.Hooks
  alias Rodar.Scaffold.Discovery
  alias Rodar.TaskRegistry
  alias Rodar.Token

  @shortdoc "Execute a BPMN process from an XML file"

  @node_type_labels %{
    bpmn_event_start: "Start Event",
    bpmn_event_end: "End Event",
    bpmn_event_intermediate: "Intermediate Event",
    bpmn_event_intermediate_throw: "Intermediate Throw Event",
    bpmn_event_intermediate_catch: "Intermediate Catch Event",
    bpmn_event_boundary: "Boundary Event",
    bpmn_activity_task_user: "User Task",
    bpmn_activity_task_script: "Script Task",
    bpmn_activity_task_service: "Service Task",
    bpmn_activity_task_manual: "Manual Task",
    bpmn_activity_task_send: "Send Task",
    bpmn_activity_task_receive: "Receive Task",
    bpmn_activity_subprocess: "Subprocess",
    bpmn_activity_subprocess_embeded: "Embedded Subprocess",
    bpmn_gateway_exclusive: "Exclusive Gateway",
    bpmn_gateway_parallel: "Parallel Gateway",
    bpmn_gateway_inclusive: "Inclusive Gateway",
    bpmn_gateway_complex: "Complex Gateway",
    bpmn_gateway_exclusive_event: "Event-Based Gateway"
  }

  @impl true
  def run([file_path | rest]) do
    Mix.Task.run("app.start")

    {opts, init_data} = parse_args(rest)
    non_interactive = Keyword.get(opts, :non_interactive, false)

    diagram =
      file_path
      |> File.read!()
      |> Diagram.load(bpmn_file: file_path, app_name: app_name(), discover_handlers: true)

    case diagram.processes do
      [] ->
        Mix.shell().error("No processes found in #{file_path}")

      [{:bpmn_process, %{id: process_id} = attrs, elements} | _] ->
        name = Map.get(attrs, :name, process_id)
        process_map = build_process_map(elements)

        discovery = Map.get(diagram, :discovery)
        discovered_registry_ids = maybe_register_discovered(discovery)

        analysis = Analyzer.analyze(process_map)

        print_header(name, process_id, process_map, analysis, discovery)

        registered_ids = register_passthroughs(analysis.unhandled_service_tasks)
        passthrough_ids = MapSet.new(registered_ids)

        {:ok, context} = Context.start_supervised(process_map, init_data)

        Enum.each(init_data, fn {key, value} ->
          Context.put_data(context, key, value)
        end)

        register_hooks(context, passthrough_ids)

        start_event = find_start_event(process_map)

        if start_event do
          IO.puts("\n--- Execution ---\n")
          token = Token.new()
          result = Rodar.execute(start_event, context, token)

          result =
            maybe_interactive_loop(
              result,
              context,
              process_map,
              analysis,
              non_interactive
            )

          print_result(result, context)
          print_passthrough_tip(registered_ids, file_path)
        else
          Mix.shell().error("No start event found in process")
        end

        cleanup_passthroughs(registered_ids)
        cleanup_discovered_registry(discovered_registry_ids)
    end
  end

  def run(_) do
    Mix.shell().error("Usage: mix rodar.run <file.bpmn> [--data '{...}'] [--non-interactive]")
  end

  # --- Argument parsing ---

  defp parse_args(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        strict: [data: :string, non_interactive: :boolean],
        aliases: [d: :data]
      )

    init_data =
      case Keyword.get(opts, :data) do
        nil ->
          %{}

        json ->
          case Jason.decode(json) do
            {:ok, data} ->
              data

            {:error, _} ->
              Mix.shell().error("Invalid JSON in --data argument")
              %{}
          end
      end

    {opts, init_data}
  end

  # --- Process map building ---

  defp build_process_map(elements) when is_map(elements), do: elements

  defp build_process_map(elements) when is_list(elements) do
    Enum.reduce(elements, %{}, fn
      {_type, %{id: id}} = elem, acc -> Map.put(acc, id, elem)
      _, acc -> acc
    end)
  end

  defp find_start_event(process_map) do
    Enum.find_value(process_map, fn
      {_id, {:bpmn_event_start, _} = elem} -> elem
      _ -> nil
    end)
  end

  # --- Header output ---

  defp print_header(name, process_id, process_map, analysis, discovery) do
    IO.puts("\n=== #{name} (#{process_id}) ===\n")

    element_counts = count_elements(process_map)

    if element_counts != "" do
      IO.puts("  Elements: #{element_counts}")
    end

    if MapSet.size(analysis.data_keys) > 0 do
      keys = analysis.data_keys |> MapSet.to_list() |> Enum.sort() |> Enum.join(", ")
      IO.puts("  Data keys in conditions: #{keys}")
    end

    print_discovered_handlers(discovery)

    if analysis.unhandled_service_tasks != [] do
      IO.puts("  Service tasks without handlers (will pass through):")

      Enum.each(analysis.unhandled_service_tasks, fn {id, attrs} ->
        task_name = Map.get(attrs, :name, id)
        IO.puts("    - #{task_name} (#{id})")
      end)
    end
  end

  defp print_discovered_handlers(nil), do: :ok

  defp print_discovered_handlers(%{handler_map: hm, task_registry_entries: tre})
       when map_size(hm) == 0 and tre == [],
       do: :ok

  defp print_discovered_handlers(%{handler_map: hm, task_registry_entries: tre}) do
    all = Enum.map(hm, fn {id, mod} -> {id, mod} end) ++ tre

    IO.puts("  Discovered handlers:")

    Enum.each(all, fn {id, mod} ->
      IO.puts("    - #{id} → #{inspect(mod)}")
    end)
  end

  defp count_elements(process_map) do
    counts =
      process_map
      |> Enum.reject(fn {_id, {type, _}} -> type == :bpmn_sequence_flow end)
      |> Enum.group_by(fn {_id, {type, _}} -> element_category(type) end)
      |> Enum.map(fn {category, items} -> "#{length(items)} #{category}" end)
      |> Enum.sort()

    Enum.join(counts, ", ")
  end

  defp element_category(type) do
    cond do
      type in [
        :bpmn_event_start,
        :bpmn_event_end,
        :bpmn_event_intermediate,
        :bpmn_event_intermediate_throw,
        :bpmn_event_intermediate_catch,
        :bpmn_event_boundary
      ] ->
        "events"

      type in [
        :bpmn_activity_task_user,
        :bpmn_activity_task_script,
        :bpmn_activity_task_service,
        :bpmn_activity_task_manual,
        :bpmn_activity_task_send,
        :bpmn_activity_task_receive,
        :bpmn_activity_subprocess,
        :bpmn_activity_subprocess_embeded
      ] ->
        "tasks"

      type in [
        :bpmn_gateway_exclusive,
        :bpmn_gateway_parallel,
        :bpmn_gateway_inclusive,
        :bpmn_gateway_complex,
        :bpmn_gateway_exclusive_event
      ] ->
        "gateways"

      true ->
        "other"
    end
  end

  # --- Discovery helpers ---

  defp app_name do
    Mix.Project.config()[:app] |> Atom.to_string() |> Macro.camelize()
  end

  defp maybe_register_discovered(nil), do: []

  defp maybe_register_discovered(discovery) do
    Discovery.register_discovered(discovery)
  end

  defp cleanup_discovered_registry([]), do: :ok

  defp cleanup_discovered_registry(ids) do
    Enum.each(ids, &TaskRegistry.unregister/1)
  end

  # --- Passthrough handler registration ---

  defp register_passthroughs(unhandled_service_tasks) do
    Enum.flat_map(unhandled_service_tasks, fn {id, _attrs} ->
      case TaskRegistry.lookup(id) do
        {:ok, _} ->
          []

        :error ->
          TaskRegistry.register(id, PassthroughHandler)
          [id]
      end
    end)
  end

  defp cleanup_passthroughs(registered_ids) do
    Enum.each(registered_ids, &TaskRegistry.unregister/1)
  end

  # --- Hook registration ---

  defp register_hooks(context, passthrough_ids) do
    Hooks.register(context, :after_node, fn meta ->
      print_node_result(meta, context, passthrough_ids)
    end)
  end

  defp print_node_result(%{node_type: :bpmn_sequence_flow}, _context, _passthrough_ids), do: :ok

  defp print_node_result(meta, context, passthrough_ids) do
    label = Map.get(@node_type_labels, meta.node_type, to_string(meta.node_type))
    node_name = get_node_name(context, meta.node_id)
    token_released = node_released_token?(context, meta)

    is_passthrough =
      meta.node_type == :bpmn_activity_task_service and
        MapSet.member?(passthrough_ids, meta.node_id)

    cond do
      is_passthrough ->
        IO.puts("  [PASS] #{label}: #{node_name} (no handler)")

      token_released ->
        IO.puts("  [OK]   #{label}: #{node_name}")

      true ->
        print_node_status(label, node_name, meta.result)
    end

    :ok
  end

  defp print_node_status(label, node_name, {:manual, _}) do
    IO.puts("  [WAIT] #{label}: #{node_name}")
  end

  defp print_node_status(label, node_name, {:error, reason}) do
    IO.puts("  [ERR]  #{label}: #{node_name} — #{inspect(reason)}")
  end

  defp print_node_status(label, node_name, {:not_implemented}) do
    IO.puts("  [ERR]  #{label}: #{node_name} (not implemented)")
  end

  defp print_node_status(label, node_name, {:ok, _}) do
    IO.puts("  [OK]   #{label}: #{node_name}")
  end

  defp print_node_status(label, node_name, _other) do
    IO.puts("  [OK]   #{label}: #{node_name}")
  end

  defp node_released_token?(context, %{token: token}) when not is_nil(token) do
    Context.get_meta(context, {:_token_released, token.id}) == true
  end

  defp node_released_token?(_context, _meta), do: false

  defp get_node_name(context, node_id) do
    process_map = Context.get(context, :process)

    case Map.get(process_map, node_id) do
      {_type, %{name: name}} when is_binary(name) and name != "" -> name
      _ -> node_id
    end
  end

  # --- Interactive loop ---

  defp maybe_interactive_loop(result, context, process_map, analysis, non_interactive) do
    case result do
      {:manual, %{id: task_id, name: task_name, outgoing: _outgoing} = task_data} ->
        if non_interactive do
          IO.puts("\n  Process suspended at \"#{task_name || task_id}\" (non-interactive mode)")
          result
        else
          prompt_and_resume(task_id, task_name, task_data, context, process_map, analysis)
        end

      other ->
        other
    end
  end

  defp prompt_and_resume(task_id, task_name, task_data, context, process_map, analysis) do
    display_name = task_name || task_id

    IO.puts("\n  Waiting for input on \"#{display_name}\"")
    print_downstream_hints(process_map, task_id)

    input = Mix.shell().prompt("  Enter JSON data (or \"skip\" to end)")
    input = String.trim(input || "")

    case parse_user_input(input) do
      :skip ->
        IO.puts("  Skipped. Process remains suspended.")
        {:manual, task_data}

      {:ok, data} ->
        result = resume_user_task(task_id, task_data, display_name, context, process_map, data)
        maybe_interactive_loop(result, context, process_map, analysis, false)

      {:error, message} ->
        Mix.shell().error("  #{message}")
        prompt_and_resume(task_id, task_name, task_data, context, process_map, analysis)
    end
  end

  defp print_downstream_hints(process_map, task_id) do
    hints = Analyzer.downstream_data_hints(process_map, task_id)

    if MapSet.size(hints) > 0 do
      keys = hints |> MapSet.to_list() |> Enum.sort() |> Enum.join(", ")
      IO.puts("  Hint: downstream conditions reference: #{keys}")
    end
  end

  defp parse_user_input(input) when input in ["skip", ""], do: :skip

  defp parse_user_input(input) do
    case Jason.decode(input) do
      {:ok, data} when is_map(data) -> {:ok, data}
      {:ok, _} -> {:error, "Input must be a JSON object. Try again."}
      {:error, _} -> {:error, "Invalid JSON. Try again."}
    end
  end

  defp resume_user_task(task_id, task_data, display_name, context, process_map, data) do
    elem =
      Map.get(process_map, task_id) ||
        {:bpmn_activity_task_user, %{id: task_id, outgoing: task_data.outgoing}}

    result = User.resume(elem, context, data)
    IO.puts("  [OK]   User Task: #{display_name} (resumed)")
    result
  end

  # --- Result output ---

  defp print_result(result, context) do
    IO.puts("\n--- Result ---\n")

    case result do
      {:ok, _} ->
        data = Context.get(context, :data)
        IO.puts("  Status: completed")
        IO.puts("  Data: #{inspect(data)}")

      {:error, reason} ->
        IO.puts("  Status: error")
        IO.puts("  Error: #{inspect(reason)}")

      {:manual, %{name: name, id: id}} ->
        IO.puts("  Status: suspended")
        IO.puts("  Waiting at: #{name || id}")

      {:manual, _} ->
        IO.puts("  Status: suspended")

      {:not_implemented} ->
        IO.puts("  Status: error (not implemented)")

      other ->
        IO.puts("  Status: #{inspect(other)}")
    end
  end

  defp print_passthrough_tip([], _file_path), do: :ok

  defp print_passthrough_tip(registered_ids, file_path) do
    count = length(registered_ids)

    IO.puts(
      "\n  TIP: #{count} service task(s) used passthrough handlers." <>
        "\n  Generate real handlers with: mix rodar.scaffold #{file_path}"
    )
  end
end
