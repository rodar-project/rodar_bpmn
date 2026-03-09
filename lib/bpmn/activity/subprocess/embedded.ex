defmodule Bpmn.Activity.Subprocess.Embedded do
  @moduledoc """
  Handle passing the token through an embedded subprocess element.

  An embedded subprocess executes a nested set of elements within the parent
  process context. The subprocess elements share the same context data as the
  parent process.

  ## Execution flow

  1. Extract nested `elements` map from element attrs
  2. Swap context process to nested elements
  3. Find and execute the start event within nested elements
  4. Restore parent process on completion
  5. Release token to outgoing flows

  ## Examples

      iex> start = {:bpmn_event_start, %{id: "sub_start", incoming: [], outgoing: ["sub_flow"]}}
      iex> sub_end = {:bpmn_event_end, %{id: "sub_end", incoming: ["sub_flow"], outgoing: []}}
      iex> sub_flow = {:bpmn_sequence_flow, %{id: "sub_flow", sourceRef: "sub_start", targetRef: "sub_end", conditionExpression: nil, isImmediate: nil}}
      iex> nested = %{"sub_start" => start, "sub_end" => sub_end, "sub_flow" => sub_flow}
      iex> outer_end = {:bpmn_event_end, %{id: "end", incoming: ["flow_out"], outgoing: []}}
      iex> flow_out = {:bpmn_sequence_flow, %{id: "flow_out", sourceRef: "sub", targetRef: "end", conditionExpression: nil, isImmediate: nil}}
      iex> process = %{"flow_out" => flow_out, "end" => outer_end}
      iex> {:ok, context} = Bpmn.Context.start_link(process, %{})
      iex> elem = {:bpmn_activity_subprocess_embeded, %{id: "sub", outgoing: ["flow_out"], elements: nested}}
      iex> {:ok, ^context} = Bpmn.Activity.Subprocess.Embedded.token_in(elem, context)
      iex> true
      true

  """

  @doc """
  Receive the token for the element and execute the nested subprocess.
  """
  @spec token_in(Bpmn.element(), Bpmn.context()) :: Bpmn.result()
  def token_in(
        {:bpmn_activity_subprocess_embeded, %{id: id, outgoing: outgoing, elements: elements}},
        context
      ) do
    Bpmn.Context.put_meta(context, id, %{active: true, completed: false, type: :subprocess})

    old_process = Bpmn.Context.swap_process(context, elements)

    result =
      case find_start_event(elements) do
        nil ->
          {:error, "Embedded subprocess '#{id}': no start event found"}

        start_event ->
          Bpmn.execute(start_event, context)
      end

    Bpmn.Context.swap_process(context, old_process)

    case result do
      {:ok, _} ->
        Bpmn.Context.put_meta(context, id, %{active: false, completed: true, type: :subprocess})
        Bpmn.release_token(outgoing, context)

      error ->
        error
    end
  end

  defp find_start_event(elements) do
    Enum.find_value(elements, fn
      {_id, {:bpmn_event_start, _} = elem} -> elem
      _ -> nil
    end)
  end
end
