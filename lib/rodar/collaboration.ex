defmodule RodarBpmn.Collaboration do
  @moduledoc """
  Multi-participant collaboration orchestration.

  Manages starting and wiring multiple BPMN processes that communicate
  via message flows, using the existing `RodarBpmn.Event.Bus` for inter-process
  messaging.

  ## Usage

      diagram = RodarBpmn.Engine.Diagram.load(xml)
      {:ok, result} = RodarBpmn.Collaboration.start(diagram)
      # result = %{collaboration_id: id, instances: %{process_id => pid}}

      RodarBpmn.Collaboration.stop(result)
  """

  require Logger

  alias RodarBpmn.Context
  alias RodarBpmn.Event.Bus
  alias RodarBpmn.Process, as: BpmnProcess
  alias RodarBpmn.Registry

  @doc """
  Start a collaboration from a parsed diagram map.

  Registers each participant's process, creates process instances,
  wires message flows via the event bus, and activates all processes.

  Returns `{:ok, %{collaboration_id: id, instances: %{process_id => pid}}}`.
  """
  @spec start(map(), map()) :: {:ok, map()} | {:error, any()}
  def start(diagram, init_data \\ %{}) do
    collaboration = diagram.collaboration
    processes = diagram.processes

    if collaboration == nil do
      {:error, "No collaboration found in diagram"}
    else
      processes_by_id = build_processes_by_id(processes)

      with :ok <- validate_participants(collaboration.participants, processes_by_id),
           {:ok, instances} <-
             start_instances(collaboration.participants, processes_by_id, init_data),
           :ok <- wire_message_flows(collaboration.message_flows, processes_by_id, instances) do
        activate_all(instances)

        {:ok,
         %{
           collaboration_id: collaboration.id,
           instances: instances
         }}
      end
    end
  end

  @doc """
  Stop all process instances in a collaboration.
  """
  @spec stop(map()) :: :ok
  def stop(%{instances: instances}) do
    Enum.each(instances, fn {_process_id, pid} ->
      if Process.alive?(pid), do: BpmnProcess.terminate(pid)
    end)

    :ok
  end

  # --- Private helpers ---

  defp build_processes_by_id(processes) do
    Enum.reduce(processes, %{}, fn {:bpmn_process, attrs, elements} = process, acc ->
      id = attrs[:id] |> to_string()
      Map.put(acc, id, {process, elements})
    end)
  end

  defp validate_participants(participants, processes_by_id) do
    missing =
      Enum.filter(participants, fn p ->
        p.processRef != "" and not Map.has_key?(processes_by_id, p.processRef)
      end)

    if missing == [] do
      :ok
    else
      ids = Enum.map_join(missing, ", ", & &1.processRef)
      {:error, "Participant process(es) not found: #{ids}"}
    end
  end

  defp start_instances(participants, processes_by_id, init_data) do
    participants
    |> Enum.filter(&(&1.processRef != ""))
    |> Enum.reduce_while({:ok, %{}}, fn participant, {:ok, acc} ->
      start_participant(participant.processRef, processes_by_id, init_data, acc)
    end)
  end

  defp start_participant(process_id, processes_by_id, init_data, acc) do
    {process_def, _elements} = Map.fetch!(processes_by_id, process_id)
    Registry.register(process_id, process_def)

    case DynamicSupervisor.start_child(
           RodarBpmn.ProcessSupervisor,
           {BpmnProcess, {process_id, init_data}}
         ) do
      {:ok, pid} ->
        {:cont, {:ok, Map.put(acc, process_id, pid)}}

      {:error, reason} ->
        {:halt, {:error, "Failed to start process '#{process_id}': #{inspect(reason)}"}}
    end
  end

  defp wire_message_flows(message_flows, processes_by_id, instances) do
    Enum.each(message_flows, fn flow ->
      wire_single_message_flow(flow, processes_by_id, instances)
    end)

    :ok
  end

  defp wire_single_message_flow(flow, processes_by_id, instances) do
    target_ref = flow.targetRef

    with {process_id, {_type, attrs}} when process_id != nil <-
           find_element_in_processes(target_ref, processes_by_id),
         target_pid when target_pid != nil <- Map.get(instances, process_id) do
      context = BpmnProcess.get_context(target_pid)
      message_ref = extract_message_ref(attrs, target_ref)
      outgoing = Map.get(attrs, :outgoing, [])
      metadata = %{context: context, node_id: target_ref, outgoing: outgoing}
      metadata = put_correlation(metadata, flow, context)
      Bus.subscribe(:message, message_ref, metadata)
    end
  end

  defp put_correlation(metadata, flow, context) do
    case Map.get(flow, :correlationKey) do
      nil ->
        metadata

      key ->
        data = Context.get(context, :data)
        Map.put(metadata, :correlation, %{key: key, value: Map.get(data, key)})
    end
  end

  defp find_element_in_processes(element_id, processes_by_id) do
    Enum.find_value(processes_by_id, {nil, nil}, fn {process_id, {_process, elements}} ->
      case Map.get(elements, element_id) do
        nil -> nil
        element -> {process_id, element}
      end
    end)
  end

  defp extract_message_ref(attrs, default) do
    case Map.get(attrs, :messageEventDefinition) do
      {:bpmn_event_definition_message, def_attrs} ->
        Map.get(def_attrs, :messageRef, default)

      _ ->
        default
    end
  end

  defp activate_all(instances) do
    Enum.each(instances, fn {_process_id, pid} ->
      BpmnProcess.activate(pid)
    end)
  end
end
