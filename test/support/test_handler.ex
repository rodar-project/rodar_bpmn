defmodule Rodar.Activity.Task.Service.TestHandler do
  @moduledoc false
  @behaviour Rodar.Activity.Task.Service.Handler

  @impl true
  def execute(_attrs, _data) do
    {:ok, %{result: "handled"}}
  end
end
