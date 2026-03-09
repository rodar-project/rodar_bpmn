defmodule Bpmn.Activity.Task.User do
  @moduledoc """
  Handle passing the token through a user task element.

  A user task pauses execution and returns `{:manual, task_data}` to signal
  that external input is required. The caller should use `resume/3` to
  continue execution once the input is available.

  ## Examples

      iex> elem = {:bpmn_activity_task_user, %{id: "task_1", name: "Review", outgoing: ["flow_out"]}}
      iex> {:ok, context} = Bpmn.Context.start_link(%{}, %{})
      iex> {:manual, task_data} = Bpmn.Activity.Task.User.token_in(elem, context)
      iex> task_data.id
      "task_1"

  """

  @doc """
  Receive the token for the element. Pauses execution and returns task data.
  """
  @spec token_in(Bpmn.element(), Bpmn.context()) :: Bpmn.result()
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

    Bpmn.Context.put_meta(context, id, %{active: true, completed: false, type: :user_task})

    {:manual, task_data}
  end

  @doc """
  Resume execution of a paused user task with the provided input data.

  The `input` map is merged into the context data, and the token is released
  to the outgoing flows.
  """
  @spec resume(Bpmn.element(), Bpmn.context(), map()) :: Bpmn.result()
  def resume({:bpmn_activity_task_user, %{id: id, outgoing: outgoing}}, context, input)
      when is_map(input) do
    Enum.each(input, fn {key, value} ->
      Bpmn.Context.put_data(context, key, value)
    end)

    Bpmn.Context.put_meta(context, id, %{active: false, completed: true, type: :user_task})

    Bpmn.release_token(outgoing, context)
  end
end
