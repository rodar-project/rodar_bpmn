defmodule Bpmn.Activity.Task.Service.TestHandler do
  @moduledoc false
  @behaviour Bpmn.Activity.Task.Service.Handler

  @impl true
  def execute(_attrs, _data) do
    {:ok, %{result: "handled"}}
  end
end
