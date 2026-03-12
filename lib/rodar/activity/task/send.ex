defmodule Rodar.Activity.Task.Send do
  @moduledoc """
  Handle passing the token through a send task element.

  A send task stores message metadata in the context and releases the token
  to outgoing flows. If a `messageRef` is present, it publishes the message
  to the event bus for automatic delivery to waiting receive tasks/catch events.

  ## Examples

      iex> end_event = {:bpmn_event_end, %{id: "end", incoming: ["flow_out"], outgoing: []}}
      iex> flow_out = {:bpmn_sequence_flow, %{id: "flow_out", sourceRef: "task_1", targetRef: "end", conditionExpression: nil, isImmediate: nil}}
      iex> process = %{"flow_out" => flow_out, "end" => end_event}
      iex> {:ok, context} = Context.start_link(process, %{})
      iex> elem = {:bpmn_activity_task_send, %{id: "task_1", name: "Send Invoice", outgoing: ["flow_out"]}}
      iex> {:ok, ^context} = Rodar.Activity.Task.Send.token_in(elem, context)
      iex> true
      true

  """

  alias Rodar.Context
  alias Rodar.Event.Bus

  @doc """
  Receive the token for the element. Stores message metadata and releases token.
  If `messageRef` is present, publishes to the event bus.
  """
  @spec token_in(Rodar.element(), Rodar.context()) :: Rodar.result()
  def token_in(
        {:bpmn_activity_task_send, %{id: id, outgoing: outgoing} = attrs},
        context
      ) do
    Context.put_meta(context, id, %{
      active: false,
      completed: true,
      type: :send_task,
      message_name: Map.get(attrs, :name)
    })

    # Publish to event bus if messageRef is present
    case Map.get(attrs, :messageRef) do
      nil ->
        :ok

      message_ref ->
        data = Context.get(context, :data)
        payload = %{source: id, data: data}
        payload = put_correlation(payload, attrs, context)
        Bus.publish(:message, message_ref, payload)
    end

    Rodar.release_token(outgoing, context)
  end

  defp put_correlation(payload, attrs, context) do
    case Map.get(attrs, :correlationKey) do
      nil ->
        payload

      key ->
        data = Context.get(context, :data)
        Map.put(payload, :correlation, %{key: key, value: Map.get(data, key)})
    end
  end
end
