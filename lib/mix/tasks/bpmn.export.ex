defmodule Mix.Tasks.Bpmn.Export do
  @moduledoc """
  Export a BPMN 2.0 XML file from its parsed representation.

  ## Usage

      mix bpmn.export path/to/process.bpmn
      mix bpmn.export path/to/process.bpmn --output output.bpmn

  Parses the input file and re-exports it as normalized BPMN 2.0 XML.
  Prints to stdout by default, or writes to a file with `--output`.
  """

  use Mix.Task

  alias Bpmn.Engine.Diagram

  @shortdoc "Export a BPMN file as normalized BPMN 2.0 XML"

  @impl true
  def run(args) do
    {opts, args} = OptionParser.parse!(args, strict: [output: :string])

    case args do
      [file_path] ->
        xml = file_path |> File.read!() |> Diagram.load() |> Diagram.export()

        case opts[:output] do
          nil ->
            Mix.shell().info(xml)

          output_path ->
            File.write!(output_path, xml)
            Mix.shell().info("Exported to #{output_path}")
        end

      _ ->
        Mix.shell().error("Usage: mix bpmn.export <file.bpmn> [--output output.bpmn]")
    end
  end
end
