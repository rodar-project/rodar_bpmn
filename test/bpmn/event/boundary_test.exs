defmodule Bpmn.Event.BoundaryTest do
  use ExUnit.Case, async: true

  defp make_process do
    end_event = {:bpmn_event_end, %{id: "end", incoming: ["flow"], outgoing: []}}

    flow =
      {:bpmn_sequence_flow,
       %{
         id: "flow",
         sourceRef: "b1",
         targetRef: "end",
         conditionExpression: nil,
         isImmediate: nil
       }}

    %{"flow" => flow, "end" => end_event}
  end

  describe "error boundary event" do
    test "releases token to outgoing flows" do
      {:ok, context} = Bpmn.Context.start_link(make_process(), %{})

      elem =
        {:bpmn_event_boundary,
         %{
           id: "b1",
           outgoing: ["flow"],
           attachedToRef: "task1",
           errorEventDefinition: {:bpmn_event_definition_error, %{_elems: []}},
           messageEventDefinition: nil,
           signalEventDefinition: nil,
           timerEventDefinition: nil,
           escalationEventDefinition: nil
         }}

      assert {:ok, ^context} = Bpmn.Event.Boundary.token_in(elem, context)
    end
  end

  describe "message boundary event" do
    test "subscribes to event bus and returns manual" do
      {:ok, context} = Bpmn.Context.start_link(make_process(), %{})
      msg_name = "msg_boundary_#{:erlang.unique_integer()}"

      elem =
        {:bpmn_event_boundary,
         %{
           id: "b1",
           outgoing: ["flow"],
           attachedToRef: "task1",
           errorEventDefinition: nil,
           messageEventDefinition: {:bpmn_event_definition_message, %{messageRef: msg_name}},
           signalEventDefinition: nil,
           timerEventDefinition: nil,
           escalationEventDefinition: nil
         }}

      assert {:manual, task_data} = Bpmn.Event.Boundary.token_in(elem, context)
      assert task_data.type == :message_boundary
      assert task_data.event_name == msg_name
    end
  end

  describe "signal boundary event" do
    test "subscribes to event bus and returns manual" do
      {:ok, context} = Bpmn.Context.start_link(make_process(), %{})
      sig_name = "sig_boundary_#{:erlang.unique_integer()}"

      elem =
        {:bpmn_event_boundary,
         %{
           id: "b1",
           outgoing: ["flow"],
           attachedToRef: "task1",
           errorEventDefinition: nil,
           messageEventDefinition: nil,
           signalEventDefinition: {:bpmn_event_definition_signal, %{signalRef: sig_name}},
           timerEventDefinition: nil,
           escalationEventDefinition: nil
         }}

      assert {:manual, task_data} = Bpmn.Event.Boundary.token_in(elem, context)
      assert task_data.type == :signal_boundary
    end
  end

  describe "timer boundary event" do
    test "schedules timer and returns manual" do
      {:ok, context} = Bpmn.Context.start_link(make_process(), %{})

      elem =
        {:bpmn_event_boundary,
         %{
           id: "b1",
           outgoing: ["flow"],
           attachedToRef: "task1",
           errorEventDefinition: nil,
           messageEventDefinition: nil,
           signalEventDefinition: nil,
           timerEventDefinition: {:bpmn_event_definition_timer, %{timeDuration: "PT10S"}},
           escalationEventDefinition: nil
         }}

      assert {:manual, task_data} = Bpmn.Event.Boundary.token_in(elem, context)
      assert task_data.type == :timer_boundary
      assert task_data.duration_ms == 10_000

      # Cancel to avoid firing
      meta = Bpmn.Context.get_meta(context, "b1")
      Bpmn.Event.Timer.cancel(meta.timer_ref)
    end
  end

  describe "timer cycle boundary event" do
    test "schedules cycle timer and returns manual" do
      {:ok, context} = Bpmn.Context.start_link(make_process(), %{})

      elem =
        {:bpmn_event_boundary,
         %{
           id: "b_cycle",
           outgoing: ["flow"],
           attachedToRef: "task1",
           errorEventDefinition: nil,
           messageEventDefinition: nil,
           signalEventDefinition: nil,
           timerEventDefinition: {:bpmn_event_definition_timer, %{timeCycle: "R3/PT10S"}},
           escalationEventDefinition: nil
         }}

      assert {:manual, task_data} = Bpmn.Event.Boundary.token_in(elem, context)
      assert task_data.type == :timer_cycle_boundary
      assert task_data.duration_ms == 10_000
      assert task_data.repetitions == 3

      meta = Bpmn.Context.get_meta(context, "b_cycle")
      Bpmn.Event.Timer.cancel(meta.timer_ref)
    end
  end

  describe "escalation boundary event" do
    test "subscribes to event bus and returns manual" do
      {:ok, context} = Bpmn.Context.start_link(make_process(), %{})
      esc_code = "esc_boundary_#{:erlang.unique_integer()}"

      elem =
        {:bpmn_event_boundary,
         %{
           id: "b1",
           outgoing: ["flow"],
           attachedToRef: "task1",
           errorEventDefinition: nil,
           messageEventDefinition: nil,
           signalEventDefinition: nil,
           timerEventDefinition: nil,
           escalationEventDefinition:
             {:bpmn_event_definition_escalation, %{escalationRef: esc_code}}
         }}

      assert {:manual, task_data} = Bpmn.Event.Boundary.token_in(elem, context)
      assert task_data.type == :escalation_boundary
      assert task_data.event_name == esc_code
    end
  end

  describe "unsupported boundary event" do
    test "returns error" do
      {:ok, context} = Bpmn.Context.start_link(make_process(), %{})

      elem =
        {:bpmn_event_boundary,
         %{
           id: "b1",
           outgoing: ["flow"],
           attachedToRef: "task1",
           errorEventDefinition: nil,
           messageEventDefinition: nil,
           signalEventDefinition: nil,
           timerEventDefinition: nil,
           escalationEventDefinition: nil
         }}

      assert {:error, msg} = Bpmn.Event.Boundary.token_in(elem, context)
      assert msg =~ "unsupported event definition"
    end
  end
end
