defmodule RodarBpmn.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        {Registry, keys: :unique, name: RodarBpmn.ProcessRegistry},
        {Registry, keys: :duplicate, name: RodarBpmn.EventRegistry},
        RodarBpmn.Registry,
        RodarBpmn.TaskRegistry,
        RodarBpmn.Expression.ScriptRegistry,
        {DynamicSupervisor, name: RodarBpmn.ContextSupervisor, strategy: :one_for_one},
        {DynamicSupervisor, name: RodarBpmn.ProcessSupervisor, strategy: :one_for_one},
        RodarBpmn.Event.Start.Trigger
      ] ++ persistence_children()

    opts = [strategy: :one_for_one, name: RodarBpmn.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp persistence_children do
    case Application.get_env(:rodar_bpmn, :persistence) do
      nil -> []
      config -> [Keyword.get(config, :adapter, RodarBpmn.Persistence.Adapter.ETS)]
    end
  end
end
