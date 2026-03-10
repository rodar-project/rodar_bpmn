defmodule Mix.Tasks.Bpmn.Inspect do
  @moduledoc """
  Print the parsed structure of a BPMN 2.0 XML file.

  ## Usage

      mix bpmn.inspect path/to/process.bpmn

  Lists all processes with element counts grouped by type,
  and shows collaboration info if present.
  """

  use Mix.Task

  alias Bpmn.Engine.Diagram

  @shortdoc "Print the parsed structure of a BPMN file"

  @impl true
  def run([file_path]) do
    diagram = file_path |> File.read!() |> Diagram.load()

    Mix.shell().info("BPMN Diagram: #{diagram.id}")
    Mix.shell().info("")

    Enum.each(diagram.processes, &print_process/1)

    print_collaboration(diagram.collaboration)
  end

  def run(_) do
    Mix.shell().error("Usage: mix bpmn.inspect <file.bpmn>")
  end

  defp print_process({:bpmn_process, %{id: id} = attrs, elements}) do
    name = Map.get(attrs, :name, id)
    Mix.shell().info("Process: #{name} (#{id})")
    Mix.shell().info("  Elements: #{map_size(elements)}")

    elements
    |> Enum.group_by(fn {_id, {type, _attrs}} -> type end)
    |> Enum.sort_by(fn {type, _} -> Atom.to_string(type) end)
    |> Enum.each(&print_type_group/1)

    Mix.shell().info("")
  end

  defp print_type_group({type, elems}) do
    ids = Enum.map_join(elems, ", ", fn {id, _} -> id end)
    Mix.shell().info("    #{type} (#{length(elems)}): #{ids}")
  end

  defp print_collaboration(nil), do: :ok

  defp print_collaboration(collab) do
    Mix.shell().info("Collaboration: #{collab.id}")

    Mix.shell().info("  Participants: #{Enum.map_join(collab.participants, ", ", & &1.name)}")

    Mix.shell().info("  Message Flows: #{length(collab.message_flows)}")
  end
end
