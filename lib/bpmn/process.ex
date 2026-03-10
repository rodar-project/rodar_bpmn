defmodule Bpmn.Process do
  @moduledoc """
  Process lifecycle management for BPMN process instances.

  Manages the full lifecycle of a BPMN process instance: creation, activation,
  suspension, resumption, and termination. Each process instance runs as a
  GenServer that owns a supervised context and tracks execution status.

  ## Status transitions

      :created → :running → :completed
                         → :error
      :running → :suspended → :running (resume)
      any     → :terminated
  """

  use GenServer
  require Logger

  alias Bpmn.Context
  alias Bpmn.Event.Bus
  alias Bpmn.Persistence
  alias Bpmn.Persistence.Serializer
  alias Bpmn.Registry
  alias Bpmn.Telemetry
  alias Bpmn.Token
  alias Bpmn.Validation

  @type status :: :created | :running | :suspended | :completed | :terminated | :error

  # --- Client API ---

  @doc """
  Start a process instance from a registered definition.

  Looks up the process definition in `Bpmn.Registry`, creates a supervised
  context, and sets status to `:created`.
  """
  @spec start_link({String.t(), map()} | {:restore, map(), pid()} | String.t(), map()) ::
          {:ok, pid()} | {:error, any()}
  def start_link({:restore, _restore_data, _context} = args) do
    GenServer.start_link(__MODULE__, args)
  end

  def start_link({process_id, init_data}) do
    start_link(process_id, init_data)
  end

  def start_link(process_id, init_data \\ %{}) do
    GenServer.start_link(__MODULE__, {process_id, init_data})
  end

  @doc """
  Create a process instance under the `Bpmn.ProcessSupervisor` and activate it.
  """
  @spec create_and_run(String.t(), map()) :: {:ok, pid()} | {:error, any()}
  def create_and_run(process_id, init_data \\ %{}) do
    case DynamicSupervisor.start_child(
           Bpmn.ProcessSupervisor,
           {__MODULE__, {process_id, init_data}}
         ) do
      {:ok, pid} ->
        activate(pid)
        {:ok, pid}

      error ->
        error
    end
  end

  @doc """
  Activate a created process instance. Finds the start event and begins execution.
  """
  @spec activate(pid()) :: :ok | {:error, any()}
  def activate(pid) do
    GenServer.call(pid, :activate, :infinity)
  end

  @doc """
  Suspend a running process instance.
  """
  @spec suspend(pid()) :: :ok | {:error, any()}
  def suspend(pid) do
    GenServer.call(pid, :suspend)
  end

  @doc """
  Resume a suspended process instance.
  """
  @spec resume(pid()) :: :ok | {:error, any()}
  def resume(pid) do
    GenServer.call(pid, :resume)
  end

  @doc """
  Terminate a process instance and stop its context.
  """
  @spec terminate(pid()) :: :ok
  def terminate(pid) do
    GenServer.call(pid, :terminate)
  end

  @doc """
  Query the current status of a process instance.
  """
  @spec status(pid()) :: status()
  def status(pid) do
    GenServer.call(pid, :status)
  end

  @doc """
  Get the context pid for a process instance.
  """
  @spec get_context(pid()) :: pid()
  def get_context(pid) do
    GenServer.call(pid, :get_context)
  end

  @doc """
  Get the instance ID of a process instance.
  """
  @spec instance_id(pid()) :: String.t()
  def instance_id(pid) do
    GenServer.call(pid, :instance_id)
  end

  @doc """
  Get the definition version of a process instance.
  """
  @spec definition_version(pid()) :: pos_integer() | nil
  def definition_version(pid) do
    GenServer.call(pid, :definition_version)
  end

  @doc """
  Get the process ID string of a process instance.
  """
  @spec process_id(pid()) :: String.t()
  def process_id(pid) do
    GenServer.call(pid, :process_id)
  end

  @doc """
  Update the definition version tracked by this process instance.

  Used internally by `Bpmn.Migration` after swapping the process definition
  in the context.
  """
  @spec update_definition_version(pid(), pos_integer()) :: :ok
  def update_definition_version(pid, version) do
    GenServer.call(pid, {:update_definition_version, version})
  end

  @doc """
  Dehydrate a process instance: save its state to persistence and return
  the instance ID.
  """
  @spec dehydrate(pid()) :: {:ok, String.t()} | {:error, any()}
  def dehydrate(pid) do
    GenServer.call(pid, :dehydrate)
  end

  @doc """
  Rehydrate a process instance from a persisted snapshot.

  Loads the snapshot from the persistence adapter, looks up the process
  definition in the registry, starts a new supervised context with the
  restored state, and starts a new Process GenServer.
  """
  @spec rehydrate(String.t()) :: {:ok, pid()} | {:error, any()}
  def rehydrate(instance_id) do
    with {:ok, snapshot} <- Persistence.load(instance_id),
         {:ok, {_type, _attrs, elements}} <- lookup_registry_versioned(snapshot),
         process_map <- build_process_map(elements),
         {:ok, context} <- Context.start_supervised(process_map, %{}),
         deserialized_state <- Serializer.deserialize_context_state(snapshot.context_state),
         :ok <- Context.restore_state(context, deserialized_state),
         root_token <- Serializer.deserialize_token(snapshot.root_token),
         restore_data <- %{
           instance_id: snapshot.instance_id,
           process_id: snapshot.process_id,
           definition_version: Map.get(snapshot, :definition_version),
           status: snapshot.status,
           root_token: root_token
         },
         {:ok, pid} <-
           DynamicSupervisor.start_child(
             Bpmn.ProcessSupervisor,
             {__MODULE__, {:restore, restore_data, context}}
           ) do
      resubscribe_events(deserialized_state, process_map, context)
      {:ok, pid}
    else
      {:error, _} = err -> err
    end
  end

  # --- GenServer Callbacks ---

  @impl true
  def init({:restore, restore_data, context}) do
    Logger.metadata(
      bpmn_instance_id: restore_data.instance_id,
      bpmn_process_id: restore_data.process_id
    )

    {:ok,
     %{
       instance_id: restore_data.instance_id,
       process_id: restore_data.process_id,
       definition: nil,
       definition_version: Map.get(restore_data, :definition_version),
       context: context,
       status: restore_data.status,
       root_token: restore_data.root_token
     }}
  end

  def init({process_id, init_data}) do
    case Registry.lookup(process_id) do
      {:ok, {_type, attrs, elements}} ->
        version = fetch_latest_version(process_id)
        process_map = build_process_map(elements)

        case Context.start_supervised(process_map, init_data) do
          {:ok, context} ->
            instance_id = generate_instance_id()

            Logger.metadata(
              bpmn_instance_id: instance_id,
              bpmn_process_id: process_id
            )

            {:ok,
             %{
               instance_id: instance_id,
               process_id: process_id,
               definition: {attrs, elements},
               definition_version: version,
               context: context,
               status: :created,
               root_token: nil
             }}

          error ->
            {:stop, error}
        end

      :error ->
        {:stop, {:error, "Process '#{process_id}' not found in registry"}}
    end
  end

  @impl true
  def handle_call(:activate, _from, %{status: :created} = state) do
    process_map = Context.get(state.context, :process)

    case maybe_validate(process_map) do
      {:error, issues} ->
        state = %{state | status: :error}
        {:reply, {:error, {:validation_failed, issues}}, state}

      :ok ->
        do_activate(process_map, state)
    end
  end

  def handle_call(:activate, _from, state) do
    {:reply, {:error, "Cannot activate process in status: #{state.status}"}, state}
  end

  def handle_call(:suspend, _from, %{status: :running} = state) do
    {:reply, :ok, %{state | status: :suspended}}
  end

  def handle_call(:suspend, _from, state) do
    {:reply, {:error, "Cannot suspend process in status: #{state.status}"}, state}
  end

  def handle_call(:resume, _from, %{status: :suspended} = state) do
    {:reply, :ok, %{state | status: :running}}
  end

  def handle_call(:resume, _from, state) do
    {:reply, {:error, "Cannot resume process in status: #{state.status}"}, state}
  end

  def handle_call(:terminate, _from, state) do
    if Process.alive?(state.context) do
      GenServer.stop(state.context, :normal)
    end

    {:reply, :ok, %{state | status: :terminated}}
  end

  def handle_call(:status, _from, state) do
    {:reply, state.status, state}
  end

  def handle_call(:get_context, _from, state) do
    {:reply, state.context, state}
  end

  def handle_call(:instance_id, _from, state) do
    {:reply, state.instance_id, state}
  end

  def handle_call(:definition_version, _from, state) do
    {:reply, state.definition_version, state}
  end

  def handle_call(:process_id, _from, state) do
    {:reply, state.process_id, state}
  end

  def handle_call({:update_definition_version, version}, _from, state) do
    {:reply, :ok, %{state | definition_version: version}}
  end

  def handle_call(:dehydrate, _from, state) do
    case do_dehydrate(state) do
      {:ok, instance_id} -> {:reply, {:ok, instance_id}, state}
      {:error, _} = err -> {:reply, err, state}
    end
  end

  # --- Private helpers ---

  defp do_activate(process_map, state) do
    case find_start_event(process_map) do
      nil ->
        state = %{state | status: :error}
        {:reply, {:error, "No start event found"}, state}

      start_event ->
        state = run_from_start(start_event, state)
        {:reply, :ok, state}
    end
  end

  defp run_from_start(start_event, state) do
    token = Token.new()
    state = %{state | status: :running, root_token: token}
    start_time = System.monotonic_time()
    Telemetry.process_started(state.instance_id, state.process_id)

    result = Bpmn.execute(start_event, state.context, token)

    state =
      case result do
        {:ok, _} ->
          %{state | status: :completed}

        {:error, _} ->
          %{state | status: :error}

        {:manual, _} ->
          state = %{state | status: :suspended}
          maybe_auto_dehydrate(state)
          state

        _ ->
          %{state | status: :error}
      end

    Telemetry.process_stopped(
      state.instance_id,
      state.process_id,
      state.status,
      start_time
    )

    state
  end

  defp maybe_validate(process_map) do
    if Application.get_env(:bpmn, :validate_on_activate, false) do
      case Validation.validate(process_map) do
        {:ok, _} -> :ok
        {:error, _} = err -> err
      end
    else
      :ok
    end
  end

  defp find_start_event(process_map) do
    Enum.find_value(process_map, fn
      {_id, {:bpmn_event_start, _} = elem} -> elem
      _ -> nil
    end)
  end

  defp build_process_map(elements) when is_map(elements), do: elements

  defp build_process_map(elements) when is_list(elements) do
    Enum.reduce(elements, %{}, fn
      {_type, %{id: id}} = elem, acc -> Map.put(acc, id, elem)
      _, acc -> acc
    end)
  end

  defp generate_instance_id do
    Token.new().id
  end

  defp fetch_latest_version(process_id) do
    case Registry.latest_version(process_id) do
      {:ok, version} -> version
      :error -> nil
    end
  end

  defp maybe_auto_dehydrate(state) do
    if Persistence.auto_dehydrate?(), do: do_dehydrate(state)
  end

  defp lookup_registry(process_id) do
    case Registry.lookup(process_id) do
      {:ok, _} = result -> result
      :error -> {:error, "Process '#{process_id}' not found in registry"}
    end
  end

  defp lookup_registry_versioned(snapshot) do
    case Map.get(snapshot, :definition_version) do
      nil ->
        lookup_registry(snapshot.process_id)

      version ->
        case Registry.lookup(snapshot.process_id, version) do
          {:ok, _} = result -> result
          :error -> lookup_registry(snapshot.process_id)
        end
    end
  end

  defp do_dehydrate(state) do
    context_state = Context.get_state(state.context)

    snapshot =
      Serializer.snapshot(%{
        instance_id: state.instance_id,
        process_id: state.process_id,
        definition_version: state.definition_version,
        status: state.status,
        root_token: state.root_token,
        context_state: context_state
      })

    case Persistence.save(state.instance_id, snapshot) do
      :ok -> {:ok, state.instance_id}
      {:error, _} = err -> err
    end
  end

  defp resubscribe_events(context_state, process_map, context) do
    Enum.each(context_state.nodes, fn
      {node_id, %{active: true, type: type}} when type in [:catch_event, :boundary_event] ->
        case Map.get(process_map, node_id) do
          {_elem_type, %{outgoing: outgoing} = attrs} ->
            resubscribe_node(node_id, attrs, outgoing, context)

          _ ->
            :ok
        end

      _ ->
        :ok
    end)
  end

  defp resubscribe_node(id, attrs, outgoing, context) do
    metadata = %{context: context, node_id: id, outgoing: outgoing}

    cond do
      match?({:bpmn_event_definition_message, _}, Map.get(attrs, :messageEventDefinition)) ->
        {:bpmn_event_definition_message, def_attrs} = attrs.messageEventDefinition
        name = Map.get(def_attrs, :messageRef, id)
        Bus.subscribe(:message, name, metadata)

      match?({:bpmn_event_definition_signal, _}, Map.get(attrs, :signalEventDefinition)) ->
        {:bpmn_event_definition_signal, def_attrs} = attrs.signalEventDefinition
        name = Map.get(def_attrs, :signalRef, id)
        Bus.subscribe(:signal, name, metadata)

      match?({:bpmn_event_definition_escalation, _}, Map.get(attrs, :escalationEventDefinition)) ->
        {:bpmn_event_definition_escalation, def_attrs} = attrs.escalationEventDefinition
        name = Map.get(def_attrs, :escalationRef, id)
        Bus.subscribe(:escalation, name, metadata)

      true ->
        :ok
    end
  end
end
