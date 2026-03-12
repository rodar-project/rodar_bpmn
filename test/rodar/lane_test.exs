defmodule RodarBpmn.LaneTest do
  use ExUnit.Case, async: true

  alias RodarBpmn.Lane

  doctest RodarBpmn.Lane

  defp sample_lane_set do
    %{
      id: "ls1",
      lanes: [
        %{id: "lane_hr", name: "HR", flow_node_refs: ["task1", "task2"], child_lane_set: nil},
        %{
          id: "lane_mgr",
          name: "Manager",
          flow_node_refs: ["task3"],
          child_lane_set: %{
            id: "cls1",
            lanes: [
              %{
                id: "lane_senior",
                name: "Senior Manager",
                flow_node_refs: ["task3"],
                child_lane_set: nil
              }
            ]
          }
        }
      ]
    }
  end

  describe "find_lane_for_node/2" do
    test "finds lane for a node in a top-level lane" do
      assert {:ok, lane} = Lane.find_lane_for_node(sample_lane_set(), "task1")
      assert lane.id == "lane_hr"
    end

    test "finds deepest lane when node is in both parent and child" do
      assert {:ok, lane} = Lane.find_lane_for_node(sample_lane_set(), "task3")
      assert lane.id == "lane_senior"
    end

    test "returns :error for unknown node" do
      assert :error = Lane.find_lane_for_node(sample_lane_set(), "unknown")
    end

    test "returns :error for nil lane_set" do
      assert :error = Lane.find_lane_for_node(nil, "task1")
    end
  end

  describe "node_lane_map/1" do
    test "builds flat map of node IDs to lanes" do
      map = Lane.node_lane_map(sample_lane_set())
      assert map["task1"].id == "lane_hr"
      assert map["task2"].id == "lane_hr"
    end

    test "deepest lane wins for nested nodes" do
      map = Lane.node_lane_map(sample_lane_set())
      assert map["task3"].id == "lane_senior"
    end

    test "returns empty map for nil" do
      assert %{} == Lane.node_lane_map(nil)
    end
  end

  describe "all_lanes/1" do
    test "flattens all lanes including nested" do
      lanes = Lane.all_lanes(sample_lane_set())
      ids = Enum.map(lanes, & &1.id) |> Enum.sort()
      assert ids == ["lane_hr", "lane_mgr", "lane_senior"]
    end

    test "returns empty list for nil" do
      assert [] == Lane.all_lanes(nil)
    end

    test "returns single lane when no nesting" do
      lane_set = %{
        id: "ls1",
        lanes: [%{id: "l1", name: "Only", flow_node_refs: ["n1"], child_lane_set: nil}]
      }

      assert [lane] = Lane.all_lanes(lane_set)
      assert lane.id == "l1"
    end
  end
end
