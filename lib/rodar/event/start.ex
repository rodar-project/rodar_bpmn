defmodule RodarBpmn.Event.Start do
  @moduledoc """
  Handles BPMN start event elements.

  The start event is the entry point of a process. When a token arrives, it is
  released to the first outgoing sequence flow. If there are no outgoing flows
  (e.g., a degenerate single-node process), it returns `{:ok, context}` immediately.

  For message- and signal-triggered start events that automatically create process
  instances, see `RodarBpmn.Event.Start.Trigger`.

  ## Examples

      iex> {:ok, context} = RodarBpmn.Context.start_link(%{}, %{})
      iex> {:ok, pid} = RodarBpmn.Event.Start.token_in({:bpmn_event_start, %{outgoing: []}}, context)
      iex> context == pid
      true

      iex> {:ok, context} = RodarBpmn.Context.start_link(%{"to" => {:bpmn_activity_task_script, %{}}}, %{})
      iex> {:not_implemented} = RodarBpmn.Event.Start.token_in({:bpmn_event_start, %{outgoing: ["to"]}}, context)
      iex> true
      true

  """

  @doc """
  Accepts the initial token and releases it to the first outgoing sequence flow.
  """
  @spec token_in(RodarBpmn.element(), RodarBpmn.context()) :: RodarBpmn.result()
  def token_in({:bpmn_event_start, %{outgoing: []}}, context), do: {:ok, context}
  def token_in(elem, context), do: execute(elem, context)

  @doc """
  Execute the start event business logic
  """
  @spec execute(RodarBpmn.element(), RodarBpmn.context()) :: RodarBpmn.result()
  def execute({:bpmn_event_start, %{outgoing: outgoing} = _event}, context) do
    token_out(outgoing, context)
  end

  defp token_out(targets, context), do: RodarBpmn.release_token(targets, context)
end
