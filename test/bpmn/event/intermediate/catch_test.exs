defmodule Bpmn.Event.Intermediate.CatchTest do
  use ExUnit.Case, async: true

  describe "message catch event" do
    test "subscribes to event bus and returns manual" do
      {:ok, context} = Bpmn.Context.start_link(%{}, %{})
      msg_name = "msg_catch_#{:erlang.unique_integer()}"

      elem =
        {:bpmn_event_intermediate_catch,
         %{
           id: "catch1",
           outgoing: ["flow_out"],
           messageEventDefinition: {:bpmn_event_definition_message, %{messageRef: msg_name}},
           signalEventDefinition: nil,
           timerEventDefinition: nil
         }}

      assert {:manual, task_data} = Bpmn.Event.Intermediate.Catch.token_in(elem, context)
      assert task_data.id == "catch1"
      assert task_data.type == :message_catch
      assert task_data.event_name == msg_name

      # Verify subscription exists
      subs = Bpmn.Event.Bus.subscriptions(:message, msg_name)
      assert length(subs) == 1
    end
  end

  describe "signal catch event" do
    test "subscribes to event bus and returns manual" do
      {:ok, context} = Bpmn.Context.start_link(%{}, %{})
      sig_name = "sig_catch_#{:erlang.unique_integer()}"

      elem =
        {:bpmn_event_intermediate_catch,
         %{
           id: "catch1",
           outgoing: ["flow_out"],
           messageEventDefinition: nil,
           signalEventDefinition: {:bpmn_event_definition_signal, %{signalRef: sig_name}},
           timerEventDefinition: nil
         }}

      assert {:manual, task_data} = Bpmn.Event.Intermediate.Catch.token_in(elem, context)
      assert task_data.type == :signal_catch
      assert task_data.event_name == sig_name
    end
  end

  describe "timer catch event" do
    test "returns manual with timer info for valid duration" do
      {:ok, context} = Bpmn.Context.start_link(%{}, %{})

      elem =
        {:bpmn_event_intermediate_catch,
         %{
           id: "catch1",
           outgoing: ["flow_out"],
           messageEventDefinition: nil,
           signalEventDefinition: nil,
           timerEventDefinition: {:bpmn_event_definition_timer, %{timeDuration: "PT5S"}}
         }}

      assert {:manual, task_data} = Bpmn.Event.Intermediate.Catch.token_in(elem, context)
      assert task_data.type == :timer_catch
      assert task_data.duration_ms == 5_000

      # Cancel the timer to avoid it firing in tests
      meta = Bpmn.Context.get_meta(context, "catch1")
      Bpmn.Event.Timer.cancel(meta.timer_ref)
    end

    test "returns error for invalid duration" do
      {:ok, context} = Bpmn.Context.start_link(%{}, %{})

      elem =
        {:bpmn_event_intermediate_catch,
         %{
           id: "catch1",
           outgoing: ["flow_out"],
           messageEventDefinition: nil,
           signalEventDefinition: nil,
           timerEventDefinition: {:bpmn_event_definition_timer, %{timeDuration: "invalid"}}
         }}

      assert {:error, msg} = Bpmn.Event.Intermediate.Catch.token_in(elem, context)
      assert msg =~ "invalid timer duration"
    end

    test "returns manual without duration when timeDuration is nil" do
      {:ok, context} = Bpmn.Context.start_link(%{}, %{})

      elem =
        {:bpmn_event_intermediate_catch,
         %{
           id: "catch1",
           outgoing: ["flow_out"],
           messageEventDefinition: nil,
           signalEventDefinition: nil,
           timerEventDefinition: {:bpmn_event_definition_timer, %{}}
         }}

      assert {:manual, task_data} = Bpmn.Event.Intermediate.Catch.token_in(elem, context)
      assert task_data.type == :timer_catch
      refute Map.has_key?(task_data, :duration_ms)
    end
  end

  describe "timer cycle catch event" do
    test "returns manual with cycle info for valid cycle" do
      {:ok, context} = Bpmn.Context.start_link(%{}, %{})

      elem =
        {:bpmn_event_intermediate_catch,
         %{
           id: "catch_cycle",
           outgoing: ["flow_out"],
           messageEventDefinition: nil,
           signalEventDefinition: nil,
           timerEventDefinition: {:bpmn_event_definition_timer, %{timeCycle: "R3/PT10S"}}
         }}

      assert {:manual, task_data} = Bpmn.Event.Intermediate.Catch.token_in(elem, context)
      assert task_data.type == :timer_cycle_catch
      assert task_data.duration_ms == 10_000
      assert task_data.repetitions == 3

      meta = Bpmn.Context.get_meta(context, "catch_cycle")
      Bpmn.Event.Timer.cancel(meta.timer_ref)
    end

    test "returns manual with infinite cycle for bare duration" do
      {:ok, context} = Bpmn.Context.start_link(%{}, %{})

      elem =
        {:bpmn_event_intermediate_catch,
         %{
           id: "catch_cycle2",
           outgoing: ["flow_out"],
           messageEventDefinition: nil,
           signalEventDefinition: nil,
           timerEventDefinition: {:bpmn_event_definition_timer, %{timeCycle: "PT5S"}}
         }}

      assert {:manual, task_data} = Bpmn.Event.Intermediate.Catch.token_in(elem, context)
      assert task_data.type == :timer_cycle_catch
      assert task_data.repetitions == :infinite

      meta = Bpmn.Context.get_meta(context, "catch_cycle2")
      Bpmn.Event.Timer.cancel(meta.timer_ref)
    end

    test "returns error for invalid cycle expression" do
      {:ok, context} = Bpmn.Context.start_link(%{}, %{})

      elem =
        {:bpmn_event_intermediate_catch,
         %{
           id: "catch_cycle3",
           outgoing: ["flow_out"],
           messageEventDefinition: nil,
           signalEventDefinition: nil,
           timerEventDefinition: {:bpmn_event_definition_timer, %{timeCycle: "R3/invalid"}}
         }}

      assert {:error, msg} = Bpmn.Event.Intermediate.Catch.token_in(elem, context)
      assert msg =~ "invalid timer cycle"
    end

    test "timeCycle takes priority over timeDuration" do
      {:ok, context} = Bpmn.Context.start_link(%{}, %{})

      elem =
        {:bpmn_event_intermediate_catch,
         %{
           id: "catch_both",
           outgoing: ["flow_out"],
           messageEventDefinition: nil,
           signalEventDefinition: nil,
           timerEventDefinition:
             {:bpmn_event_definition_timer, %{timeCycle: "R2/PT1S", timeDuration: "PT5S"}}
         }}

      assert {:manual, task_data} = Bpmn.Event.Intermediate.Catch.token_in(elem, context)
      assert task_data.type == :timer_cycle_catch
      assert task_data.repetitions == 2

      meta = Bpmn.Context.get_meta(context, "catch_both")
      Bpmn.Event.Timer.cancel(meta.timer_ref)
    end
  end

  describe "unsupported catch event" do
    test "returns error for catch event without known definition" do
      {:ok, context} = Bpmn.Context.start_link(%{}, %{})

      elem =
        {:bpmn_event_intermediate_catch,
         %{
           id: "catch1",
           outgoing: ["flow_out"],
           messageEventDefinition: nil,
           signalEventDefinition: nil,
           timerEventDefinition: nil
         }}

      assert {:error, msg} = Bpmn.Event.Intermediate.Catch.token_in(elem, context)
      assert msg =~ "unsupported event definition"
    end
  end

  describe "resume/3" do
    test "merges input data and releases token" do
      end_event = {:bpmn_event_end, %{id: "end", incoming: ["flow_out"], outgoing: []}}

      flow_out =
        {:bpmn_sequence_flow,
         %{
           id: "flow_out",
           sourceRef: "catch1",
           targetRef: "end",
           conditionExpression: nil,
           isImmediate: nil
         }}

      process = %{"flow_out" => flow_out, "end" => end_event}
      {:ok, context} = Bpmn.Context.start_link(process, %{})

      elem =
        {:bpmn_event_intermediate_catch, %{id: "catch1", outgoing: ["flow_out"]}}

      assert {:ok, ^context} =
               Bpmn.Event.Intermediate.Catch.resume(elem, context, %{"key" => "value"})

      assert Bpmn.Context.get_data(context, "key") == "value"
    end
  end

  describe "dispatch via Bpmn.execute/2" do
    test "dispatches intermediate catch events correctly" do
      {:ok, context} = Bpmn.Context.start_link(%{}, %{})
      msg_name = "msg_dispatch_#{:erlang.unique_integer()}"

      elem =
        {:bpmn_event_intermediate_catch,
         %{
           id: "catch1",
           outgoing: ["flow_out"],
           messageEventDefinition: {:bpmn_event_definition_message, %{messageRef: msg_name}},
           signalEventDefinition: nil,
           timerEventDefinition: nil
         }}

      assert {:manual, _} = Bpmn.execute(elem, context)
    end
  end
end
