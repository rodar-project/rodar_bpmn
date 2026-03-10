defmodule Bpmn.Event.Intermediate.Catch do
  @moduledoc """
  Handle passing the token through an intermediate catch event element.

  Intermediate catch events pause execution and subscribe to the event bus,
  waiting for a matching event (message, signal, or timer) before releasing
  the token to outgoing flows.

  ## Examples

      iex> {:ok, context} = Bpmn.Context.start_link(%{}, %{})
      iex> elem = {:bpmn_event_intermediate_catch, %{id: "catch1", outgoing: ["flow_out"], messageEventDefinition: {:bpmn_event_definition_message, %{messageRef: "msg1"}}, signalEventDefinition: nil, timerEventDefinition: nil}}
      iex> {:manual, task_data} = Bpmn.Event.Intermediate.Catch.token_in(elem, context)
      iex> task_data.id
      "catch1"

  """

  @doc """
  Receive the token for the element and handle the catch event.
  """
  @spec token_in(Bpmn.element(), Bpmn.context()) :: Bpmn.result()
  def token_in({:bpmn_event_intermediate_catch, %{id: id, outgoing: outgoing} = attrs}, context) do
    cond do
      has_message?(attrs) ->
        subscribe_message(id, attrs, outgoing, context)

      has_signal?(attrs) ->
        subscribe_signal(id, attrs, outgoing, context)

      has_timer?(attrs) ->
        handle_timer(id, attrs, outgoing, context)

      true ->
        {:error, "Catch event '#{id}': unsupported event definition"}
    end
  end

  @doc """
  Resume execution of a paused catch event with the provided data.
  """
  @spec resume(Bpmn.element(), Bpmn.context(), map()) :: Bpmn.result()
  def resume({:bpmn_event_intermediate_catch, %{id: id, outgoing: outgoing}}, context, input)
      when is_map(input) do
    Enum.each(input, fn {key, value} ->
      Bpmn.Context.put_data(context, key, value)
    end)

    Bpmn.Context.put_meta(context, id, %{active: false, completed: true, type: :catch_event})
    Bpmn.release_token(outgoing, context)
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

  defp subscribe_message(id, attrs, outgoing, context) do
    {:bpmn_event_definition_message, def_attrs} = attrs.messageEventDefinition
    message_name = Map.get(def_attrs, :messageRef, id)

    Bpmn.Context.put_meta(context, id, %{active: true, completed: false, type: :catch_event})

    Bpmn.Event.Bus.subscribe(:message, message_name, %{
      context: context,
      node_id: id,
      outgoing: outgoing
    })

    {:manual,
     %{
       id: id,
       type: :message_catch,
       event_name: message_name,
       outgoing: outgoing,
       context: context
     }}
  end

  defp subscribe_signal(id, attrs, outgoing, context) do
    {:bpmn_event_definition_signal, def_attrs} = attrs.signalEventDefinition
    signal_name = Map.get(def_attrs, :signalRef, id)

    Bpmn.Context.put_meta(context, id, %{active: true, completed: false, type: :catch_event})

    Bpmn.Event.Bus.subscribe(:signal, signal_name, %{
      context: context,
      node_id: id,
      outgoing: outgoing
    })

    {:manual,
     %{id: id, type: :signal_catch, event_name: signal_name, outgoing: outgoing, context: context}}
  end

  defp handle_timer(id, attrs, outgoing, context) do
    {:bpmn_event_definition_timer, def_attrs} = attrs.timerEventDefinition

    Bpmn.Context.put_meta(context, id, %{active: true, completed: false, type: :catch_event})

    cond do
      Map.has_key?(def_attrs, :timeCycle) ->
        schedule_cycle_timer(id, def_attrs.timeCycle, outgoing, context)

      Map.has_key?(def_attrs, :timeDuration) ->
        schedule_duration_timer(id, def_attrs.timeDuration, outgoing, context)

      true ->
        {:manual, %{id: id, type: :timer_catch, outgoing: outgoing, context: context}}
    end
  end

  defp schedule_duration_timer(id, nil, outgoing, context) do
    {:manual, %{id: id, type: :timer_catch, outgoing: outgoing, context: context}}
  end

  defp schedule_duration_timer(id, duration, outgoing, context) when is_binary(duration) do
    case Bpmn.Event.Timer.parse_duration(duration) do
      {:ok, ms} ->
        timer_ref = Bpmn.Event.Timer.schedule(ms, context, id, outgoing)

        Bpmn.Context.put_meta(context, id, %{
          active: true,
          completed: false,
          type: :catch_event,
          timer_ref: timer_ref
        })

        {:manual,
         %{id: id, type: :timer_catch, duration_ms: ms, outgoing: outgoing, context: context}}

      {:error, reason} ->
        {:error, "Catch event '#{id}': invalid timer duration — #{reason}"}
    end
  end

  defp schedule_duration_timer(id, _other, outgoing, context) do
    {:manual, %{id: id, type: :timer_catch, outgoing: outgoing, context: context}}
  end

  defp schedule_cycle_timer(id, cycle_expr, outgoing, context) do
    case Bpmn.Event.Timer.parse_cycle(cycle_expr) do
      {:ok, %{repetitions: reps, duration_ms: ms}} ->
        timer_ref = Bpmn.Event.Timer.schedule_cycle(ms, context, id, outgoing, reps)

        Bpmn.Context.put_meta(context, id, %{
          active: true,
          completed: false,
          type: :catch_event,
          timer_ref: timer_ref
        })

        {:manual,
         %{
           id: id,
           type: :timer_cycle_catch,
           duration_ms: ms,
           repetitions: reps,
           outgoing: outgoing,
           context: context
         }}

      {:error, reason} ->
        {:error, "Catch event '#{id}': invalid timer cycle — #{reason}"}
    end
  end
end
