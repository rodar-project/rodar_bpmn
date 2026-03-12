defmodule Rodar.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        {Registry, keys: :unique, name: Rodar.ProcessRegistry},
        {Registry, keys: :duplicate, name: Rodar.EventRegistry},
        Rodar.Registry,
        Rodar.TaskRegistry,
        Rodar.Expression.ScriptRegistry,
        {DynamicSupervisor, name: Rodar.ContextSupervisor, strategy: :one_for_one},
        {DynamicSupervisor, name: Rodar.ProcessSupervisor, strategy: :one_for_one},
        Rodar.Event.Start.Trigger
      ] ++ persistence_children()

    opts = [strategy: :one_for_one, name: Rodar.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp persistence_children do
    case Application.get_env(:rodar, :persistence) do
      nil -> []
      config -> [Keyword.get(config, :adapter, Rodar.Persistence.Adapter.ETS)]
    end
  end
end
