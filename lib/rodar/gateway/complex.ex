defmodule Rodar.Gateway.Complex do
  @moduledoc """
  Handle passing the token through a complex gateway element.

  A complex gateway is similar to an inclusive gateway but with a configurable
  `activationCondition` expression for join behavior. On fork, it evaluates
  conditions on outgoing flows (like an inclusive gateway). On join, it uses
  the activation condition to determine when enough tokens have arrived.

  ## Examples

      iex> end_event = {:bpmn_event_end, %{id: "end", incoming: ["flow_out"], outgoing: []}}
      iex> flow_out = {:bpmn_sequence_flow, %{id: "flow_out", sourceRef: "gw", targetRef: "end", conditionExpression: nil, isImmediate: nil}}
      iex> gateway = {:bpmn_gateway_complex, %{id: "gw", incoming: ["in"], outgoing: ["flow_out"]}}
      iex> process = %{"flow_out" => flow_out, "end" => end_event}
      iex> {:ok, context} = Rodar.Context.start_link(process, %{})
      iex> {:ok, ^context} = Rodar.Gateway.Complex.token_in(gateway, context)
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
  def token_in({:bpmn_gateway_complex, %{incoming: incoming}} = elem, context, from_flow)
      when length(incoming) > 1 do
    join(elem, context, from_flow)
  end

  def token_in(elem, context, _from_flow), do: fork(elem, context)

  defp fork({:bpmn_gateway_complex, %{id: id, outgoing: outgoing} = attrs}, context) do
    process = Rodar.Context.get(context, :process)
    default_flow = Map.get(attrs, :default)

    matching =
      outgoing
      |> Enum.filter(fn flow_id ->
        flow_id != default_flow && flow_matches?(Map.get(process, flow_id), context)
      end)

    activated =
      case matching do
        [] when is_binary(default_flow) -> [default_flow]
        [] -> :none
        flows -> flows
      end

    case activated do
      :none ->
        {:error, "Complex gateway '#{id}': no matching condition and no default flow"}

      flows ->
        Rodar.Context.record_activated_paths(context, id, flows)
        Rodar.release_token(flows, context)
    end
  end

  defp join(
         {:bpmn_gateway_complex, %{id: id, incoming: incoming, outgoing: outgoing} = attrs},
         context,
         from_flow
       ) do
    arrived =
      if from_flow do
        Rodar.Context.record_token(context, id, from_flow)
      else
        Rodar.Context.token_count(context, id)
      end

    expected = expected_count(context, id, incoming, attrs)

    if arrived >= expected do
      Rodar.Context.clear_tokens(context, id)
      Rodar.Context.clear_activated_paths(context, id)
      Rodar.release_token(outgoing, context)
    else
      {:ok, context}
    end
  end

  defp expected_count(context, gateway_id, incoming, attrs) do
    case Map.get(attrs, :activationCondition) do
      nil ->
        case Rodar.Context.get_activated_paths(context, gateway_id) do
          nil -> length(incoming)
          paths -> length(paths)
        end

      activation_condition ->
        case Rodar.Expression.execute(activation_condition, context) do
          {:ok, count} when is_integer(count) -> count
          _ -> length(incoming)
        end
    end
  end

  defp flow_matches?({:bpmn_sequence_flow, %{conditionExpression: condition}}, context)
       when not is_nil(condition) do
    case Rodar.Expression.execute(condition, context) do
      {:ok, true} -> true
      {:ok, false} -> false
    end
  end

  defp flow_matches?(_flow, _context), do: true
end
