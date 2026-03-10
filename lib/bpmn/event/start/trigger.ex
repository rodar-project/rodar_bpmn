defmodule Bpmn.Event.Start.Trigger do
  @moduledoc """
  Auto-instantiation of BPMN processes via signal/message-triggered start events.

  When a process definition contains a start event with a `messageEventDefinition`
  or `signalEventDefinition`, you can register it so that publishing a matching
  event on the bus automatically creates and runs a new process instance.

  ## Example

      # Register a process with a message start event
      Bpmn.Registry.register("order-process", process_definition)
      Bpmn.Event.Start.Trigger.register("order-process")

      # Publishing a message now auto-creates a process instance
      Bpmn.Event.Bus.publish(:message, "new_order", %{data: %{"item" => "widget"}})
      # => A new "order-process" instance is created with %{"item" => "widget"} as init data

  """

  use GenServer

  # --- Client API ---

  @doc "Start the trigger GenServer."
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, %{}, name: name)
  end

  @doc """
  Register a process definition for event-triggered auto-instantiation.

  Scans the process definition for start events with message or signal event
  definitions and subscribes to the event bus for each. Returns the list of
  event subscriptions created.
  """
  @spec register(String.t()) :: {:ok, [{atom(), String.t()}]} | {:error, String.t()}
  def register(process_id) do
    GenServer.call(__MODULE__, {:register, process_id})
  end

  @doc """
  Remove all trigger subscriptions for a process definition.
  """
  @spec unregister(String.t()) :: :ok
  def unregister(process_id) do
    GenServer.call(__MODULE__, {:unregister, process_id})
  end

  @doc """
  List all registered trigger subscriptions.

  Returns a list of `%{process_id, event_type, event_name}` maps.
  """
  @spec list() :: [map()]
  def list do
    GenServer.call(__MODULE__, :list)
  end

  # --- GenServer Callbacks ---

  @impl true
  def init(_state) do
    {:ok, %{triggers: []}}
  end

  @impl true
  def handle_call({:register, process_id}, _from, state) do
    case Bpmn.Registry.lookup(process_id) do
      {:ok, {_type, _attrs, elements}} ->
        subscriptions = subscribe_start_events(process_id, elements)
        triggers = state.triggers ++ subscriptions
        {:reply, {:ok, subscriptions}, %{state | triggers: triggers}}

      :error ->
        {:reply, {:error, "Process '#{process_id}' not found in registry"}, state}
    end
  end

  def handle_call({:unregister, process_id}, _from, state) do
    {to_remove, remaining} = Enum.split_with(state.triggers, &(&1.process_id == process_id))

    Enum.each(to_remove, fn trigger ->
      Bpmn.Event.Bus.unsubscribe(trigger.event_type, trigger.event_name)
    end)

    {:reply, :ok, %{state | triggers: remaining}}
  end

  def handle_call(:list, _from, state) do
    {:reply, state.triggers, state}
  end

  @impl true
  def handle_info({:bpmn_event, _type, _name, payload, metadata}, state) do
    process_id = metadata.process_id
    init_data = extract_init_data(payload)
    spawn(fn -> Bpmn.Process.create_and_run(process_id, init_data) end)

    # Re-subscribe for next event (signals broadcast but messages are consumed)
    if metadata.event_type == :message do
      Bpmn.Event.Bus.subscribe(metadata.event_type, metadata.event_name, metadata)
    end

    {:noreply, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # --- Private helpers ---

  defp subscribe_start_events(process_id, elements) when is_map(elements) do
    elements
    |> Enum.flat_map(fn {_id, element} ->
      find_start_triggers(process_id, element)
    end)
  end

  defp subscribe_start_events(process_id, elements) when is_list(elements) do
    Enum.flat_map(elements, fn element ->
      find_start_triggers(process_id, element)
    end)
  end

  defp find_start_triggers(process_id, {:bpmn_event_start, attrs}) do
    triggers = []

    triggers =
      case Map.get(attrs, :messageEventDefinition) do
        {:bpmn_event_definition_message, def_attrs} ->
          name = Map.get(def_attrs, :messageRef, attrs[:id])
          subscribe_trigger(process_id, :message, name)
          [%{process_id: process_id, event_type: :message, event_name: name} | triggers]

        _ ->
          triggers
      end

    case Map.get(attrs, :signalEventDefinition) do
      {:bpmn_event_definition_signal, def_attrs} ->
        name = Map.get(def_attrs, :signalRef, attrs[:id])
        subscribe_trigger(process_id, :signal, name)
        [%{process_id: process_id, event_type: :signal, event_name: name} | triggers]

      _ ->
        triggers
    end
  end

  defp find_start_triggers(_process_id, _element), do: []

  defp subscribe_trigger(process_id, event_type, event_name) do
    Bpmn.Event.Bus.subscribe(event_type, event_name, %{
      process_id: process_id,
      event_type: event_type,
      event_name: event_name
    })
  end

  defp extract_init_data(%{data: data}) when is_map(data), do: data
  defp extract_init_data(payload) when is_map(payload), do: payload
  defp extract_init_data(_), do: %{}
end
