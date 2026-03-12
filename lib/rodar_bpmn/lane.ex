defmodule RodarBpmn.Lane do
  @moduledoc """
  Stateless utility functions for querying BPMN lane assignments.

  Lanes are structural metadata that assign flow nodes (tasks, events, gateways)
  to roles, groups, or departments. They do not affect execution — the engine
  treats them as read-only annotations.

  All functions accept a `lane_set` map as returned by the parser in the process
  attrs (`:lane_set` key). A `nil` lane set is handled gracefully.

  ## Examples

      iex> lane_set = %{
      ...>   id: "ls1",
      ...>   lanes: [
      ...>     %{id: "lane1", name: "HR", flow_node_refs: ["task1", "task2"], child_lane_set: nil}
      ...>   ]
      ...> }
      iex> {:ok, lane} = RodarBpmn.Lane.find_lane_for_node(lane_set, "task1")
      iex> lane.name
      "HR"

  ## See Also

  - `RodarBpmn.Engine.Diagram` -- parser that extracts lane sets from BPMN XML
  - `RodarBpmn.Validation.validate_lanes/2` -- validates lane referential integrity

  """

  @doc """
  Finds the deepest lane containing the given node ID.

  Searches recursively through child lane sets. Returns the most specific
  (deepest nested) lane that references the node.

  Returns `{:ok, lane}` or `:error` if not found.

  ## Examples

      iex> lane_set = %{id: "ls1", lanes: [
      ...>   %{id: "l1", name: "A", flow_node_refs: ["n1"], child_lane_set: nil}
      ...> ]}
      iex> {:ok, lane} = RodarBpmn.Lane.find_lane_for_node(lane_set, "n1")
      iex> lane.id
      "l1"

      iex> RodarBpmn.Lane.find_lane_for_node(nil, "n1")
      :error

  """
  @spec find_lane_for_node(map() | nil, String.t()) :: {:ok, map()} | :error
  def find_lane_for_node(nil, _node_id), do: :error

  def find_lane_for_node(%{lanes: lanes}, node_id) do
    find_in_lanes(lanes, node_id)
  end

  defp find_in_lanes(lanes, node_id) do
    Enum.find_value(lanes, :error, fn lane ->
      find_in_lane(lane, node_id)
    end)
  end

  defp find_in_lane(lane, node_id) do
    child_result = find_in_child_lane_set(lane[:child_lane_set], node_id)

    case child_result do
      {:ok, _} -> child_result
      :error -> match_lane_ref(lane, node_id)
    end
  end

  defp find_in_child_lane_set(%{lanes: child_lanes}, node_id),
    do: find_in_lanes(child_lanes, node_id)

  defp find_in_child_lane_set(nil, _node_id), do: :error

  defp match_lane_ref(lane, node_id) do
    if node_id in lane.flow_node_refs, do: {:ok, lane}, else: nil
  end

  @doc """
  Builds a flat map from node ID to its deepest lane.

  When a node appears in both a parent and child lane, the child (deepest) lane wins.

  ## Examples

      iex> lane_set = %{id: "ls1", lanes: [
      ...>   %{id: "l1", name: "A", flow_node_refs: ["n1", "n2"], child_lane_set: nil},
      ...>   %{id: "l2", name: "B", flow_node_refs: ["n3"], child_lane_set: nil}
      ...> ]}
      iex> map = RodarBpmn.Lane.node_lane_map(lane_set)
      iex> map["n1"].id
      "l1"
      iex> map["n3"].id
      "l2"

      iex> RodarBpmn.Lane.node_lane_map(nil)
      %{}

  """
  @spec node_lane_map(map() | nil) :: %{String.t() => map()}
  def node_lane_map(nil), do: %{}

  def node_lane_map(%{lanes: lanes}) do
    collect_node_lanes(lanes, %{})
  end

  defp collect_node_lanes(lanes, acc) do
    Enum.reduce(lanes, acc, fn lane, acc ->
      # First add parent refs
      acc = Enum.reduce(lane.flow_node_refs, acc, fn ref, a -> Map.put(a, ref, lane) end)

      # Then overwrite with child lane refs (deepest wins)
      case lane[:child_lane_set] do
        %{lanes: child_lanes} -> collect_node_lanes(child_lanes, acc)
        nil -> acc
      end
    end)
  end

  @doc """
  Returns a flat list of all lanes, including nested children.

  ## Examples

      iex> lane_set = %{id: "ls1", lanes: [
      ...>   %{id: "l1", name: "A", flow_node_refs: ["n1"], child_lane_set: %{
      ...>     id: "cls1", lanes: [%{id: "l1a", name: "A1", flow_node_refs: ["n1"], child_lane_set: nil}]
      ...>   }},
      ...>   %{id: "l2", name: "B", flow_node_refs: ["n2"], child_lane_set: nil}
      ...> ]}
      iex> lanes = RodarBpmn.Lane.all_lanes(lane_set)
      iex> length(lanes)
      3
      iex> Enum.map(lanes, & &1.id) |> Enum.sort()
      ["l1", "l1a", "l2"]

      iex> RodarBpmn.Lane.all_lanes(nil)
      []

  """
  @spec all_lanes(map() | nil) :: [map()]
  def all_lanes(nil), do: []

  def all_lanes(%{lanes: lanes}) do
    flatten_lanes(lanes)
  end

  defp flatten_lanes(lanes) do
    Enum.flat_map(lanes, fn lane ->
      children =
        case lane[:child_lane_set] do
          %{lanes: child_lanes} -> flatten_lanes(child_lanes)
          nil -> []
        end

      [lane | children]
    end)
  end
end
