defmodule RodarBpmn.SequenceFlow do
  @moduledoc """
  Handles sequence flow elements that connect BPMN nodes.

  Evaluates an optional condition expression via `RodarBpmn.Expression` before
  passing the token to the target node. If the condition evaluates to `false`,
  returns `{:false}` (used by exclusive and inclusive gateways to skip the path).
  Unconditional flows pass the token through directly.

  ## Examples

      iex> {:ok, context} = RodarBpmn.Context.start_link(%{"to" => {:bpmn_activity_task_script, %{}}}, %{"username" => "test", "password" => "secret"})
      iex> RodarBpmn.SequenceFlow.token_in({:bpmn_sequence_flow, %{sourceRef: "from", targetRef: "to"}}, context)
      {:not_implemented}

      iex> {:ok, context} = RodarBpmn.Context.start_link(%{"to" => {:bpmn_activity_task_script, %{}}}, %{"username" => "test", "password" => "secret"})
      iex> RodarBpmn.SequenceFlow.token_in({:bpmn_sequence_flow, %{sourceRef: "from", targetRef: "to", conditionExpression: {:bpmn_expression, {"elixir", "1!=1"}}}}, context)
      {:false}
  """

  @doc """
  Evaluates any condition expression and releases the token to the target node.
  """
  @spec token_in(RodarBpmn.element(), RodarBpmn.context()) :: RodarBpmn.result()
  def token_in(elem, context), do: execute(elem, context)

  defp token_out({:bpmn_sequence_flow, %{targetRef: target}}, context),
    do: RodarBpmn.release_token(target, context)

  @doc """
  Execute the sequence flow logic
  """
  @spec execute(RodarBpmn.element(), RodarBpmn.context()) :: RodarBpmn.result()
  def execute({:bpmn_sequence_flow, %{conditionExpression: condition} = flow}, context)
      when not is_nil(condition) do
    case RodarBpmn.Expression.execute(condition, context) do
      {:ok, true} -> token_out({:bpmn_sequence_flow, flow}, context)
      {:ok, false} -> {false}
    end
  end

  def execute(elem, context), do: token_out(elem, context)
end
