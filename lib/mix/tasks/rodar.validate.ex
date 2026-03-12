defmodule Mix.Tasks.Rodar.Validate do
  @moduledoc """
  Validate a BPMN 2.0 XML file for structural issues.

  ## Usage

      mix bpmn.validate path/to/process.bpmn

  Loads and parses the file, then runs structural validation on each process.
  If a collaboration element is present, collaboration constraints are also checked.

  Exit code 1 on errors, 0 on clean or warnings-only.
  """

  use Mix.Task

  alias Rodar.Engine.Diagram
  alias Rodar.Validation

  @shortdoc "Validate a BPMN 2.0 XML file"

  @impl true
  def run([file_path]) do
    diagram = file_path |> File.read!() |> Diagram.load()

    has_errors =
      diagram.processes
      |> Enum.reduce(false, fn {:bpmn_process, %{id: id}, elements}, has_errors ->
        case Validation.validate(elements) do
          {:ok, _} ->
            Mix.shell().info("Process #{id}: OK")
            has_errors

          {:error, issues} ->
            Mix.shell().error("Process #{id}: #{length(issues)} issue(s)")
            Enum.each(issues, &print_issue/1)
            has_errors || Enum.any?(issues, &(&1.severity == :error))
        end
      end)

    has_errors = validate_collaboration(diagram, has_errors)

    if has_errors do
      Mix.raise("Validation failed")
    end
  end

  def run(_) do
    Mix.shell().error("Usage: mix bpmn.validate <file.bpmn>")
  end

  defp validate_collaboration(%{collaboration: nil}, has_errors), do: has_errors

  defp validate_collaboration(%{collaboration: collab, processes: processes}, has_errors) do
    case Validation.validate_collaboration(collab, processes) do
      {:ok, _} ->
        Mix.shell().info("Collaboration #{collab.id}: OK")
        has_errors

      {:error, issues} ->
        Mix.shell().error("Collaboration #{collab.id}: #{length(issues)} issue(s)")
        Enum.each(issues, &print_issue/1)
        has_errors || Enum.any?(issues, &(&1.severity == :error))
    end
  end

  defp print_issue(issue) do
    node = if issue[:node_id], do: " [#{issue.node_id}]", else: ""
    Mix.shell().info("  #{issue.severity}: #{issue.rule}#{node} — #{issue.message}")
  end
end
