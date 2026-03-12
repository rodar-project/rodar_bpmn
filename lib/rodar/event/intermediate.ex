defmodule Rodar.Event.Intermediate do
  @moduledoc """
  Stub handler for the generic `:bpmn_event_intermediate` element type.

  Always returns `{:not_implemented}`. The BPMN 2.0 parser splits intermediate
  events into their specific types, so this module only handles the rare case of
  an unresolved generic tag. Use `Rodar.Event.Intermediate.Throw` and
  `Rodar.Event.Intermediate.Catch` for actual intermediate event handling.

  ## Examples

      iex> Rodar.Event.Intermediate.token_in({:bpmn_event_intermediate, %{}}, nil)
      {:not_implemented}

  """

  @doc """
  Returns `{:not_implemented}` for generic intermediate events.
  """
  @spec token_in(Rodar.element(), Rodar.context()) :: Rodar.result()
  def token_in(_elem, _context), do: {:not_implemented}
end
