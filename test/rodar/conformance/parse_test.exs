defmodule RodarBpmn.Conformance.ParseTest do
  use ExUnit.Case, async: true

  alias RodarBpmn.Conformance.TestHelper

  @moduletag :conformance

  describe "MIWG A.1.0 — Sequential Flow" do
    setup do
      {:ok, diagram: TestHelper.load_fixture(:miwg, "A.1.0.bpmn")}
    end

    test "parses successfully with expected structure", %{diagram: diagram} do
      assert is_map(diagram)
      assert Map.has_key?(diagram, :processes)
      assert length(diagram.processes) == 1
    end

    test "process has correct ID", %{diagram: diagram} do
      [{:bpmn_process, attrs, _elements}] = diagram.processes
      assert attrs[:id] == "WFP-6-"
    end

    test "contains 1 start event, 3 tasks, 1 end event, 4 sequence flows", %{diagram: diagram} do
      elements = TestHelper.first_process_elements(diagram)

      assert TestHelper.count_elements_by_type(elements, :bpmn_event_start) == 1
      assert TestHelper.count_elements_by_type(elements, :bpmn_activity_task) == 3
      assert TestHelper.count_elements_by_type(elements, :bpmn_event_end) == 1
      assert TestHelper.count_elements_by_type(elements, :bpmn_sequence_flow) == 4
    end

    test "start event has one outgoing flow", %{diagram: diagram} do
      elements = TestHelper.first_process_elements(diagram)
      start = TestHelper.find_start_event(elements)
      {:bpmn_event_start, %{outgoing: outgoing}} = start
      assert length(outgoing) == 1
    end
  end

  describe "MIWG A.2.0 — Exclusive Gateway" do
    setup do
      {:ok, diagram: TestHelper.load_fixture(:miwg, "A.2.0.bpmn")}
    end

    test "parses successfully", %{diagram: diagram} do
      assert length(diagram.processes) == 1
    end

    test "process has correct ID", %{diagram: diagram} do
      [{:bpmn_process, attrs, _}] = diagram.processes
      assert attrs[:id] == "WFP-6-"
    end

    test "contains 2 exclusive gateways", %{diagram: diagram} do
      elements = TestHelper.first_process_elements(diagram)
      assert TestHelper.count_elements_by_type(elements, :bpmn_gateway_exclusive) == 2
    end

    test "split gateway has 3 outgoing flows", %{diagram: diagram} do
      elements = TestHelper.first_process_elements(diagram)

      split_gw =
        Enum.find_value(elements, fn
          {_id, {:bpmn_gateway_exclusive, %{outgoing: out}} = elem} when length(out) == 3 ->
            elem

          _ ->
            nil
        end)

      assert split_gw != nil
      {:bpmn_gateway_exclusive, %{outgoing: outgoing}} = split_gw
      assert length(outgoing) == 3
    end

    test "contains 4 tasks", %{diagram: diagram} do
      elements = TestHelper.first_process_elements(diagram)
      assert TestHelper.count_elements_by_type(elements, :bpmn_activity_task) == 4
    end
  end

  describe "MIWG A.3.0 — Subprocess with Boundary Events" do
    setup do
      {:ok, diagram: TestHelper.load_fixture(:miwg, "A.3.0.bpmn")}
    end

    test "parses successfully", %{diagram: diagram} do
      assert length(diagram.processes) == 1
    end

    test "contains an embedded subprocess", %{diagram: diagram} do
      elements = TestHelper.first_process_elements(diagram)

      subprocess_count =
        TestHelper.count_elements_by_type(elements, :bpmn_activity_subprocess_embeded)

      assert subprocess_count >= 1
    end

    test "contains boundary events with attachedToRef", %{diagram: diagram} do
      elements = TestHelper.first_process_elements(diagram)

      boundary_events =
        Enum.filter(elements, fn
          {_id, {:bpmn_event_boundary, %{attachedToRef: ref}}} when is_binary(ref) -> true
          _ -> false
        end)

      assert length(boundary_events) >= 2
    end

    test "contains 2 end events", %{diagram: diagram} do
      elements = TestHelper.first_process_elements(diagram)
      assert TestHelper.count_elements_by_type(elements, :bpmn_event_end) == 2
    end

    test "contains 4 tasks", %{diagram: diagram} do
      elements = TestHelper.first_process_elements(diagram)
      assert TestHelper.count_elements_by_type(elements, :bpmn_activity_task) == 4
    end
  end

  describe "MIWG B.1.0 — Collaboration" do
    setup do
      {:ok, diagram: TestHelper.load_fixture(:miwg, "B.1.0.bpmn")}
    end

    test "parses successfully with multiple processes", %{diagram: diagram} do
      assert length(diagram.processes) >= 2
    end

    test "has collaboration element", %{diagram: diagram} do
      assert diagram.collaboration != nil
    end

    test "collaboration has participants", %{diagram: diagram} do
      collab = diagram.collaboration
      assert Map.has_key?(collab, :participants)
      assert length(collab.participants) >= 2
    end

    test "collaboration has message flows", %{diagram: diagram} do
      collab = diagram.collaboration
      assert Map.has_key?(collab, :message_flows)
      assert collab.message_flows != []
    end

    test "contains various task types across processes", %{diagram: diagram} do
      all_types =
        diagram.processes
        |> Enum.flat_map(fn {:bpmn_process, _, elements} ->
          Enum.map(elements, fn {_id, {type, _}} -> type end)
        end)
        |> Enum.uniq()

      assert :bpmn_activity_task_user in all_types
      assert :bpmn_activity_task_service in all_types
    end

    test "contains a subprocess", %{diagram: diagram} do
      all_types =
        diagram.processes
        |> Enum.flat_map(fn {:bpmn_process, _, elements} ->
          Enum.map(elements, fn {_id, {type, _}} -> type end)
        end)
        |> Enum.uniq()

      assert :bpmn_activity_subprocess_embeded in all_types or
               :bpmn_activity_subprocess in all_types
    end
  end

  describe "MIWG B.2.0 — Advanced Elements" do
    setup do
      {:ok, diagram: TestHelper.load_fixture(:miwg, "B.2.0.bpmn")}
    end

    test "parses successfully with multiple processes", %{diagram: diagram} do
      assert length(diagram.processes) >= 2
    end

    test "contains parallel gateways", %{diagram: diagram} do
      elements = TestHelper.first_process_elements(diagram)
      assert TestHelper.count_elements_by_type(elements, :bpmn_gateway_parallel) >= 2
    end

    test "contains inclusive gateways", %{diagram: diagram} do
      elements = TestHelper.first_process_elements(diagram)
      assert TestHelper.count_elements_by_type(elements, :bpmn_gateway_inclusive) >= 2
    end

    test "contains boundary events", %{diagram: diagram} do
      elements = TestHelper.first_process_elements(diagram)
      assert TestHelper.count_elements_by_type(elements, :bpmn_event_boundary) >= 1
    end

    test "contains intermediate catch event", %{diagram: diagram} do
      elements = TestHelper.first_process_elements(diagram)
      assert TestHelper.count_elements_by_type(elements, :bpmn_event_intermediate_catch) >= 1
    end

    test "contains intermediate throw event", %{diagram: diagram} do
      elements = TestHelper.first_process_elements(diagram)
      assert TestHelper.count_elements_by_type(elements, :bpmn_event_intermediate_throw) >= 1
    end

    test "contains embedded subprocess", %{diagram: diagram} do
      elements = TestHelper.first_process_elements(diagram)
      assert TestHelper.count_elements_by_type(elements, :bpmn_activity_subprocess_embeded) >= 1
    end

    test "contains send task", %{diagram: diagram} do
      elements = TestHelper.first_process_elements(diagram)
      assert TestHelper.count_elements_by_type(elements, :bpmn_activity_task_send) >= 1
    end
  end
end
