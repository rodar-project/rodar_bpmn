defmodule Bpmn.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Registry, keys: :unique, name: Bpmn.ProcessRegistry},
      {Registry, keys: :duplicate, name: Bpmn.EventRegistry},
      Bpmn.Registry,
      {DynamicSupervisor, name: Bpmn.ContextSupervisor, strategy: :one_for_one},
      {DynamicSupervisor, name: Bpmn.ProcessSupervisor, strategy: :one_for_one}
    ]

    opts = [strategy: :one_for_one, name: Bpmn.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
