defmodule RodarBpmn.Event.Intermediate do
  @moduledoc """
  Handle passing the token through an intermediate event element.

  This module is kept for backward compatibility with the legacy
  `:bpmn_event_intermediate` tag. New code should use
  `RodarBpmn.Event.Intermediate.Throw` and `RodarBpmn.Event.Intermediate.Catch`.

    iex> RodarBpmn.Event.Intermediate.token_in({:bpmn_event_intermediate, %{}}, nil)
    {:not_implemented}

  """

  @doc """
  Receive the token for the element and decide if the business logic should be executed
  """
  @spec token_in(RodarBpmn.element(), RodarBpmn.context()) :: RodarBpmn.result()
  def token_in(_elem, _context), do: {:not_implemented}
end
