defmodule Bpmn.SequenceFlow do
  @moduledoc """
  Handle passing the token through a sequence flow element.

    iex> {:ok, context} = Bpmn.Context.start_link(%{"to" => {:bpmn_activity_task_script, %{}}}, %{"username" => "test", "password" => "secret"})
    iex> Bpmn.SequenceFlow.token_in({:bpmn_sequence_flow, %{sourceRef: "from", targetRef: "to"}}, context)
    {:not_implemented}

    iex> {:ok, context} = Bpmn.Context.start_link(%{"to" => {:bpmn_activity_task_script, %{}}}, %{"username" => "test", "password" => "secret"})
    iex> Bpmn.SequenceFlow.token_in({:bpmn_sequence_flow, %{sourceRef: "from", targetRef: "to", conditionExpression: {:bpmn_expression, {"elixir", "1!=1"}}}}, context)
    {:false}
  """

  @doc """
  Receive the token for the element and decide if the business logic should be executed
  """
  @spec token_in(Bpmn.element(), Bpmn.context()) :: Bpmn.result()
  def token_in(elem, context), do: execute(elem, context)

  defp token_out({:bpmn_sequence_flow, %{targetRef: target}}, context),
    do: Bpmn.release_token(target, context)

  @doc """
  Execute the sequence flow logic
  """
  @spec execute(Bpmn.element(), Bpmn.context()) :: Bpmn.result()
  def execute({:bpmn_sequence_flow, %{conditionExpression: condition} = flow}, context)
      when not is_nil(condition) do
    case Bpmn.Expression.execute(condition, context) do
      {:ok, true} -> token_out({:bpmn_sequence_flow, flow}, context)
      {:ok, false} -> {false}
    end
  end

  def execute(elem, context), do: token_out(elem, context)
end
