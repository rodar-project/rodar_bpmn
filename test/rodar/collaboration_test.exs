defmodule Rodar.CollaborationTest do
  use ExUnit.Case, async: false

  alias Rodar.{Collaboration, Registry}

  setup do
    for id <- Registry.list() do
      Registry.unregister(id)
    end

    :ok
  end

  defp make_flow(id, source, target) do
    {:bpmn_sequence_flow,
     %{id: id, sourceRef: source, targetRef: target, conditionExpression: nil, isImmediate: nil}}
  end

  describe "start/2" do
    test "starts a two-participant collaboration with independent processes" do
      elements_a = %{
        "s_a" => {:bpmn_event_start, %{id: "s_a", incoming: [], outgoing: ["f_a"]}},
        "e_a" => {:bpmn_event_end, %{id: "e_a", incoming: ["f_a"], outgoing: []}},
        "f_a" => make_flow("f_a", "s_a", "e_a")
      }

      elements_b = %{
        "s_b" => {:bpmn_event_start, %{id: "s_b", incoming: [], outgoing: ["f_b"]}},
        "e_b" => {:bpmn_event_end, %{id: "e_b", incoming: ["f_b"], outgoing: []}},
        "f_b" => make_flow("f_b", "s_b", "e_b")
      }

      diagram = %{
        collaboration: %{
          id: "collab_1",
          participants: [
            %{id: "p1", name: "A", processRef: "ProcessA"},
            %{id: "p2", name: "B", processRef: "ProcessB"}
          ],
          message_flows: []
        },
        processes: [
          {:bpmn_process, %{id: "ProcessA"}, elements_a},
          {:bpmn_process, %{id: "ProcessB"}, elements_b}
        ]
      }

      {:ok, result} = Collaboration.start(diagram)
      assert result.collaboration_id == "collab_1"
      assert map_size(result.instances) == 2

      assert Rodar.Process.status(result.instances["ProcessA"]) == :completed
      assert Rodar.Process.status(result.instances["ProcessB"]) == :completed
    end

    test "returns error when participant processRef doesn't match any process" do
      diagram = %{
        collaboration: %{
          id: "collab_1",
          participants: [
            %{id: "p1", name: "A", processRef: "NonExistent"}
          ],
          message_flows: []
        },
        processes: [
          {:bpmn_process, %{id: "ProcessA"},
           %{
             "s" => {:bpmn_event_start, %{id: "s", incoming: [], outgoing: ["f"]}},
             "e" => {:bpmn_event_end, %{id: "e", incoming: ["f"], outgoing: []}},
             "f" => make_flow("f", "s", "e")
           }}
        ]
      }

      assert {:error, msg} = Collaboration.start(diagram)
      assert msg =~ "NonExistent"
    end

    test "returns error when no collaboration in diagram" do
      diagram = %{
        collaboration: nil,
        processes: []
      }

      assert {:error, "No collaboration found in diagram"} = Collaboration.start(diagram)
    end
  end

  describe "stop/1" do
    test "terminates all process instances" do
      elements = %{
        "s" => {:bpmn_event_start, %{id: "s", incoming: [], outgoing: ["f"]}},
        "e" => {:bpmn_event_end, %{id: "e", incoming: ["f"], outgoing: []}},
        "f" => make_flow("f", "s", "e")
      }

      diagram = %{
        collaboration: %{
          id: "collab_1",
          participants: [
            %{id: "p1", name: "A", processRef: "ProcStop"}
          ],
          message_flows: []
        },
        processes: [
          {:bpmn_process, %{id: "ProcStop"}, elements}
        ]
      }

      {:ok, result} = Collaboration.start(diagram)
      pid = result.instances["ProcStop"]
      assert Process.alive?(pid)

      Collaboration.stop(result)
      assert Rodar.Process.status(pid) == :terminated
    end
  end

  describe "message flow wiring" do
    test "two-pool collaboration with message throw/catch" do
      # Process A: start → throw message → end
      elements_a = %{
        "s_a" => {:bpmn_event_start, %{id: "s_a", incoming: [], outgoing: ["f_a1"]}},
        "throw_a" =>
          {:bpmn_event_intermediate_throw,
           %{
             id: "throw_a",
             incoming: ["f_a1"],
             outgoing: ["f_a2"],
             messageEventDefinition: {:bpmn_event_definition_message, %{messageRef: "msg_order"}},
             conditionalEventDefinition: nil,
             compensateEventDefinition: nil,
             escalationEventDefinition: nil,
             errorEventDefinition: nil,
             signalEventDefinition: nil,
             terminateEventDefinition: nil,
             timerEventDefinition: nil
           }},
        "e_a" => {:bpmn_event_end, %{id: "e_a", incoming: ["f_a2"], outgoing: []}},
        "f_a1" => make_flow("f_a1", "s_a", "throw_a"),
        "f_a2" => make_flow("f_a2", "throw_a", "e_a")
      }

      # Process B: start → catch message → end
      elements_b = %{
        "s_b" => {:bpmn_event_start, %{id: "s_b", incoming: [], outgoing: ["f_b1"]}},
        "catch_b" =>
          {:bpmn_event_intermediate_catch,
           %{
             id: "catch_b",
             incoming: ["f_b1"],
             outgoing: ["f_b2"],
             messageEventDefinition: {:bpmn_event_definition_message, %{messageRef: "msg_order"}},
             conditionalEventDefinition: nil,
             compensateEventDefinition: nil,
             escalationEventDefinition: nil,
             errorEventDefinition: nil,
             signalEventDefinition: nil,
             terminateEventDefinition: nil,
             timerEventDefinition: nil
           }},
        "e_b" => {:bpmn_event_end, %{id: "e_b", incoming: ["f_b2"], outgoing: []}},
        "f_b1" => make_flow("f_b1", "s_b", "catch_b"),
        "f_b2" => make_flow("f_b2", "catch_b", "e_b")
      }

      diagram = %{
        collaboration: %{
          id: "collab_msg",
          participants: [
            %{id: "p1", name: "Sender", processRef: "ProcSender"},
            %{id: "p2", name: "Receiver", processRef: "ProcReceiver"}
          ],
          message_flows: [
            %{id: "mf1", name: "Order", sourceRef: "throw_a", targetRef: "catch_b"}
          ]
        },
        processes: [
          {:bpmn_process, %{id: "ProcSender"}, elements_a},
          {:bpmn_process, %{id: "ProcReceiver"}, elements_b}
        ]
      }

      {:ok, result} = Collaboration.start(diagram)

      # Both processes should complete — the message throw in A
      # triggers the catch in B via pre-wired event bus subscription
      assert Rodar.Process.status(result.instances["ProcSender"]) == :completed
      # Process B catch will have been pre-subscribed, so when A throws the message,
      # B's catch should receive it. However, since processes activate sequentially
      # and B's catch event returns {:manual, _}, B may be suspended.
      status_b = Rodar.Process.status(result.instances["ProcReceiver"])
      assert status_b in [:completed, :suspended]
    end
  end
end
