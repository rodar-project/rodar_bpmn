defmodule RodarBpmn.Registry do
  @moduledoc """
  Process definition registry for BPMN processes.

  Stores parsed BPMN process definitions keyed by process ID, allowing
  lookup and management of available process definitions at runtime.

  Uses Elixir's built-in `Registry` module for efficient lookups.
  """

  use GenServer

  # --- Client API ---

  @doc """
  Start the registry GenServer.
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, %{}, name: name)
  end

  @doc """
  Register a process definition under the given process ID.
  """
  @spec register(String.t(), any()) :: :ok
  def register(process_id, definition) do
    GenServer.call(__MODULE__, {:register, process_id, definition})
  end

  @doc """
  Look up a process definition by process ID.
  """
  @spec lookup(String.t()) :: {:ok, any()} | :error
  def lookup(process_id) do
    case Registry.lookup(RodarBpmn.ProcessRegistry, process_id) do
      [{_pid, definition}] -> {:ok, definition}
      [] -> :error
    end
  end

  @doc """
  Remove a process definition from the registry.
  """
  @spec unregister(String.t()) :: :ok
  def unregister(process_id) do
    GenServer.call(__MODULE__, {:unregister, process_id})
  end

  @doc """
  List all registered process IDs.
  """
  @spec list() :: [String.t()]
  def list do
    GenServer.call(__MODULE__, :list)
  end

  # --- GenServer Callbacks ---

  @impl true
  def init(state) do
    {:ok, state}
  end

  @impl true
  def handle_call({:register, process_id, definition}, _from, state) do
    # Unregister first if already registered
    Registry.unregister(RodarBpmn.ProcessRegistry, process_id)
    {:ok, _} = Registry.register(RodarBpmn.ProcessRegistry, process_id, definition)
    {:reply, :ok, Map.put(state, process_id, true)}
  end

  def handle_call({:unregister, process_id}, _from, state) do
    Registry.unregister(RodarBpmn.ProcessRegistry, process_id)
    {:reply, :ok, Map.delete(state, process_id)}
  end

  def handle_call(:list, _from, state) do
    {:reply, Map.keys(state), state}
  end
end
