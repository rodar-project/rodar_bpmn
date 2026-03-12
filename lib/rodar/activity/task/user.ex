defmodule RodarBpmn.Activity.Task.User do
  @moduledoc """
  Handle passing the token through a user task element.

  A user task pauses execution and returns `{:manual, task_data}` to signal
  that external input is required. The caller should use `resume/3` to
  continue execution once the input is available.

  ## Examples

      iex> elem = {:bpmn_activity_task_user, %{id: "task_1", name: "Review", outgoing: ["flow_out"]}}
      iex> {:ok, context} = RodarBpmn.Context.start_link(%{}, %{})
      iex> {:manual, task_data} = RodarBpmn.Activity.Task.User.token_in(elem, context)
      iex> task_data.id
      "task_1"

  """

  @doc """
  Receive the token for the element. Pauses execution and returns task data.
  """
  @spec token_in(RodarBpmn.element(), RodarBpmn.context()) :: RodarBpmn.result()
  def token_in(
        {:bpmn_activity_task_user, %{id: id, outgoing: outgoing} = attrs},
        context
      ) do
    task_data = %{
      id: id,
      name: Map.get(attrs, :name),
      outgoing: outgoing,
      context: context
    }

    RodarBpmn.Context.put_meta(context, id, %{active: true, completed: false, type: :user_task})

    {:manual, task_data}
  end

  @doc """
  Resume execution of a paused user task with the provided input data.

  The `input` map is merged into the context data, and the token is released
  to the outgoing flows.
  """
  @spec resume(RodarBpmn.element(), RodarBpmn.context(), map()) :: RodarBpmn.result()
  def resume({:bpmn_activity_task_user, %{id: id, outgoing: outgoing}}, context, input)
      when is_map(input) do
    Enum.each(input, fn {key, value} ->
      RodarBpmn.Context.put_data(context, key, value)
    end)

    RodarBpmn.Context.put_meta(context, id, %{active: false, completed: true, type: :user_task})

    RodarBpmn.release_token(outgoing, context)
  end
end
