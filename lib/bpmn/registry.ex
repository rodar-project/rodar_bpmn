defmodule Bpmn.Registry do
  @moduledoc """
  Process definition registry for BPMN processes with version support.

  Stores parsed BPMN process definitions keyed by process ID, allowing
  lookup and management of available process definitions at runtime.
  Supports multiple versions of each definition, with automatic version
  incrementing on re-registration.

  Uses Elixir's built-in `Registry` module for efficient latest-version lookups.

  ## Versioning

  Each call to `register/2` auto-increments the version number. The latest
  version is always stored in the Elixir `ProcessRegistry` for fast-path
  `lookup/1`. Previous versions are retained in the GenServer state and
  accessible via `lookup/2`.

  Versions can be marked as deprecated via `deprecate/2`, which is an
  advisory flag (instances already running on deprecated versions continue
  to work).
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

  Auto-increments the version number. Returns `:ok` for backward compatibility.
  Use `register/3` to get the version number back.
  """
  @spec register(String.t(), any()) :: :ok
  def register(process_id, definition) do
    {:ok, _version} = register(process_id, definition, [])
    :ok
  end

  @doc """
  Register a process definition with options.

  ## Options

    * `:version` - explicit version number (default: auto-increment)

  Returns `{:ok, version}` where `version` is the assigned version number.
  """
  @spec register(String.t(), any(), keyword()) :: {:ok, pos_integer()}
  def register(process_id, definition, opts) do
    GenServer.call(__MODULE__, {:register, process_id, definition, opts})
  end

  @doc """
  Look up the latest process definition by process ID.
  """
  @spec lookup(String.t()) :: {:ok, any()} | :error
  def lookup(process_id) do
    case Registry.lookup(Bpmn.ProcessRegistry, process_id) do
      [{_pid, definition}] -> {:ok, definition}
      [] -> :error
    end
  end

  @doc """
  Look up a specific version of a process definition.
  """
  @spec lookup(String.t(), pos_integer()) :: {:ok, any()} | :error
  def lookup(process_id, version) do
    GenServer.call(__MODULE__, {:lookup, process_id, version})
  end

  @doc """
  List all versions of a process definition.

  Returns a list of maps with `:version` and `:deprecated` keys, sorted
  by version number ascending.
  """
  @spec versions(String.t()) :: [%{version: pos_integer(), deprecated: boolean()}]
  def versions(process_id) do
    GenServer.call(__MODULE__, {:versions, process_id})
  end

  @doc """
  Get the latest version number for a process definition.
  """
  @spec latest_version(String.t()) :: {:ok, pos_integer()} | :error
  def latest_version(process_id) do
    GenServer.call(__MODULE__, {:latest_version, process_id})
  end

  @doc """
  Mark a version as deprecated.

  Deprecated versions remain accessible but are flagged as such.
  """
  @spec deprecate(String.t(), pos_integer()) :: :ok | :error
  def deprecate(process_id, version) do
    GenServer.call(__MODULE__, {:deprecate, process_id, version})
  end

  @doc """
  Remove a process definition from the registry (all versions).
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
  def handle_call({:register, process_id, definition, opts}, _from, state) do
    ledger = Map.get(state, process_id, new_ledger())
    version = Keyword.get(opts, :version, ledger.latest + 1)

    new_ledger = %{
      ledger
      | latest: max(version, ledger.latest),
        versions: Map.put(ledger.versions, version, definition)
    }

    update_process_registry(process_id, definition, version, new_ledger.latest)

    {:reply, {:ok, version}, Map.put(state, process_id, new_ledger)}
  end

  def handle_call({:lookup, process_id, version}, _from, state) do
    case get_in(state, [process_id, :versions, version]) do
      nil -> {:reply, :error, state}
      definition -> {:reply, {:ok, definition}, state}
    end
  end

  def handle_call({:versions, process_id}, _from, state) do
    case Map.get(state, process_id) do
      nil ->
        {:reply, [], state}

      ledger ->
        version_list = build_version_list(ledger)
        {:reply, version_list, state}
    end
  end

  def handle_call({:latest_version, process_id}, _from, state) do
    case Map.get(state, process_id) do
      nil -> {:reply, :error, state}
      ledger -> {:reply, {:ok, ledger.latest}, state}
    end
  end

  def handle_call({:deprecate, process_id, version}, _from, state) do
    case Map.get(state, process_id) do
      nil ->
        {:reply, :error, state}

      ledger ->
        if Map.has_key?(ledger.versions, version) do
          new_ledger = %{ledger | deprecated: MapSet.put(ledger.deprecated, version)}
          {:reply, :ok, Map.put(state, process_id, new_ledger)}
        else
          {:reply, :error, state}
        end
    end
  end

  def handle_call({:unregister, process_id}, _from, state) do
    Registry.unregister(Bpmn.ProcessRegistry, process_id)
    {:reply, :ok, Map.delete(state, process_id)}
  end

  def handle_call(:list, _from, state) do
    {:reply, Map.keys(state), state}
  end

  # --- Private helpers ---

  defp new_ledger do
    %{latest: 0, versions: %{}, deprecated: MapSet.new()}
  end

  defp update_process_registry(process_id, definition, version, latest) do
    if version >= latest do
      Registry.unregister(Bpmn.ProcessRegistry, process_id)
      {:ok, _} = Registry.register(Bpmn.ProcessRegistry, process_id, definition)
    end
  end

  defp build_version_list(ledger) do
    ledger.versions
    |> Map.keys()
    |> Enum.sort()
    |> Enum.map(fn v ->
      %{version: v, deprecated: MapSet.member?(ledger.deprecated, v)}
    end)
  end
end
