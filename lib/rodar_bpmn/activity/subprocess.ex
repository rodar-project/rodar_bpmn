defmodule RodarBpmn.Activity.Subprocess do
  @moduledoc """
  Handle passing the token through a call activity (subprocess) element.

  A call activity invokes an external process definition looked up from the
  `RodarBpmn.Registry`. It executes the referenced process in a child context,
  then merges results back and releases the token to outgoing flows.

  ## Examples

      iex> start = {:bpmn_event_start, %{id: "s", incoming: [], outgoing: ["f1"]}}
      iex> sub_end = {:bpmn_event_end, %{id: "e", incoming: ["f1"], outgoing: []}}
      iex> f1 = {:bpmn_sequence_flow, %{id: "f1", sourceRef: "s", targetRef: "e", conditionExpression: nil, isImmediate: nil}}
      iex> child_elements = %{"s" => start, "e" => sub_end, "f1" => f1}
      iex> RodarBpmn.Registry.register("child_proc", {:bpmn_process, %{id: "child_proc"}, child_elements})
      iex> outer_end = {:bpmn_event_end, %{id: "end", incoming: ["flow_out"], outgoing: []}}
      iex> flow_out = {:bpmn_sequence_flow, %{id: "flow_out", sourceRef: "call1", targetRef: "end", conditionExpression: nil, isImmediate: nil}}
      iex> process = %{"flow_out" => flow_out, "end" => outer_end}
      iex> {:ok, context} = RodarBpmn.Context.start_link(process, %{})
      iex> elem = {:bpmn_activity_subprocess, %{id: "call1", calledElement: "child_proc", outgoing: ["flow_out"]}}
      iex> {:ok, ^context} = RodarBpmn.Activity.Subprocess.token_in(elem, context)
      iex> RodarBpmn.Registry.unregister("child_proc")
      iex> true
      true

  """

  @doc """
  Receive the token for the element and execute the call activity.
  """
  @spec token_in(RodarBpmn.element(), RodarBpmn.context()) :: RodarBpmn.result()
  def token_in(
        {:bpmn_activity_subprocess, %{id: id, calledElement: process_id, outgoing: outgoing}},
        context
      ) do
    with {:ok, {:bpmn_process, _attrs, elements}} <- lookup_process(process_id, id),
         {:ok, start_event} <- find_start_event(elements, id, process_id) do
      execute_child(id, elements, start_event, outgoing, context)
    end
  end

  # Fallback for subprocess elements without calledElement (legacy stub)
  def token_in(_elem, _context), do: {:not_implemented}

  defp lookup_process(process_id, call_id) do
    case RodarBpmn.Registry.lookup(process_id) do
      {:ok, {:bpmn_process, _, _}} = result ->
        result

      {:ok, _} ->
        {:error, "Call activity '#{call_id}': invalid process definition for '#{process_id}'"}

      :error ->
        {:error, "Call activity '#{call_id}': process '#{process_id}' not found in registry"}
    end
  end

  defp find_start_event(elements, call_id, process_id) do
    case Enum.find_value(elements, fn
           {_id, {:bpmn_event_start, _} = elem} -> elem
           _ -> nil
         end) do
      nil -> {:error, "Call activity '#{call_id}': no start event in process '#{process_id}'"}
      start_event -> {:ok, start_event}
    end
  end

  defp execute_child(id, elements, start_event, outgoing, context) do
    init_data = RodarBpmn.Context.get(context, :data)
    {:ok, child_ctx} = RodarBpmn.Context.start_link(elements, init_data)

    case RodarBpmn.execute(start_event, child_ctx) do
      {:ok, _} ->
        child_data = RodarBpmn.Context.get(child_ctx, :data)

        Enum.each(child_data, fn {key, value} ->
          RodarBpmn.Context.put_data(context, key, value)
        end)

        RodarBpmn.Context.put_meta(context, id, %{
          active: false,
          completed: true,
          type: :call_activity
        })

        RodarBpmn.release_token(outgoing, context)

      other ->
        other
    end
  end
end
