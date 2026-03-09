defmodule Bpmn.Activity.Task.Send do
  @moduledoc """
  Handle passing the token through a send task element.

  A send task is fire-and-forget: it stores message metadata in the context
  and immediately releases the token to outgoing flows. Phase 5 event bus
  will add actual message emission.

  ## Examples

      iex> end_event = {:bpmn_event_end, %{id: "end", incoming: ["flow_out"], outgoing: []}}
      iex> flow_out = {:bpmn_sequence_flow, %{id: "flow_out", sourceRef: "task_1", targetRef: "end", conditionExpression: nil, isImmediate: nil}}
      iex> process = %{"flow_out" => flow_out, "end" => end_event}
      iex> {:ok, context} = Bpmn.Context.start_link(process, %{})
      iex> elem = {:bpmn_activity_task_send, %{id: "task_1", name: "Send Invoice", outgoing: ["flow_out"]}}
      iex> {:ok, ^context} = Bpmn.Activity.Task.Send.token_in(elem, context)
      iex> true
      true

  """

  @doc """
  Receive the token for the element. Stores message metadata and releases token.
  """
  @spec token_in(Bpmn.element(), Bpmn.context()) :: Bpmn.result()
  def token_in(
        {:bpmn_activity_task_send, %{id: id, outgoing: outgoing} = attrs},
        context
      ) do
    Bpmn.Context.put_meta(context, id, %{
      active: false,
      completed: true,
      type: :send_task,
      message_name: Map.get(attrs, :name)
    })

    Bpmn.release_token(outgoing, context)
  end
end
