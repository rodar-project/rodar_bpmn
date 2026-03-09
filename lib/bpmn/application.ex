defmodule Bpmn.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Bpmn.Port.Supervisor
    ]

    opts = [strategy: :one_for_one, name: Bpmn.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
