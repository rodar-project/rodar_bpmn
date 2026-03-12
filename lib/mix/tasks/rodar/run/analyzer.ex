defmodule Mix.Tasks.RodarBpmn.Run.Analyzer do
  @moduledoc """
  Pre-execution analysis of a BPMN process map.

  Scans the process map for data keys referenced in condition expressions,
  service tasks without handlers, and user tasks. Used by `Mix.Tasks.RodarBpmn.Run`
  to provide informative output before execution begins.
  """

  @doc """
  Analyze a process map and return a summary.

  Returns a map with:
  - `:data_keys` — set of data keys referenced in condition expressions
  - `:unhandled_service_tasks` — list of service task elements without inline handlers
  - `:user_tasks` — list of user task elements
  """
  @spec analyze(map()) :: map()
  def analyze(process_map) do
    %{
      data_keys: extract_data_keys(process_map),
      unhandled_service_tasks: find_unhandled_service_tasks(process_map),
      user_tasks: find_user_tasks(process_map)
    }
  end

  @doc """
  Extract data keys referenced in Elixir condition expressions.

  Scans sequence flow condition expressions for `data["key"]` patterns.
  FEEL expressions are noted but not parsed (bare identifiers are ambiguous).
  """
  @spec extract_data_keys(map()) :: MapSet.t(String.t())
  def extract_data_keys(process_map) do
    process_map
    |> Enum.reduce(MapSet.new(), fn
      {_id, {:bpmn_sequence_flow, %{conditionExpression: {:bpmn_expression, {lang, expr}}}}},
      acc ->
        extract_keys_from_expression(lang, expr, acc)

      _, acc ->
        acc
    end)
  end

  @doc """
  Find service tasks without inline `:handler` attributes.
  """
  @spec find_unhandled_service_tasks(map()) :: [{String.t(), map()}]
  def find_unhandled_service_tasks(process_map) do
    Enum.flat_map(process_map, fn
      {id, {:bpmn_activity_task_service, %{handler: _}}} when id != nil ->
        []

      {id, {:bpmn_activity_task_service, attrs}} ->
        [{id, attrs}]

      _ ->
        []
    end)
  end

  @doc """
  Find user task elements in the process map.
  """
  @spec find_user_tasks(map()) :: [{String.t(), map()}]
  def find_user_tasks(process_map) do
    Enum.flat_map(process_map, fn
      {id, {:bpmn_activity_task_user, attrs}} ->
        [{id, attrs}]

      _ ->
        []
    end)
  end

  @doc """
  Follow a node's outgoing flows to the next gateway and extract
  data keys from its condition expressions as hints for user prompts.
  """
  @spec downstream_data_hints(map(), String.t()) :: MapSet.t(String.t())
  def downstream_data_hints(process_map, node_id) do
    case Map.get(process_map, node_id) do
      {_type, %{outgoing: outgoing}} ->
        outgoing
        |> Enum.reduce(MapSet.new(), fn flow_id, acc ->
          collect_downstream_keys(process_map, flow_id, acc, 0)
        end)

      _ ->
        MapSet.new()
    end
  end

  # --- Private ---

  defp extract_keys_from_expression("elixir", expr, acc) do
    ~r/data\["([^"]+)"\]/
    |> Regex.scan(expr)
    |> Enum.reduce(acc, fn [_, key], set -> MapSet.put(set, key) end)
  end

  defp extract_keys_from_expression(_lang, _expr, acc), do: acc

  # Walk downstream up to 3 hops looking for gateway conditions
  defp collect_downstream_keys(_process_map, _id, acc, depth) when depth > 3, do: acc

  defp collect_downstream_keys(process_map, id, acc, depth) do
    case Map.get(process_map, id) do
      {:bpmn_sequence_flow, %{targetRef: target}} ->
        collect_downstream_keys(process_map, target, acc, depth + 1)

      {:bpmn_gateway_exclusive, %{outgoing: outgoing}} ->
        extract_gateway_condition_keys(process_map, outgoing, acc)

      _ ->
        acc
    end
  end

  defp extract_gateway_condition_keys(process_map, outgoing, acc) do
    Enum.reduce(outgoing, acc, fn flow_id, inner_acc ->
      case Map.get(process_map, flow_id) do
        {:bpmn_sequence_flow, %{conditionExpression: {:bpmn_expression, {lang, expr}}}} ->
          extract_keys_from_expression(lang, expr, inner_acc)

        _ ->
          inner_acc
      end
    end)
  end
end
