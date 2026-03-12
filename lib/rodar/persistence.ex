defmodule RodarBpmn.Persistence do
  @moduledoc """
  Persistence behaviour and facade for BPMN process snapshots.

  Defines the adapter callback contract and provides a public API that
  delegates to the configured adapter. The adapter is read from application
  config:

      config :rodar_bpmn, :persistence,
        adapter: RodarBpmn.Persistence.Adapter.ETS,
        auto_dehydrate: true

  ## Callbacks

  Adapters must implement `save/2`, `load/1`, `delete/1`, and `list/0`.
  """

  @type instance_id :: String.t()
  @type snapshot :: map()

  @callback save(instance_id, snapshot) :: :ok | {:error, any()}
  @callback load(instance_id) :: {:ok, snapshot} | {:error, :not_found}
  @callback delete(instance_id) :: :ok
  @callback list() :: [instance_id]

  @doc "Save a process snapshot."
  @spec save(instance_id, snapshot) :: :ok | {:error, any()}
  def save(instance_id, snapshot), do: adapter().save(instance_id, snapshot)

  @doc "Load a process snapshot by instance ID."
  @spec load(instance_id) :: {:ok, snapshot} | {:error, :not_found}
  def load(instance_id), do: adapter().load(instance_id)

  @doc "Delete a process snapshot."
  @spec delete(instance_id) :: :ok
  def delete(instance_id), do: adapter().delete(instance_id)

  @doc "List all persisted instance IDs."
  @spec list() :: [instance_id]
  def list, do: adapter().list()

  @doc "Return the configured persistence adapter module."
  @spec adapter() :: module()
  def adapter do
    config = Application.get_env(:rodar_bpmn, :persistence, [])
    Keyword.get(config, :adapter, RodarBpmn.Persistence.Adapter.ETS)
  end

  @doc "Return whether auto-dehydrate is enabled."
  @spec auto_dehydrate?() :: boolean()
  def auto_dehydrate? do
    config = Application.get_env(:rodar_bpmn, :persistence, [])
    Keyword.get(config, :auto_dehydrate, true)
  end
end
