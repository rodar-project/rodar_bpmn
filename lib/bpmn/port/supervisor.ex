defmodule Bpmn.Port.Supervisor do
  @moduledoc """
  Supervisor for the Node.js port process.
  """
  use Supervisor

  def start_link(_opts \\ []) do
    Supervisor.start_link(__MODULE__, :ok)
  end

  def init(:ok) do
    children = [
      {Bpmn.Port.Nodejs, ["node ./priv/scripts/node.js"]}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
