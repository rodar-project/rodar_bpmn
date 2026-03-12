defmodule RodarBpmn.Event.Bus do
  @moduledoc """
  Registry-based pub/sub event bus for BPMN events.

  Supports message, signal, escalation, and timer event types with
  different delivery semantics:

  - `:message` — point-to-point: delivers to the first matching subscriber
    and unregisters it. Supports correlation keys for routing to specific
    subscribers when multiple instances wait for the same message name.
  - `:signal` — broadcast: delivers to all matching subscribers
  - `:escalation` — broadcast: delivers to all matching subscribers

  ## Message Correlation

  When multiple process instances subscribe to the same message name,
  correlation keys route messages to the correct subscriber. Both the
  subscriber metadata and publisher payload can include a `:correlation`
  map with `:key` and `:value` fields:

      # Subscriber metadata
      %{correlation: %{key: "order_id", value: "ORD-123"}, ...}

      # Publisher payload
      %{correlation: %{key: "order_id", value: "ORD-123"}, ...}

  If the publisher includes correlation, the bus finds the subscriber with
  a matching correlation key/value pair. If no correlated match is found,
  it falls back to an uncorrelated subscriber. If the publisher omits
  correlation, existing first-match behavior applies (backward compatible).

  Subscribers register with metadata containing callback information
  (context pid, node_id, outgoing flows) so the bus can resume execution
  when an event fires.
  """

  @registry RodarBpmn.EventRegistry

  @doc """
  Subscribe the calling process to events of the given type and name.

  ## Options in metadata

  - `:context` — the context pid to resume
  - `:node_id` — the BPMN node that is waiting
  - `:outgoing` — outgoing flow IDs to release token to
  - `:callback` — optional callback function

  ## Examples

      iex> {:ok, key} = RodarBpmn.Event.Bus.subscribe(:message, "order_received")
      iex> match?({:message, "order_received"}, key)
      true

  """
  @spec subscribe(atom(), String.t(), map()) :: {:ok, {atom(), String.t()}}
  def subscribe(event_type, event_name, metadata \\ %{}) do
    key = {event_type, event_name}
    {:ok, _} = Registry.register(@registry, key, metadata)
    RodarBpmn.Telemetry.event_subscribed(event_type, event_name, Map.get(metadata, :node_id))
    {:ok, key}
  end

  @doc """
  Unsubscribe the calling process from events of the given type and name.

  ## Examples

      iex> RodarBpmn.Event.Bus.subscribe(:message, "test_unsub")
      iex> RodarBpmn.Event.Bus.unsubscribe(:message, "test_unsub")
      :ok

  """
  @spec unsubscribe(atom(), String.t()) :: :ok
  def unsubscribe(event_type, event_name) do
    key = {event_type, event_name}
    Registry.unregister(@registry, key)
  end

  @doc """
  Publish an event to subscribers.

  - `:message` — delivers to the first subscriber and unregisters it.
    Returns `{:error, :no_subscriber}` if none found.
  - `:signal` — broadcasts to all subscribers. Always returns `:ok`.
  - `:escalation` — broadcasts to all subscribers. Always returns `:ok`.

  ## Examples

      iex> RodarBpmn.Event.Bus.publish(:signal, "no_listeners", %{})
      :ok

  """
  @spec publish(atom(), String.t(), map()) :: :ok | {:error, :no_subscriber}
  def publish(:message, event_name, payload) do
    key = {:message, event_name}

    case Registry.lookup(@registry, key) do
      [] ->
        RodarBpmn.Telemetry.event_published(:message, event_name, 0)
        {:error, :no_subscriber}

      subscribers ->
        case find_correlated_subscriber(subscribers, payload) do
          nil ->
            RodarBpmn.Telemetry.event_published(:message, event_name, 0)
            {:error, :no_subscriber}

          {pid, metadata} ->
            send(pid, {:bpmn_event, :message, event_name, payload, metadata})
            Registry.unregister_match(@registry, key, metadata, [])
            RodarBpmn.Telemetry.event_published(:message, event_name, 1)
            :ok
        end
    end
  end

  def publish(:signal, event_name, payload) do
    key = {:signal, event_name}

    Registry.dispatch(@registry, key, fn entries ->
      for {pid, metadata} <- entries do
        send(pid, {:bpmn_event, :signal, event_name, payload, metadata})
      end
    end)

    count = Registry.lookup(@registry, key) |> length()
    RodarBpmn.Telemetry.event_published(:signal, event_name, count)

    :ok
  end

  def publish(:escalation, event_name, payload) do
    key = {:escalation, event_name}

    Registry.dispatch(@registry, key, fn entries ->
      for {pid, metadata} <- entries do
        send(pid, {:bpmn_event, :escalation, event_name, payload, metadata})
      end
    end)

    count = Registry.lookup(@registry, key) |> length()
    RodarBpmn.Telemetry.event_published(:escalation, event_name, count)

    :ok
  end

  @doc """
  List current subscribers for the given event type and name.

  ## Examples

      iex> RodarBpmn.Event.Bus.subscriptions(:message, "nonexistent")
      []

  """
  @spec subscriptions(atom(), String.t()) :: [map()]
  def subscriptions(event_type, event_name) do
    key = {event_type, event_name}

    Registry.lookup(@registry, key)
    |> Enum.map(fn {pid, metadata} -> Map.put(metadata, :pid, pid) end)
  end

  defp find_correlated_subscriber(subscribers, payload) do
    pub_corr = Map.get(payload, :correlation)

    if is_nil(pub_corr) do
      List.first(subscribers)
    else
      correlated =
        Enum.find(subscribers, fn {_pid, meta} ->
          match_correlation?(Map.get(meta, :correlation), pub_corr)
        end)

      correlated ||
        Enum.find(subscribers, fn {_pid, meta} ->
          is_nil(Map.get(meta, :correlation))
        end)
    end
  end

  defp match_correlation?(nil, _pub), do: false
  defp match_correlation?(sub, pub), do: sub.key == pub.key and sub.value == pub.value
end
