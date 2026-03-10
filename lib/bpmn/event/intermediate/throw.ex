defmodule Bpmn.Event.Intermediate.Throw do
  @moduledoc """
  Handle passing the token through an intermediate throw event element.

  Intermediate throw events emit events (messages, signals, escalations) to the
  event bus and then release the token to outgoing flows. Events without a
  specific definition (none/link) pass through immediately.

  ## Examples

      iex> end_event = {:bpmn_event_end, %{id: "end", incoming: ["flow_out"], outgoing: []}}
      iex> flow_out = {:bpmn_sequence_flow, %{id: "flow_out", sourceRef: "throw1", targetRef: "end", conditionExpression: nil, isImmediate: nil}}
      iex> process = %{"flow_out" => flow_out, "end" => end_event}
      iex> {:ok, context} = Bpmn.Context.start_link(process, %{})
      iex> elem = {:bpmn_event_intermediate_throw, %{id: "throw1", outgoing: ["flow_out"], messageEventDefinition: nil, signalEventDefinition: nil, escalationEventDefinition: nil}}
      iex> {:ok, ^context} = Bpmn.Event.Intermediate.Throw.token_in(elem, context)
      iex> true
      true

  """

  alias Bpmn.Compensation
  alias Bpmn.Context
  alias Bpmn.Event.Bus

  @doc """
  Receive the token for the element and handle the throw event.
  """
  @spec token_in(Bpmn.element(), Bpmn.context()) :: Bpmn.result()
  def token_in({:bpmn_event_intermediate_throw, %{id: id, outgoing: outgoing} = attrs}, context) do
    cond do
      has_message?(attrs) ->
        publish_message(id, attrs, context)
        Bpmn.release_token(outgoing, context)

      has_signal?(attrs) ->
        publish_signal(id, attrs, context)
        Bpmn.release_token(outgoing, context)

      has_escalation?(attrs) ->
        publish_escalation(id, attrs, context)
        Bpmn.release_token(outgoing, context)

      has_compensate?(attrs) ->
        handle_compensate(attrs, outgoing, context)

      true ->
        # None/link — pass through
        Bpmn.release_token(outgoing, context)
    end
  end

  defp has_message?(attrs) do
    match?({:bpmn_event_definition_message, _}, Map.get(attrs, :messageEventDefinition))
  end

  defp has_signal?(attrs) do
    match?({:bpmn_event_definition_signal, _}, Map.get(attrs, :signalEventDefinition))
  end

  defp has_escalation?(attrs) do
    match?({:bpmn_event_definition_escalation, _}, Map.get(attrs, :escalationEventDefinition))
  end

  defp publish_message(id, attrs, context) do
    {:bpmn_event_definition_message, def_attrs} = attrs.messageEventDefinition
    message_name = Map.get(def_attrs, :messageRef, id)
    data = Context.get(context, :data)
    payload = %{source: id, data: data}
    payload = put_correlation(payload, def_attrs, context)
    Bus.publish(:message, message_name, payload)
  end

  defp publish_signal(id, attrs, context) do
    {:bpmn_event_definition_signal, def_attrs} = attrs.signalEventDefinition
    signal_name = Map.get(def_attrs, :signalRef, id)
    data = Context.get(context, :data)
    Bus.publish(:signal, signal_name, %{source: id, data: data})
  end

  defp has_compensate?(attrs) do
    match?({:bpmn_event_definition_compensate, _}, Map.get(attrs, :compensateEventDefinition))
  end

  defp handle_compensate(attrs, outgoing, context) do
    {:bpmn_event_definition_compensate, def_attrs} = attrs.compensateEventDefinition
    activity_ref = Map.get(def_attrs, :activityRef)
    wait = Map.get(def_attrs, :waitForCompletion, "true")

    run_compensation = fn ->
      if activity_ref do
        Compensation.compensate_activity(context, to_string(activity_ref))
      else
        Compensation.compensate_all(context)
      end
    end

    if wait == "false" do
      spawn(run_compensation)
      Bpmn.release_token(outgoing, context)
    else
      run_compensation.()
      Bpmn.release_token(outgoing, context)
    end
  end

  defp put_correlation(payload, def_attrs, context) do
    case Map.get(def_attrs, :correlationKey) do
      nil ->
        payload

      key ->
        data = Context.get(context, :data)
        Map.put(payload, :correlation, %{key: key, value: Map.get(data, key)})
    end
  end

  defp publish_escalation(id, attrs, context) do
    {:bpmn_event_definition_escalation, def_attrs} = attrs.escalationEventDefinition
    escalation_code = Map.get(def_attrs, :escalationRef, id)
    data = Context.get(context, :data)
    Bus.publish(:escalation, escalation_code, %{source: id, data: data})
  end
end
