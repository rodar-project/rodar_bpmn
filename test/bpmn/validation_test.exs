defmodule Bpmn.ValidationTest do
  use ExUnit.Case, async: true
  doctest Bpmn.Validation

  alias Bpmn.Validation

  defp valid_process_map do
    %{
      "start_1" => {:bpmn_event_start, %{id: "start_1", incoming: [], outgoing: ["flow_1"]}},
      "end_1" => {:bpmn_event_end, %{id: "end_1", incoming: ["flow_1"], outgoing: []}},
      "flow_1" =>
        {:bpmn_sequence_flow,
         %{
           id: "flow_1",
           sourceRef: "start_1",
           targetRef: "end_1",
           conditionExpression: nil
         }}
    }
  end

  describe "validate/1" do
    test "returns {:ok, process_map} for a valid process" do
      map = valid_process_map()
      assert {:ok, ^map} = Validation.validate(map)
    end

    test "accumulates multiple errors in one pass" do
      # Empty map should produce at least start_event_exists and end_event_exists
      {:error, issues} = Validation.validate(%{})
      rules = Enum.map(issues, & &1.rule)
      assert :start_event_exists in rules
      assert :end_event_exists in rules
    end
  end

  describe "validate!/1" do
    test "returns process_map for a valid process" do
      map = valid_process_map()
      assert ^map = Validation.validate!(map)
    end

    test "raises on errors" do
      assert_raise RuntimeError, ~r/Validation failed/, fn ->
        Validation.validate!(%{})
      end
    end
  end

  describe "validate_start_event_exists" do
    test "error when no start event" do
      map = %{
        "end_1" => {:bpmn_event_end, %{id: "end_1", incoming: ["f"], outgoing: []}}
      }

      {:error, issues} = Validation.validate(map)
      assert Enum.any?(issues, &(&1.rule == :start_event_exists))
    end
  end

  describe "validate_start_event_outgoing" do
    test "error when start event has no outgoing flows" do
      map = %{
        "s" => {:bpmn_event_start, %{id: "s", incoming: [], outgoing: []}},
        "e" => {:bpmn_event_end, %{id: "e", incoming: ["f"], outgoing: []}},
        "f" =>
          {:bpmn_sequence_flow,
           %{id: "f", sourceRef: "s", targetRef: "e", conditionExpression: nil}}
      }

      {:error, issues} = Validation.validate(map)
      assert Enum.any?(issues, &(&1.rule == :start_event_outgoing))
    end
  end

  describe "validate_end_event_exists" do
    test "error when no end event" do
      map = %{
        "s" => {:bpmn_event_start, %{id: "s", incoming: [], outgoing: ["f"]}}
      }

      {:error, issues} = Validation.validate(map)
      assert Enum.any?(issues, &(&1.rule == :end_event_exists))
    end
  end

  describe "validate_end_event_incoming" do
    test "error when end event has no incoming flows" do
      map = %{
        "s" => {:bpmn_event_start, %{id: "s", incoming: [], outgoing: ["f"]}},
        "e" => {:bpmn_event_end, %{id: "e", incoming: [], outgoing: []}},
        "f" =>
          {:bpmn_sequence_flow,
           %{id: "f", sourceRef: "s", targetRef: "e", conditionExpression: nil}}
      }

      {:error, issues} = Validation.validate(map)
      assert Enum.any?(issues, &(&1.rule == :end_event_incoming))
    end
  end

  describe "validate_sequence_flow_refs" do
    test "error when sourceRef does not exist" do
      map = %{
        "s" => {:bpmn_event_start, %{id: "s", incoming: [], outgoing: ["f"]}},
        "e" => {:bpmn_event_end, %{id: "e", incoming: ["f"], outgoing: []}},
        "f" =>
          {:bpmn_sequence_flow,
           %{id: "f", sourceRef: "nonexistent", targetRef: "e", conditionExpression: nil}}
      }

      {:error, issues} = Validation.validate(map)

      assert Enum.any?(
               issues,
               &(&1.rule == :sequence_flow_refs and String.contains?(&1.message, "source"))
             )
    end

    test "error when targetRef does not exist" do
      map = %{
        "s" => {:bpmn_event_start, %{id: "s", incoming: [], outgoing: ["f"]}},
        "e" => {:bpmn_event_end, %{id: "e", incoming: ["f"], outgoing: []}},
        "f" =>
          {:bpmn_sequence_flow,
           %{id: "f", sourceRef: "s", targetRef: "nonexistent", conditionExpression: nil}}
      }

      {:error, issues} = Validation.validate(map)

      assert Enum.any?(
               issues,
               &(&1.rule == :sequence_flow_refs and String.contains?(&1.message, "target"))
             )
    end
  end

  describe "validate_orphan_nodes" do
    test "error for node not targeted by any flow" do
      map = %{
        "s" => {:bpmn_event_start, %{id: "s", incoming: [], outgoing: ["f"]}},
        "e" => {:bpmn_event_end, %{id: "e", incoming: ["f"], outgoing: []}},
        "f" =>
          {:bpmn_sequence_flow,
           %{id: "f", sourceRef: "s", targetRef: "e", conditionExpression: nil}},
        "orphan" => {:bpmn_activity_task_service, %{id: "orphan", incoming: [], outgoing: []}}
      }

      {:error, issues} = Validation.validate(map)
      assert Enum.any?(issues, &(&1.rule == :orphan_nodes and &1.node_id == "orphan"))
    end

    test "start events are not flagged as orphans" do
      map = valid_process_map()
      {:ok, _} = Validation.validate(map)
    end

    test "boundary events are not flagged as orphans" do
      map = %{
        "s" => {:bpmn_event_start, %{id: "s", incoming: [], outgoing: ["f1"]}},
        "t" => {:bpmn_activity_task_user, %{id: "t", incoming: ["f1"], outgoing: ["f2"]}},
        "e" => {:bpmn_event_end, %{id: "e", incoming: ["f2"], outgoing: []}},
        "b" =>
          {:bpmn_event_boundary, %{id: "b", incoming: [], outgoing: ["f3"], attachedToRef: "t"}},
        "e2" => {:bpmn_event_end, %{id: "e2", incoming: ["f3"], outgoing: []}},
        "f1" =>
          {:bpmn_sequence_flow,
           %{id: "f1", sourceRef: "s", targetRef: "t", conditionExpression: nil}},
        "f2" =>
          {:bpmn_sequence_flow,
           %{id: "f2", sourceRef: "t", targetRef: "e", conditionExpression: nil}},
        "f3" =>
          {:bpmn_sequence_flow,
           %{id: "f3", sourceRef: "b", targetRef: "e2", conditionExpression: nil}}
      }

      {:ok, _} = Validation.validate(map)
    end
  end

  describe "validate_gateway_outgoing" do
    test "error when fork gateway has less than 2 outgoing" do
      map = %{
        "s" => {:bpmn_event_start, %{id: "s", incoming: [], outgoing: ["f1"]}},
        "gw" => {:bpmn_gateway_exclusive, %{id: "gw", incoming: ["f1"], outgoing: ["f2"]}},
        "e" => {:bpmn_event_end, %{id: "e", incoming: ["f2"], outgoing: []}},
        "f1" =>
          {:bpmn_sequence_flow,
           %{id: "f1", sourceRef: "s", targetRef: "gw", conditionExpression: nil}},
        "f2" =>
          {:bpmn_sequence_flow,
           %{id: "f2", sourceRef: "gw", targetRef: "e", conditionExpression: nil}}
      }

      {:error, issues} = Validation.validate(map)
      assert Enum.any?(issues, &(&1.rule == :gateway_outgoing and &1.node_id == "gw"))
    end

    test "join gateway (>1 incoming) with 1 outgoing is valid" do
      map = %{
        "s" => {:bpmn_event_start, %{id: "s", incoming: [], outgoing: ["f1"]}},
        "gw" => {:bpmn_gateway_parallel, %{id: "gw", incoming: ["f1", "f2"], outgoing: ["f3"]}},
        "e" => {:bpmn_event_end, %{id: "e", incoming: ["f3"], outgoing: []}},
        "f1" =>
          {:bpmn_sequence_flow,
           %{id: "f1", sourceRef: "s", targetRef: "gw", conditionExpression: nil}},
        "f2" =>
          {:bpmn_sequence_flow,
           %{id: "f2", sourceRef: "s", targetRef: "gw", conditionExpression: nil}},
        "f3" =>
          {:bpmn_sequence_flow,
           %{id: "f3", sourceRef: "gw", targetRef: "e", conditionExpression: nil}}
      }

      {:ok, _} = Validation.validate(map)
    end
  end

  describe "validate_exclusive_gateway_default" do
    test "warning when exclusive gateway has conditional flows but no default" do
      map = %{
        "s" => {:bpmn_event_start, %{id: "s", incoming: [], outgoing: ["f1"]}},
        "gw" => {:bpmn_gateway_exclusive, %{id: "gw", incoming: ["f1"], outgoing: ["f2", "f3"]}},
        "e1" => {:bpmn_event_end, %{id: "e1", incoming: ["f2"], outgoing: []}},
        "e2" => {:bpmn_event_end, %{id: "e2", incoming: ["f3"], outgoing: []}},
        "f1" =>
          {:bpmn_sequence_flow,
           %{id: "f1", sourceRef: "s", targetRef: "gw", conditionExpression: nil}},
        "f2" =>
          {:bpmn_sequence_flow,
           %{
             id: "f2",
             sourceRef: "gw",
             targetRef: "e1",
             conditionExpression: {:bpmn_expression, {"elixir", "true"}}
           }},
        "f3" =>
          {:bpmn_sequence_flow,
           %{id: "f3", sourceRef: "gw", targetRef: "e2", conditionExpression: nil}}
      }

      # Warnings don't cause failure
      {:ok, _} = Validation.validate(map)
    end
  end

  describe "validate_boundary_attachment" do
    test "error when attachedToRef points to non-existent node" do
      map = %{
        "s" => {:bpmn_event_start, %{id: "s", incoming: [], outgoing: ["f1"]}},
        "e" => {:bpmn_event_end, %{id: "e", incoming: ["f1"], outgoing: []}},
        "b" =>
          {:bpmn_event_boundary,
           %{id: "b", incoming: [], outgoing: ["f2"], attachedToRef: "nonexistent"}},
        "f1" =>
          {:bpmn_sequence_flow,
           %{id: "f1", sourceRef: "s", targetRef: "e", conditionExpression: nil}},
        "f2" =>
          {:bpmn_sequence_flow,
           %{id: "f2", sourceRef: "b", targetRef: "e", conditionExpression: nil}}
      }

      {:error, issues} = Validation.validate(map)
      assert Enum.any?(issues, &(&1.rule == :boundary_attachment))
    end

    test "error when boundary event has no attachedToRef" do
      map = %{
        "s" => {:bpmn_event_start, %{id: "s", incoming: [], outgoing: ["f1"]}},
        "e" => {:bpmn_event_end, %{id: "e", incoming: ["f1"], outgoing: []}},
        "b" => {:bpmn_event_boundary, %{id: "b", incoming: [], outgoing: ["f2"]}},
        "f1" =>
          {:bpmn_sequence_flow,
           %{id: "f1", sourceRef: "s", targetRef: "e", conditionExpression: nil}},
        "f2" =>
          {:bpmn_sequence_flow,
           %{id: "f2", sourceRef: "b", targetRef: "e", conditionExpression: nil}}
      }

      {:error, issues} = Validation.validate(map)
      assert Enum.any?(issues, &(&1.rule == :boundary_attachment))
    end
  end

  describe "validate_collaboration/2" do
    defp sample_processes do
      elements_a = %{
        "s_a" => {:bpmn_event_start, %{id: "s_a", incoming: [], outgoing: ["f_a"]}},
        "throw_a" =>
          {:bpmn_event_intermediate_throw,
           %{
             id: "throw_a",
             incoming: ["f_a"],
             outgoing: ["f_a2"],
             messageEventDefinition: {:bpmn_event_definition_message, %{messageRef: "msg1"}}
           }},
        "e_a" => {:bpmn_event_end, %{id: "e_a", incoming: ["f_a2"], outgoing: []}},
        "f_a" =>
          {:bpmn_sequence_flow,
           %{id: "f_a", sourceRef: "s_a", targetRef: "throw_a", conditionExpression: nil}},
        "f_a2" =>
          {:bpmn_sequence_flow,
           %{id: "f_a2", sourceRef: "throw_a", targetRef: "e_a", conditionExpression: nil}}
      }

      elements_b = %{
        "s_b" => {:bpmn_event_start, %{id: "s_b", incoming: [], outgoing: ["f_b"]}},
        "catch_b" =>
          {:bpmn_event_intermediate_catch,
           %{
             id: "catch_b",
             incoming: ["f_b"],
             outgoing: ["f_b2"],
             messageEventDefinition: {:bpmn_event_definition_message, %{messageRef: "msg1"}}
           }},
        "e_b" => {:bpmn_event_end, %{id: "e_b", incoming: ["f_b2"], outgoing: []}},
        "f_b" =>
          {:bpmn_sequence_flow,
           %{id: "f_b", sourceRef: "s_b", targetRef: "catch_b", conditionExpression: nil}},
        "f_b2" =>
          {:bpmn_sequence_flow,
           %{id: "f_b2", sourceRef: "catch_b", targetRef: "e_b", conditionExpression: nil}}
      }

      [
        {:bpmn_process, %{id: "ProcessA"}, elements_a},
        {:bpmn_process, %{id: "ProcessB"}, elements_b}
      ]
    end

    test "valid collaboration passes" do
      collab = %{
        id: "collab_1",
        participants: [
          %{id: "p1", name: "A", processRef: "ProcessA"},
          %{id: "p2", name: "B", processRef: "ProcessB"}
        ],
        message_flows: [
          %{id: "mf1", name: "", sourceRef: "throw_a", targetRef: "catch_b"}
        ]
      }

      {:ok, _} = Validation.validate_collaboration(collab, sample_processes())
    end

    test "error when participant processRef doesn't match any process" do
      collab = %{
        id: "collab_1",
        participants: [
          %{id: "p1", name: "A", processRef: "NonexistentProcess"}
        ],
        message_flows: []
      }

      {:error, issues} = Validation.validate_collaboration(collab, sample_processes())
      assert Enum.any?(issues, &(&1.rule == :participant_process_ref))
    end

    test "error when message flow sourceRef doesn't exist in any process" do
      collab = %{
        id: "collab_1",
        participants: [
          %{id: "p1", name: "A", processRef: "ProcessA"},
          %{id: "p2", name: "B", processRef: "ProcessB"}
        ],
        message_flows: [
          %{id: "mf1", name: "", sourceRef: "nonexistent", targetRef: "catch_b"}
        ]
      }

      {:error, issues} = Validation.validate_collaboration(collab, sample_processes())
      assert Enum.any?(issues, &(&1.rule == :message_flow_refs))
    end

    test "error when message flow source and target are in the same process" do
      collab = %{
        id: "collab_1",
        participants: [
          %{id: "p1", name: "A", processRef: "ProcessA"},
          %{id: "p2", name: "B", processRef: "ProcessB"}
        ],
        message_flows: [
          %{id: "mf1", name: "", sourceRef: "throw_a", targetRef: "e_a"}
        ]
      }

      {:error, issues} = Validation.validate_collaboration(collab, sample_processes())
      assert Enum.any?(issues, &(&1.rule == :message_flow_cross_process))
    end
  end
end
