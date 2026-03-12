defmodule Rodar.IntegrationTest do
  use ExUnit.Case, async: true

  alias Rodar.{
    Activity.Task.Send,
    Context,
    Engine.Diagram,
    Event.Bus,
    Event.End,
    Event.Intermediate.Catch,
    Event.Intermediate.Throw,
    Event.Start
  }

  @moduledoc """
  End-to-end integration test that loads a BPMN file through the parser
  and executes it through the engine.
  """

  describe "user_login.bpmn" do
    setup do
      diagram = Diagram.load(File.read!("./priv/bpmn/examples/user_login.bpmn"))
      {:ok, diagram: diagram}
    end

    test "parses the BPMN file into a diagram map", %{diagram: diagram} do
      assert is_map(diagram)
      assert Map.has_key?(diagram, :processes)
      assert Map.has_key?(diagram, :id)
      assert is_list(diagram.processes)
      assert length(diagram.processes) == 1
    end

    test "process contains expected elements", %{diagram: diagram} do
      [{:bpmn_process, attrs, elements}] = diagram.processes

      assert attrs[:id] == "user-login"
      assert attrs[:name] == "Login"

      # Verify start event exists
      start_event = elements["StartEvent_1"]
      assert {:bpmn_event_start, %{outgoing: ["SequenceFlow_0u2ggjm"]}} = start_event

      # Verify end events exist
      assert {:bpmn_event_end, _} = elements["EndEvent_1s3wrav"]
      assert {:bpmn_event_end, _} = elements["EndEvent_0y3z10o"]

      # Verify sequence flows exist
      assert {:bpmn_sequence_flow, %{sourceRef: "StartEvent_1", targetRef: "Task_1ymg9vn"}} =
               elements["SequenceFlow_0u2ggjm"]

      # Verify gateway
      assert {:bpmn_gateway_exclusive, %{incoming: ["SequenceFlow_1i6wlcd"]}} =
               elements["ExclusiveGateway_1eglp8f"]

      # Verify tasks with correct type tags
      assert {:bpmn_activity_task_script, _} = elements["Task_1ymg9vn"]
      assert {:bpmn_activity_task_script, _} = elements["Task_0iy3d09"]
      assert {:bpmn_activity_task_service, _} = elements["Task_1y7eqry"]
    end

    test "executes start event through sequence flow to first task", %{diagram: diagram} do
      [{:bpmn_process, _attrs, elements}] = diagram.processes

      # Create context with the process elements
      {:ok, context} =
        Context.start_link(elements, %{"username" => "test", "password" => "secret"})

      # Find and execute the start event
      {:bpmn_event_start, _} = start_event = elements["StartEvent_1"]

      # The start event should flow through the sequence flow to the script task,
      # which returns {:not_implemented} since it's a stub
      result = Start.token_in(start_event, context)
      assert {:not_implemented} = result
    end

    test "end event completes the process" do
      {:ok, context} = Context.start_link(%{}, %{})
      end_event = {:bpmn_event_end, %{incoming: ["some_flow"]}}

      assert {:ok, ^context} = End.token_in(end_event, context)
    end

    test "full dispatch through Rodar.execute/2", %{diagram: diagram} do
      [{:bpmn_process, _attrs, elements}] = diagram.processes

      {:ok, context} = Context.start_link(elements, %{})

      # Execute start event through the main dispatcher
      start_event = elements["StartEvent_1"]
      result = Rodar.execute(start_event, context)

      # Should reach the script task stub and return {:not_implemented}
      assert {:not_implemented} = result
    end
  end

  describe "event bus: send task → catch event → end" do
    test "send task publishes message that auto-resumes catch event via event bus" do
      # Build process: start → send_task → catch_event → end
      # The send task publishes a message, the catch event subscribes and is
      # auto-resumed via the event bus when the message arrives.

      end_event = {:bpmn_event_end, %{id: "end", incoming: ["f3"], outgoing: []}}

      f1 =
        {:bpmn_sequence_flow,
         %{
           id: "f1",
           sourceRef: "start",
           targetRef: "send",
           conditionExpression: nil,
           isImmediate: nil
         }}

      f2 =
        {:bpmn_sequence_flow,
         %{
           id: "f2",
           sourceRef: "send",
           targetRef: "end",
           conditionExpression: nil,
           isImmediate: nil
         }}

      f3 =
        {:bpmn_sequence_flow,
         %{
           id: "f3",
           sourceRef: "catch",
           targetRef: "end",
           conditionExpression: nil,
           isImmediate: nil
         }}

      start = {:bpmn_event_start, %{id: "start", incoming: [], outgoing: ["f1"]}}

      msg_name = "integration_msg_#{:erlang.unique_integer()}"

      send_task =
        {:bpmn_activity_task_send,
         %{id: "send", name: "Send Order", outgoing: ["f2"], messageRef: msg_name}}

      catch_event =
        {:bpmn_event_intermediate_catch,
         %{
           id: "catch",
           outgoing: ["f3"],
           messageEventDefinition: {:bpmn_event_definition_message, %{messageRef: msg_name}},
           signalEventDefinition: nil,
           timerEventDefinition: nil
         }}

      process = %{
        "start" => start,
        "f1" => f1,
        "send" => send_task,
        "f2" => f2,
        "catch" => catch_event,
        "f3" => f3,
        "end" => end_event
      }

      {:ok, context} = Context.start_link(process, %{})

      # First, subscribe the catch event
      {:manual, _} = Catch.token_in(catch_event, context)

      # Now execute the send task — it should publish and auto-deliver
      {:ok, ^context} = Send.token_in(send_task, context)

      # Verify the catch event subscription was consumed
      assert Bus.subscriptions(:message, msg_name) == []
    end
  end

  describe "signal broadcast integration" do
    test "signal throw broadcasts to multiple catch events" do
      sig_name = "integration_sig_#{:erlang.unique_integer()}"

      {:ok, ctx1} = Context.start_link(%{}, %{})
      {:ok, ctx2} = Context.start_link(%{}, %{})

      # Two catch events subscribe to same signal
      catch1 =
        {:bpmn_event_intermediate_catch,
         %{
           id: "catch1",
           outgoing: ["f1"],
           messageEventDefinition: nil,
           signalEventDefinition: {:bpmn_event_definition_signal, %{signalRef: sig_name}},
           timerEventDefinition: nil
         }}

      catch2 =
        {:bpmn_event_intermediate_catch,
         %{
           id: "catch2",
           outgoing: ["f2"],
           messageEventDefinition: nil,
           signalEventDefinition: {:bpmn_event_definition_signal, %{signalRef: sig_name}},
           timerEventDefinition: nil
         }}

      {:manual, _} = Catch.token_in(catch1, ctx1)
      {:manual, _} = Catch.token_in(catch2, ctx2)

      # Verify both subscriptions exist
      subs = Bus.subscriptions(:signal, sig_name)
      assert length(subs) == 2

      # Throw signal — should broadcast to both
      end_event = {:bpmn_event_end, %{id: "end", incoming: ["f_out"], outgoing: []}}

      f_out =
        {:bpmn_sequence_flow,
         %{
           id: "f_out",
           sourceRef: "throw1",
           targetRef: "end",
           conditionExpression: nil,
           isImmediate: nil
         }}

      {:ok, throw_ctx} = Context.start_link(%{"f_out" => f_out, "end" => end_event}, %{})

      throw_event =
        {:bpmn_event_intermediate_throw,
         %{
           id: "throw1",
           outgoing: ["f_out"],
           messageEventDefinition: nil,
           signalEventDefinition: {:bpmn_event_definition_signal, %{signalRef: sig_name}},
           escalationEventDefinition: nil
         }}

      assert {:ok, _} = Throw.token_in(throw_event, throw_ctx)
    end
  end

  describe "simple start-to-end flow" do
    test "executes a minimal process from start to end" do
      # Build a minimal process: start → sequence_flow → end
      end_event = {:bpmn_event_end, %{id: "end_1", incoming: ["flow_1"], outgoing: []}}

      seq_flow =
        {:bpmn_sequence_flow,
         %{
           id: "flow_1",
           name: "",
           sourceRef: "start_1",
           targetRef: "end_1",
           conditionExpression: nil,
           isImmediate: nil
         }}

      start_event = {:bpmn_event_start, %{id: "start_1", outgoing: ["flow_1"]}}

      process = %{
        "start_1" => start_event,
        "flow_1" => seq_flow,
        "end_1" => end_event
      }

      {:ok, context} = Context.start_link(process, %{"key" => "value"})

      # Execute the full flow
      result = Rodar.execute(start_event, context)
      assert {:ok, ^context} = result

      # Verify initial data is preserved
      assert Context.get(context, :init) == %{"key" => "value"}
    end
  end
end
