defmodule Bpmn.Event.Boundary do
  @moduledoc """
  Handle passing the token through a boundary event element.

  Boundary events are attached to activities and can be triggered by
  various event types:

  - **Error** — activated directly by the parent activity on error
    (existing pattern in `Bpmn.Activity.Subprocess.Embedded`)
  - **Message** — subscribes to the event bus for a matching message
  - **Signal** — subscribes to the event bus for a matching signal
  - **Timer** — schedules a timer callback
  - **Escalation** — subscribes to the event bus for a matching escalation

  ## Examples

      iex> end_event = {:bpmn_event_end, %{id: "end", incoming: ["flow"], outgoing: []}}
      iex> flow = {:bpmn_sequence_flow, %{id: "flow", sourceRef: "b1", targetRef: "end", conditionExpression: nil, isImmediate: nil}}
      iex> process = %{"flow" => flow, "end" => end_event}
      iex> {:ok, context} = Bpmn.Context.start_link(process, %{})
      iex> elem = {:bpmn_event_boundary, %{id: "b1", outgoing: ["flow"], attachedToRef: "task1", errorEventDefinition: {:bpmn_event_definition_error, %{_elems: []}}, messageEventDefinition: nil, signalEventDefinition: nil, timerEventDefinition: nil, escalationEventDefinition: nil}}
      iex> {:ok, ^context} = Bpmn.Event.Boundary.token_in(elem, context)
      iex> true
      true

  """

  @doc """
  Receive the token for the element and handle the boundary event.
  """
  @spec token_in(Bpmn.element(), Bpmn.context()) :: Bpmn.result()
  def token_in({:bpmn_event_boundary, %{id: id, outgoing: outgoing} = attrs}, context) do
    cond do
      has_error?(attrs) ->
        handle_error_boundary(id, outgoing, context)

      has_message?(attrs) ->
        handle_message_boundary(id, attrs, outgoing, context)

      has_signal?(attrs) ->
        handle_signal_boundary(id, attrs, outgoing, context)

      has_timer?(attrs) ->
        handle_timer_boundary(id, attrs, outgoing, context)

      has_escalation?(attrs) ->
        handle_escalation_boundary(id, attrs, outgoing, context)

      true ->
        {:error, "Boundary event '#{id}': unsupported event definition"}
    end
  end

  defp has_error?(attrs) do
    match?({:bpmn_event_definition_error, _}, Map.get(attrs, :errorEventDefinition))
  end

  defp has_message?(attrs) do
    match?({:bpmn_event_definition_message, _}, Map.get(attrs, :messageEventDefinition))
  end

  defp has_signal?(attrs) do
    match?({:bpmn_event_definition_signal, _}, Map.get(attrs, :signalEventDefinition))
  end

  defp has_timer?(attrs) do
    match?({:bpmn_event_definition_timer, _}, Map.get(attrs, :timerEventDefinition))
  end

  defp has_escalation?(attrs) do
    match?({:bpmn_event_definition_escalation, _}, Map.get(attrs, :escalationEventDefinition))
  end

  # Error boundaries are activated directly by the parent activity
  defp handle_error_boundary(_id, outgoing, context) do
    Bpmn.release_token(outgoing, context)
  end

  defp handle_message_boundary(id, attrs, outgoing, context) do
    {:bpmn_event_definition_message, def_attrs} = attrs.messageEventDefinition
    message_name = Map.get(def_attrs, :messageRef, id)

    Bpmn.Context.put_meta(context, id, %{active: true, completed: false, type: :boundary_event})

    Bpmn.Event.Bus.subscribe(:message, message_name, %{
      context: context,
      node_id: id,
      outgoing: outgoing
    })

    {:manual, %{id: id, type: :message_boundary, event_name: message_name, context: context}}
  end

  defp handle_signal_boundary(id, attrs, outgoing, context) do
    {:bpmn_event_definition_signal, def_attrs} = attrs.signalEventDefinition
    signal_name = Map.get(def_attrs, :signalRef, id)

    Bpmn.Context.put_meta(context, id, %{active: true, completed: false, type: :boundary_event})

    Bpmn.Event.Bus.subscribe(:signal, signal_name, %{
      context: context,
      node_id: id,
      outgoing: outgoing
    })

    {:manual, %{id: id, type: :signal_boundary, event_name: signal_name, context: context}}
  end

  defp handle_timer_boundary(id, attrs, outgoing, context) do
    {:bpmn_event_definition_timer, def_attrs} = attrs.timerEventDefinition

    Bpmn.Context.put_meta(context, id, %{active: true, completed: false, type: :boundary_event})

    if Map.has_key?(def_attrs, :timeCycle) do
      schedule_boundary_cycle(id, def_attrs.timeCycle, outgoing, context)
    else
      schedule_boundary_duration(id, Map.get(def_attrs, :timeDuration), outgoing, context)
    end
  end

  defp schedule_boundary_duration(id, duration, outgoing, context) when is_binary(duration) do
    case Bpmn.Event.Timer.parse_duration(duration) do
      {:ok, ms} ->
        timer_ref = Bpmn.Event.Timer.schedule(ms, context, id, outgoing)

        Bpmn.Context.put_meta(context, id, %{
          active: true,
          completed: false,
          type: :boundary_event,
          timer_ref: timer_ref
        })

        {:manual, %{id: id, type: :timer_boundary, duration_ms: ms, context: context}}

      {:error, reason} ->
        {:error, "Boundary event '#{id}': invalid timer duration — #{reason}"}
    end
  end

  defp schedule_boundary_duration(id, _other, _outgoing, context) do
    {:manual, %{id: id, type: :timer_boundary, context: context}}
  end

  defp schedule_boundary_cycle(id, cycle_expr, outgoing, context) do
    case Bpmn.Event.Timer.parse_cycle(cycle_expr) do
      {:ok, %{repetitions: reps, duration_ms: ms}} ->
        timer_ref = Bpmn.Event.Timer.schedule_cycle(ms, context, id, outgoing, reps)

        Bpmn.Context.put_meta(context, id, %{
          active: true,
          completed: false,
          type: :boundary_event,
          timer_ref: timer_ref
        })

        {:manual,
         %{
           id: id,
           type: :timer_cycle_boundary,
           duration_ms: ms,
           repetitions: reps,
           context: context
         }}

      {:error, reason} ->
        {:error, "Boundary event '#{id}': invalid timer cycle — #{reason}"}
    end
  end

  defp handle_escalation_boundary(id, attrs, outgoing, context) do
    {:bpmn_event_definition_escalation, def_attrs} = attrs.escalationEventDefinition
    escalation_code = Map.get(def_attrs, :escalationRef, id)

    Bpmn.Context.put_meta(context, id, %{active: true, completed: false, type: :boundary_event})

    Bpmn.Event.Bus.subscribe(:escalation, escalation_code, %{
      context: context,
      node_id: id,
      outgoing: outgoing
    })

    {:manual,
     %{id: id, type: :escalation_boundary, event_name: escalation_code, context: context}}
  end
end
