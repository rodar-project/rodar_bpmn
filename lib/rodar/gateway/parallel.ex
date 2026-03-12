defmodule Rodar.Gateway.Parallel do
  @moduledoc """
  Handle passing the token through a parallel gateway element.

  A parallel gateway (AND) has two behaviors:

  ## Fork (diverge)

  When the gateway has multiple outgoing flows and a single incoming flow,
  it releases tokens to **all** outgoing flows concurrently.

  ## Join (converge)

  When the gateway has multiple incoming flows, it waits until tokens have
  arrived on **all** incoming flows before releasing the token to the
  outgoing flow(s).

  ## Examples

      iex> end_event = {:bpmn_event_end, %{id: "end", incoming: ["flow_out"], outgoing: []}}
      iex> flow_out = {:bpmn_sequence_flow, %{id: "flow_out", sourceRef: "gw", targetRef: "end", conditionExpression: nil, isImmediate: nil}}
      iex> gateway = {:bpmn_gateway_parallel, %{id: "gw", incoming: ["in"], outgoing: ["flow_out"]}}
      iex> process = %{"flow_out" => flow_out, "end" => end_event}
      iex> {:ok, context} = Rodar.Context.start_link(process, %{})
      iex> {:ok, ^context} = Rodar.Gateway.Parallel.token_in(gateway, context)
      iex> true
      true

  """

  @doc """
  Receive the token for the element and execute the gateway logic.
  """
  @spec token_in(Rodar.element(), Rodar.context()) :: Rodar.result()
  def token_in(elem, context), do: token_in(elem, context, nil)

  @doc """
  Receive the token with the source flow ID for join tracking.
  """
  @spec token_in(Rodar.element(), Rodar.context(), String.t() | nil) :: Rodar.result()
  def token_in({:bpmn_gateway_parallel, %{incoming: incoming}} = elem, context, from_flow)
      when length(incoming) > 1 do
    join(elem, context, from_flow)
  end

  def token_in(elem, context, _from_flow), do: fork(elem, context)

  @doc """
  Fork: release tokens to all outgoing flows.
  """
  @spec fork(Rodar.element(), Rodar.context()) :: Rodar.result()
  def fork({:bpmn_gateway_parallel, %{outgoing: outgoing}}, context) do
    Rodar.release_token(outgoing, context)
  end

  @doc """
  Join: wait for all incoming tokens before continuing.
  """
  @spec join(Rodar.element(), Rodar.context(), String.t() | nil) :: Rodar.result()
  def join(
        {:bpmn_gateway_parallel, %{id: id, incoming: incoming, outgoing: outgoing}},
        context,
        from_flow
      ) do
    arrived =
      if from_flow do
        Rodar.Context.record_token(context, id, from_flow)
      else
        Rodar.Context.token_count(context, id)
      end

    if arrived >= length(incoming) do
      Rodar.Context.clear_tokens(context, id)
      Rodar.release_token(outgoing, context)
    else
      {:ok, context}
    end
  end
end
