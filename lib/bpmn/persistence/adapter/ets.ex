defmodule Bpmn.Persistence.Adapter.ETS do
  @moduledoc """
  ETS-based persistence adapter for BPMN process snapshots.

  Stores serialized snapshots in a named ETS table owned by this GenServer.
  Suitable for development and testing — data is lost when the BEAM stops.
  """

  use GenServer
  @behaviour Bpmn.Persistence

  @table :bpmn_persistence

  # --- Client API ---

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl Bpmn.Persistence
  def save(instance_id, snapshot) do
    binary = Bpmn.Persistence.Serializer.serialize(snapshot)
    :ets.insert(@table, {instance_id, binary})
    :ok
  end

  @impl Bpmn.Persistence
  def load(instance_id) do
    case :ets.lookup(@table, instance_id) do
      [{^instance_id, binary}] ->
        {:ok, Bpmn.Persistence.Serializer.deserialize(binary)}

      [] ->
        {:error, :not_found}
    end
  end

  @impl Bpmn.Persistence
  def delete(instance_id) do
    :ets.delete(@table, instance_id)
    :ok
  end

  @impl Bpmn.Persistence
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
