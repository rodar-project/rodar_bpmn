defmodule Rodar.Gateway.Exclusive.Event do
  @moduledoc """
  Handle passing the token through an event-based exclusive gateway element.

  An event-based gateway routes the token based on which downstream catch
  event fires first. It subscribes all downstream catch events to the event
  bus; the first one to fire wins, cancelling all other subscriptions.

  ## Examples

      iex> {:ok, context} = Rodar.Context.start_link(%{}, %{})
      iex> elem = {:bpmn_gateway_exclusive_event, %{id: "egw1", outgoing: ["f1", "f2"]}}
      iex> {:manual, task_data} = Rodar.Gateway.Exclusive.Event.token_in(elem, context)
      iex> task_data.id
      "egw1"

  """

  @doc """
  Receive the token for the element and set up event subscriptions.
  """
  @spec token_in(Rodar.element(), Rodar.context()) :: Rodar.result()
  def token_in({:bpmn_gateway_exclusive_event, %{id: id, outgoing: outgoing}}, context) do
    process = Rodar.Context.get(context, :process)

    # Find downstream catch events
    catch_events =
      outgoing
      |> Enum.map(fn flow_id ->
        case Map.get(process, flow_id) do
          {:bpmn_sequence_flow, %{targetRef: target_ref}} ->
            {flow_id, Map.get(process, target_ref)}

          _ ->
            {flow_id, nil}
        end
      end)
      |> Enum.reject(fn {_flow_id, elem} -> is_nil(elem) end)

    Rodar.Context.put_meta(context, id, %{
      active: true,
      completed: false,
      type: :event_gateway,
      pending_events: Enum.map(catch_events, fn {flow_id, _} -> flow_id end)
    })

    {:manual,
     %{
       id: id,
       type: :event_gateway,
       outgoing: outgoing,
       context: context,
       catch_events: catch_events
     }}
  end
end
