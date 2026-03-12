defmodule Rodar.Gateway.Exclusive do
  @moduledoc """
  Handle passing the token through an exclusive gateway element.

  An exclusive gateway (XOR) evaluates conditions on outgoing sequence flows
  and routes the token down the first matching path, or the default flow if
  no conditions match.

  ## Diverging (split)

  When the gateway has multiple outgoing flows, it evaluates each flow's
  condition expression in order. The token is sent to the first flow whose
  condition evaluates to `true`. If no condition matches, the default flow
  (if specified) is used.

  ## Converging (merge)

  When the gateway has a single outgoing flow (or is used as a merge point),
  the token passes straight through to the outgoing flow.

  ## Examples

      iex> end_event = {:bpmn_event_end, %{id: "end", incoming: ["flow_yes"], outgoing: []}}
      iex> flow_yes = {:bpmn_sequence_flow, %{id: "flow_yes", sourceRef: "gw", targetRef: "end", conditionExpression: nil, isImmediate: nil}}
      iex> flow_no = {:bpmn_sequence_flow, %{id: "flow_no", sourceRef: "gw", targetRef: "end", conditionExpression: nil, isImmediate: nil}}
      iex> gateway = {:bpmn_gateway_exclusive, %{id: "gw", incoming: ["in"], outgoing: ["flow_yes", "flow_no"], default: "flow_no"}}
      iex> process = %{"flow_yes" => flow_yes, "flow_no" => flow_no, "end" => end_event}
      iex> {:ok, context} = Rodar.Context.start_link(process, %{})
      iex> {:ok, ^context} = Rodar.Gateway.Exclusive.token_in(gateway, context)
      iex> true
      true

  """

  @doc """
  Receive the token for the element and route it through the gateway.
  """
  @spec token_in(Rodar.element(), Rodar.context()) :: Rodar.result()
  def token_in(elem, context), do: execute(elem, context)

  @doc """
  Execute the exclusive gateway business logic.

  For diverging gateways, evaluates conditions on outgoing sequence flows
  and routes the token to the first match or the default flow.

  For converging gateways (single outgoing), passes the token through.
  """
  @spec execute(Rodar.element(), Rodar.context()) :: Rodar.result()
  def execute({:bpmn_gateway_exclusive, %{outgoing: outgoing} = attrs}, context) do
    process = Rodar.Context.get(context, :process)
    default_flow = Map.get(attrs, :default)

    result =
      outgoing
      |> Enum.reduce_while(nil, fn flow_id, _acc ->
        flow = Map.get(process, flow_id)
        evaluate_flow(flow, flow_id, default_flow, context)
      end)

    case result do
      nil when is_binary(default_flow) ->
        Rodar.release_token(default_flow, context)

      nil ->
        {:error, "Exclusive gateway: no matching condition and no default flow"}

      matched_flow_id ->
        Rodar.release_token(matched_flow_id, context)
    end
  end

  def execute(_elem, _context), do: {:error, "Invalid exclusive gateway element"}

  defp evaluate_flow(
         {:bpmn_sequence_flow, %{conditionExpression: condition}},
         flow_id,
         _default_flow,
         context
       )
       when not is_nil(condition) do
    case Rodar.Expression.execute(condition, context) do
      {:ok, true} -> {:halt, flow_id}
      {:ok, false} -> {:cont, nil}
    end
  end

  # Flows without conditions: skip unless it's the default flow
  defp evaluate_flow(_flow, flow_id, default_flow, _context) do
    if flow_id == default_flow do
      {:cont, nil}
    else
      # Unconditional non-default flow — treat as match
      {:halt, flow_id}
    end
  end
end
