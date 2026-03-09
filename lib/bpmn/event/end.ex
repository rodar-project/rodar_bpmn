defmodule Bpmn.Event.End do
  @moduledoc """
  Handle passing the token through an end event element.

  Supports three types of end events:

  - **Plain end** — Normal completion. Returns `{:ok, context}`.
  - **Error end** — Sets error state in context. Returns `{:error, error_ref}`.
  - **Terminate end** — Signals all branches to stop. Returns `{:ok, context}`
    after marking the process as terminated.

  ## Examples

      iex> {:ok, context} = Bpmn.Context.start_link(%{}, %{})
      iex> {:ok, ^context} = Bpmn.Event.End.token_in({:bpmn_event_end, %{incoming: []}}, context)
      iex> true
      true

      iex> {:ok, context} = Bpmn.Context.start_link(%{}, %{})
      iex> elem = {:bpmn_event_end, %{id: "end_err", incoming: ["f1"], errorEventDefinition: {:bpmn_event_definition_error, %{errorRef: "Error_001"}}}}
      iex> {:error, "Error_001"} = Bpmn.Event.End.token_in(elem, context)
      iex> true
      true

      iex> {:ok, context} = Bpmn.Context.start_link(%{}, %{})
      iex> elem = {:bpmn_event_end, %{id: "end_term", incoming: ["f1"], terminateEventDefinition: %{}}}
      iex> {:ok, ^context} = Bpmn.Event.End.token_in(elem, context)
      iex> Bpmn.Context.get_meta(context, :terminated)
      true

  """

  @doc """
  Receive the token for the element and handle end event logic.
  """
  @spec token_in(Bpmn.element(), Bpmn.context()) :: Bpmn.result()
  def token_in({:bpmn_event_end, attrs} = _elem, context) do
    cond do
      has_error_definition?(attrs) ->
        handle_error(attrs, context)

      has_terminate_definition?(attrs) ->
        handle_terminate(context)

      true ->
        {:ok, context}
    end
  end

  defp has_error_definition?(attrs) do
    match?({:bpmn_event_definition_error, _}, Map.get(attrs, :errorEventDefinition))
  end

  defp has_terminate_definition?(attrs) do
    Map.get(attrs, :terminateEventDefinition) != nil
  end

  defp handle_error(attrs, context) do
    {:bpmn_event_definition_error, %{errorRef: error_ref}} = attrs.errorEventDefinition
    Bpmn.Context.put_meta(context, :error, error_ref)
    {:error, error_ref}
  end

  defp handle_terminate(context) do
    Bpmn.Context.put_meta(context, :terminated, true)
    {:ok, context}
  end
end
