defmodule RodarBpmn.Activity.Task.Receive do
  @moduledoc """
  Handle passing the token through a receive task element.

  A receive task pauses execution and returns `{:manual, task_data}` to signal
  that an external message must be received before the process can continue.
  Use `resume/3` to continue execution once the message arrives.

  If `messageRef` is present, the task subscribes to the event bus for
  automatic resume when a matching message is published.

  ## Examples

      iex> elem = {:bpmn_activity_task_receive, %{id: "task_1", name: "Wait for Payment", outgoing: ["flow_out"]}}
      iex> {:ok, context} = Context.start_link(%{}, %{})
      iex> {:manual, task_data} = RodarBpmn.Activity.Task.Receive.token_in(elem, context)
      iex> task_data.id
      "task_1"

  """

  alias RodarBpmn.Context
  alias RodarBpmn.Event.Bus

  @doc """
  Receive the token for the element. Pauses execution and returns task data.
  If `messageRef` is present, subscribes to event bus for auto-resume.
  """
  @spec token_in(RodarBpmn.element(), RodarBpmn.context()) :: RodarBpmn.result()
  def token_in(
        {:bpmn_activity_task_receive, %{id: id, outgoing: outgoing} = attrs},
        context
      ) do
    task_data = %{
      id: id,
      name: Map.get(attrs, :name),
      outgoing: outgoing,
      context: context
    }

    Context.put_meta(context, id, %{active: true, completed: false, type: :receive_task})

    # Subscribe to event bus if messageRef is present
    case Map.get(attrs, :messageRef) do
      nil ->
        :ok

      message_ref ->
        metadata = %{context: context, node_id: id, outgoing: outgoing}
        metadata = put_correlation(metadata, attrs, context)
        Bus.subscribe(:message, message_ref, metadata)
    end

    {:manual, task_data}
  end

  @doc """
  Resume execution of a paused receive task with the provided message data.

  The `input` map is merged into the context data, and the token is released
  to the outgoing flows.
  """
  @spec resume(RodarBpmn.element(), RodarBpmn.context(), map()) :: RodarBpmn.result()
  def resume({:bpmn_activity_task_receive, %{id: id, outgoing: outgoing}}, context, input)
      when is_map(input) do
    Enum.each(input, fn {key, value} ->
      Context.put_data(context, key, value)
    end)

    Context.put_meta(context, id, %{active: false, completed: true, type: :receive_task})

    RodarBpmn.release_token(outgoing, context)
  end

  defp put_correlation(metadata, attrs, context) do
    case Map.get(attrs, :correlationKey) do
      nil ->
        metadata

      key ->
        data = Context.get(context, :data)
        Map.put(metadata, :correlation, %{key: key, value: Map.get(data, key)})
    end
  end
end
