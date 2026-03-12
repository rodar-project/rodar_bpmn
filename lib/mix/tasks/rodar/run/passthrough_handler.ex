defmodule Mix.Tasks.Rodar.Run.PassthroughHandler do
  @moduledoc """
  No-op service task handler for `mix rodar.run`.

  Registered at runtime for service tasks that have no real handler,
  allowing execution to continue through the process. Cleaned up after
  the run completes.
  """

  @behaviour Rodar.Activity.Task.Service.Handler

  @impl true
  def execute(_attrs, _data), do: {:ok, %{}}
end
