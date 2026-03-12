defmodule Mix.Tasks.RodarBpmn.Scaffold do
  @moduledoc """
  Generate handler modules for actionable tasks in a BPMN 2.0 file.

  Parses a BPMN file, identifies all service, user, send, receive, manual,
  and generic tasks, then generates handler module files with the correct
  behaviour and callback stubs.

  ## Usage

      mix rodar_bpmn.scaffold path/to/order.bpmn [options]

  ## Options

    * `--output-dir DIR` — Override default output directory
    * `--module-prefix PREFIX` — Override derived module prefix
    * `--dry-run` — Print generated code to stdout instead of writing files
    * `--force` — Overwrite existing files without prompting

  ## Defaults

    * Output dir: `lib/<app_name>/workflow/<bpmn_filename>/handlers/`
    * Module prefix: `<AppName>.Workflow.<BpmnFilename>.Handlers`
  """

  use Mix.Task

  alias RodarBpmn.Engine.Diagram
  alias RodarBpmn.Scaffold

  @shortdoc "Generate handler modules from a BPMN file"

  @switches [
    output_dir: :string,
    module_prefix: :string,
    dry_run: :boolean,
    force: :boolean
  ]

  @aliases [
    o: :output_dir,
    p: :module_prefix,
    d: :dry_run,
    f: :force
  ]

  @impl true
  def run(args) do
    case OptionParser.parse!(args, strict: @switches, aliases: @aliases) do
      {opts, [file_path]} ->
        scaffold(file_path, opts)

      _ ->
        Mix.shell().error(
          "Usage: mix rodar_bpmn.scaffold <file.bpmn> [--output-dir DIR] " <>
            "[--module-prefix PREFIX] [--dry-run] [--force]"
        )
    end
  end

  defp scaffold(file_path, opts) do
    diagram = file_path |> File.read!() |> Diagram.load()
    tasks = Scaffold.extract_tasks(diagram)

    if tasks == [] do
      Mix.shell().info("No actionable tasks found in #{file_path}")
      return_results([])
    else
      bpmn_name = bpmn_base_name(file_path)
      app_name = app_name()
      module_prefix = opts[:module_prefix] || default_module_prefix(app_name, bpmn_name)
      output_dir = opts[:output_dir] || default_output_dir(app_name, bpmn_name)
      dry_run? = Keyword.get(opts, :dry_run, false)
      force? = Keyword.get(opts, :force, false)

      results =
        Enum.map(tasks, fn task ->
          {module_name, file_name, content} = Scaffold.generate_module(task, module_prefix)
          target_path = Path.join(output_dir, file_name)

          result =
            write_or_report(target_path, content, module_name, module_prefix, dry_run?, force?)

          %{
            task: task,
            module_name: module_name,
            full_module: result_module_name(result, module_name, module_prefix),
            file_name: result_file_name(result, file_name),
            path: result_path(result, target_path),
            action: result.action
          }
        end)

      unless dry_run? do
        print_summary(results)
        print_registration(results)
      end

      return_results(results)
    end
  end

  defp write_or_report(target_path, content, module_name, module_prefix, true = _dry_run, _force) do
    Mix.shell().info("# #{target_path}")
    Mix.shell().info(String.trim(content))
    Mix.shell().info("")
    %{action: :dry_run, module_name: module_name, module_prefix: module_prefix}
  end

  defp write_or_report(target_path, content, module_name, module_prefix, _dry_run, force?) do
    if File.exists?(target_path) do
      handle_existing(target_path, content, module_name, module_prefix, force?)
    else
      write_file(target_path, content)
      %{action: :created, module_name: module_name, module_prefix: module_prefix}
    end
  end

  defp handle_existing(target_path, content, module_name, module_prefix, true = _force) do
    write_file(target_path, content)
    %{action: :overwritten, module_name: module_name, module_prefix: module_prefix}
  end

  defp handle_existing(target_path, content, module_name, module_prefix, _force) do
    existing = File.read!(target_path)

    if existing == content do
      %{action: :skipped, module_name: module_name, module_prefix: module_prefix}
    else
      print_diff(target_path, existing, content)
      prompt_conflict(target_path, content, module_name, module_prefix)
    end
  end

  defp print_diff(path, old, new) do
    Mix.shell().info("\nFile exists: #{path}\n")

    Scaffold.diff_contents(old, new)
    |> Enum.each(fn
      {:removed, line} -> Mix.shell().info("  - existing:  #{line}")
      {:added, line} -> Mix.shell().info("  + new:       #{line}")
    end)

    Mix.shell().info("")
  end

  defp prompt_conflict(target_path, content, module_name, module_prefix) do
    response =
      Mix.shell().prompt("  [O]verwrite / [K]eep both / [S]kip? (s)")
      |> String.trim()
      |> String.downcase()

    case response do
      "o" ->
        write_file(target_path, content)
        %{action: :overwritten, module_name: module_name, module_prefix: module_prefix}

      "k" ->
        new_module_name = module_name <> "New"
        new_file_name = Scaffold.file_name_from_module(new_module_name)
        new_path = Path.join(Path.dirname(target_path), new_file_name)
        new_full_module = "#{module_prefix}.#{new_module_name}"

        new_content = String.replace(content, "#{module_prefix}.#{module_name}", new_full_module)
        write_file(new_path, new_content)

        %{
          action: :kept_both,
          module_name: new_module_name,
          module_prefix: module_prefix,
          new_path: new_path,
          new_file_name: new_file_name
        }

      _ ->
        %{action: :skipped, module_name: module_name, module_prefix: module_prefix}
    end
  end

  defp write_file(path, content) do
    path |> Path.dirname() |> File.mkdir_p!()
    File.write!(path, content)
  end

  defp print_summary(results) do
    Mix.shell().info("")

    Enum.each(results, fn result ->
      label =
        case result.action do
          :created -> "Created:    "
          :overwritten -> "Overwritten:"
          :kept_both -> "Kept both:  "
          :skipped -> "Skipped:    "
          _ -> "            "
        end

      Mix.shell().info("#{label} #{result.path}")
    end)
  end

  defp print_registration(results) do
    active =
      Enum.filter(results, fn r -> r.action in [:created, :overwritten, :kept_both] end)

    if active == [] do
      :ok
    else
      {service_tasks, other_tasks} =
        Enum.split_with(active, fn r ->
          Scaffold.registration_type(r.task.bpmn_type) == :handler_map
        end)

      Mix.shell().info("")
      print_task_registry_instructions(other_tasks)
      print_handler_map_instructions(service_tasks, other_tasks)
    end
  end

  defp print_task_registry_instructions([]), do: :ok

  defp print_task_registry_instructions(tasks) do
    Mix.shell().info("# Register handlers in your application startup:")

    Enum.each(tasks, fn r ->
      Mix.shell().info(~s[RodarBpmn.TaskRegistry.register("#{r.task.id}", #{r.full_module})])
    end)
  end

  defp print_handler_map_instructions([], _other_tasks), do: :ok

  defp print_handler_map_instructions(service_tasks, other_tasks) do
    if other_tasks != [], do: Mix.shell().info("")
    Mix.shell().info("# Or use handler_map with Diagram.load/2:")
    Mix.shell().info("handler_map = %{")

    Enum.each(service_tasks, fn r ->
      Mix.shell().info(~s[  "#{r.task.id}" => #{r.full_module}])
    end)

    Mix.shell().info("}")
  end

  defp bpmn_base_name(file_path), do: Scaffold.bpmn_base_name(file_path)

  defp app_name do
    Mix.Project.config()[:app] |> Atom.to_string() |> Macro.camelize()
  end

  defp default_module_prefix(app_name, bpmn_name) do
    Scaffold.default_module_prefix(app_name, bpmn_name)
  end

  defp default_output_dir(app_name, bpmn_name) do
    snake_app = Macro.underscore(app_name)
    snake_bpmn = Macro.underscore(bpmn_name)
    namespace = Application.get_env(:rodar_bpmn, :scaffold_namespace, "Workflow")
    snake_namespace = Macro.underscore(namespace)
    Path.join(["lib", snake_app, snake_namespace, snake_bpmn, "handlers"])
  end

  defp result_module_name(%{action: :kept_both} = r, _module_name, _prefix) do
    "#{r.module_prefix}.#{r.module_name}"
  end

  defp result_module_name(_result, module_name, module_prefix) do
    "#{module_prefix}.#{module_name}"
  end

  defp result_file_name(%{action: :kept_both} = r, _file_name), do: r.new_file_name
  defp result_file_name(_result, file_name), do: file_name

  defp result_path(%{action: :kept_both} = r, _path), do: r.new_path
  defp result_path(_result, path), do: path

  # Returns results for testing; no-op at runtime
  defp return_results(results), do: results
end
