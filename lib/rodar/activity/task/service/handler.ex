defmodule Rodar.Activity.Task.Service.Handler do
  @moduledoc """
  Behaviour for service task handlers.

  Implement `execute/2` to define the business logic for a service task.
  The callback receives the task element attributes and the current context data,
  and should return `{:ok, result_map}` or `{:error, reason}`.
  """

  @callback execute(attrs :: map(), data :: map()) ::
              {:ok, map()} | {:error, String.t()}
end
