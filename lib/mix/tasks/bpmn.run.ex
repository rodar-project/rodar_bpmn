defmodule Mix.Tasks.Bpmn.Run do
  @moduledoc """
  Execute a BPMN process from an XML file.

  ## Usage

      mix bpmn.run path/to/process.bpmn
      mix bpmn.run path/to/process.bpmn --data '{"username": "alice"}'

  Starts the application, registers the first process found in the file,
  creates an instance, and runs it. Prints the final status and context data.
  """

  use Mix.Task

  alias Bpmn.Context
  alias Bpmn.Engine.Diagram
  alias Bpmn.Process, as: BpmnProcess
  alias Bpmn.Registry

  @shortdoc "Execute a BPMN process from an XML file"

  @impl true
  def run([file_path | rest]) do
    Mix.Task.run("app.start")

    init_data = parse_data(rest)
    diagram = file_path |> File.read!() |> Diagram.load()

    case diagram.processes do
      [] ->
        Mix.shell().error("No processes found in #{file_path}")

      [{:bpmn_process, %{id: process_id} = attrs, _elements} = process | _] ->
        name = Map.get(attrs, :name, process_id)
        Mix.shell().info("Running process: #{name} (#{process_id})")
        Registry.register(process_id, process)

        case BpmnProcess.create_and_run(process_id, init_data) do
          {:ok, pid} ->
            print_result(pid)

          {:error, reason} ->
            Mix.shell().error("Error: #{inspect(reason)}")
        end
    end
  end

  def run(_) do
    Mix.shell().error("Usage: mix bpmn.run <file.bpmn> [--data '{...}']")
  end

  defp parse_data(args) do
    case OptionParser.parse(args, strict: [data: :string]) do
      {[data: json], _, _} ->
        case Jason.decode(json) do
          {:ok, data} ->
            data

          {:error, _} ->
            Mix.shell().error("Invalid JSON in --data argument")
            %{}
        end

      _ ->
        %{}
    end
  end

  defp print_result(pid) do
    status = BpmnProcess.status(pid)
    Mix.shell().info("Status: #{status}")

    case status do
      :completed ->
        context = BpmnProcess.get_context(pid)
        data = Context.get(context, :data)
        Mix.shell().info("Data: #{inspect(data)}")

      :suspended ->
        Mix.shell().info("Process is waiting for manual input")

      other ->
        Mix.shell().info("Process ended with status: #{other}")
    end
  end
end
