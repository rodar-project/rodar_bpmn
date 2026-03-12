defmodule Mix.Tasks.RodarBpmn.Run.PassthroughHandler do
  @moduledoc """
  No-op service task handler for `mix rodar_bpmn.run`.

  Registered at runtime for service tasks that have no real handler,
  allowing execution to continue through the process. Cleaned up after
  the run completes.
  """

  @behaviour RodarBpmn.Activity.Task.Service.Handler

  @impl true
  def execute(_attrs, _data), do: {:ok, %{}}
end
