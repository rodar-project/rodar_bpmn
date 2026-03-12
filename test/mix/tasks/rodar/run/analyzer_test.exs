defmodule Mix.Tasks.RodarBpmn.Run.AnalyzerTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.RodarBpmn.Run.Analyzer

  describe "extract_data_keys/1" do
    test "extracts keys from Elixir condition expressions" do
      process_map = %{
        "flow_1" =>
          {:bpmn_sequence_flow,
           %{
             id: "flow_1",
             conditionExpression: {:bpmn_expression, {"elixir", ~s|data["amount"] > 1000|}}
           }},
        "flow_2" =>
          {:bpmn_sequence_flow,
           %{
             id: "flow_2",
             conditionExpression: {:bpmn_expression, {"elixir", ~s|data["approved"] == true|}}
           }}
      }

      keys = Analyzer.extract_data_keys(process_map)
      assert MapSet.member?(keys, "amount")
      assert MapSet.member?(keys, "approved")
      assert MapSet.size(keys) == 2
    end

    test "ignores flows without condition expressions" do
      process_map = %{
        "flow_1" => {:bpmn_sequence_flow, %{id: "flow_1", conditionExpression: nil}},
        "task_1" => {:bpmn_activity_task_script, %{id: "task_1"}}
      }

      keys = Analyzer.extract_data_keys(process_map)
      assert MapSet.size(keys) == 0
    end

    test "does not extract keys from FEEL expressions" do
      process_map = %{
        "flow_1" =>
          {:bpmn_sequence_flow,
           %{
             id: "flow_1",
             conditionExpression: {:bpmn_expression, {"feel", "amount > 1000"}}
           }}
      }

      keys = Analyzer.extract_data_keys(process_map)
      assert MapSet.size(keys) == 0
    end
  end

  describe "find_unhandled_service_tasks/1" do
    test "finds service tasks without handler attribute" do
      process_map = %{
        "task_1" => {:bpmn_activity_task_service, %{id: "task_1", name: "Validate"}},
        "task_2" =>
          {:bpmn_activity_task_service, %{id: "task_2", name: "Handled", handler: SomeModule}}
      }

      result = Analyzer.find_unhandled_service_tasks(process_map)
      assert length(result) == 1
      assert [{"task_1", %{name: "Validate"}}] = result
    end

    test "returns empty list when all service tasks have handlers" do
      process_map = %{
        "task_1" => {:bpmn_activity_task_service, %{id: "task_1", handler: SomeModule}}
      }

      assert Analyzer.find_unhandled_service_tasks(process_map) == []
    end
  end

  describe "find_user_tasks/1" do
    test "finds user task elements" do
      process_map = %{
        "task_1" => {:bpmn_activity_task_user, %{id: "task_1", name: "Review"}},
        "task_2" => {:bpmn_activity_task_script, %{id: "task_2"}}
      }

      result = Analyzer.find_user_tasks(process_map)
      assert length(result) == 1
      assert [{"task_1", %{name: "Review"}}] = result
    end
  end

  describe "downstream_data_hints/2" do
    test "collects data keys from gateway conditions following a node" do
      process_map = %{
        "task_1" => {:bpmn_activity_task_user, %{id: "task_1", outgoing: ["flow_1"]}},
        "flow_1" =>
          {:bpmn_sequence_flow, %{id: "flow_1", targetRef: "gw_1", conditionExpression: nil}},
        "gw_1" => {:bpmn_gateway_exclusive, %{id: "gw_1", outgoing: ["flow_yes", "flow_no"]}},
        "flow_yes" =>
          {:bpmn_sequence_flow,
           %{
             id: "flow_yes",
             conditionExpression: {:bpmn_expression, {"elixir", ~s|data["approved"] == true|}}
           }},
        "flow_no" =>
          {:bpmn_sequence_flow,
           %{
             id: "flow_no",
             conditionExpression: {:bpmn_expression, {"elixir", ~s|data["approved"] != true|}}
           }}
      }

      hints = Analyzer.downstream_data_hints(process_map, "task_1")
      assert MapSet.member?(hints, "approved")
    end

    test "returns empty set when node has no outgoing" do
      process_map = %{
        "end_1" => {:bpmn_event_end, %{id: "end_1", incoming: ["f"]}}
      }

      hints = Analyzer.downstream_data_hints(process_map, "end_1")
      assert MapSet.size(hints) == 0
    end

    test "returns empty set for unknown node" do
      hints = Analyzer.downstream_data_hints(%{}, "nonexistent")
      assert MapSet.size(hints) == 0
    end
  end

  describe "analyze/1" do
    test "returns combined analysis" do
      process_map = %{
        "start" => {:bpmn_event_start, %{id: "start", outgoing: ["f1"]}},
        "task_1" => {:bpmn_activity_task_service, %{id: "task_1", name: "Svc"}},
        "task_2" => {:bpmn_activity_task_user, %{id: "task_2", name: "Review"}},
        "flow_cond" =>
          {:bpmn_sequence_flow,
           %{
             id: "flow_cond",
             conditionExpression: {:bpmn_expression, {"elixir", ~s|data["status"] == "ok"|}}
           }}
      }

      result = Analyzer.analyze(process_map)
      assert MapSet.member?(result.data_keys, "status")
      assert length(result.unhandled_service_tasks) == 1
      assert length(result.user_tasks) == 1
    end
  end
end
