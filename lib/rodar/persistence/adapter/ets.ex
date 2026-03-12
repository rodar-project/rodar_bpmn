defmodule Rodar.Persistence.Adapter.ETS do
  @moduledoc """
  ETS-based persistence adapter for BPMN process snapshots.

  Stores serialized snapshots in a named ETS table owned by this GenServer.
  Suitable for development and testing — data is lost when the BEAM stops.
  """

  use GenServer
  @behaviour Rodar.Persistence

  alias Rodar.Persistence.Serializer

  @table :rodar_persistence

  # --- Client API ---

  @doc "Starts the ETS adapter GenServer and creates the named table."
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc "Serializes and stores a process snapshot in ETS, keyed by instance ID."
  @impl Rodar.Persistence
  def save(instance_id, snapshot) do
    binary = Serializer.serialize(snapshot)
    :ets.insert(@table, {instance_id, binary})
    :ok
  end

  @doc "Loads and deserializes a snapshot by instance ID. Returns `{:error, :not_found}` if missing."
  @impl Rodar.Persistence
  def load(instance_id) do
    case :ets.lookup(@table, instance_id) do
      [{^instance_id, binary}] ->
        {:ok, Serializer.deserialize(binary)}

      [] ->
        {:error, :not_found}
    end
  end

  @doc "Removes a snapshot from ETS by instance ID."
  @impl Rodar.Persistence
  def delete(instance_id) do
    :ets.delete(@table, instance_id)
    :ok
  end

  @doc "Returns a list of all stored instance IDs."
  @impl Rodar.Persistence
  def list do
    :ets.tab2list(@table)
    |> Enum.map(fn {id, _binary} -> id end)
  end

  # --- GenServer Callbacks ---

  @impl true
  def init(_opts) do
    table = :ets.new(@table, [:named_table, :public, :set])
    {:ok, %{table: table}}
  end
end
