defmodule Bpmn.Activity.Task.Service do
  @moduledoc """
  Handle passing the token through a service task element.

  A service task invokes a user-defined callback module that implements
  the `Bpmn.Activity.Task.Service.Handler` behaviour. The handler receives
  the task attributes and context data, and returns a result map that gets
  merged into the context.

  ## Handler Behaviour

  Implement the `execute/2` callback:

      defmodule MyApp.CheckInventory do
        @behaviour Bpmn.Activity.Task.Service.Handler

        @impl true
        def execute(attrs, data) do
          # ... business logic ...
          {:ok, %{in_stock: true}}
        end
      end

  Then reference the module in the BPMN element via the `:handler` attribute.

  ## Examples

      iex> end_event = {:bpmn_event_end, %{id: "end", incoming: ["flow_out"], outgoing: []}}
      iex> flow_out = {:bpmn_sequence_flow, %{id: "flow_out", sourceRef: "task", targetRef: "end", conditionExpression: nil, isImmediate: nil}}
      iex> elem = {:bpmn_activity_task_service, %{id: "task", outgoing: ["flow_out"], handler: Bpmn.Activity.Task.Service.TestHandler}}
      iex> process = %{"flow_out" => flow_out, "end" => end_event}
      iex> {:ok, context} = Bpmn.Context.start_link(process, %{})
      iex> {:ok, ^context} = Bpmn.Activity.Task.Service.token_in(elem, context)
      iex> Bpmn.Context.get_data(context, :result)
      "handled"

  """

  @doc """
  Receive the token for the element and invoke the service handler.
  """
  @spec token_in(Bpmn.element(), Bpmn.context()) :: Bpmn.result()
  def token_in(elem, context), do: execute(elem, context)

  @doc """
  Execute the service task business logic.
  """
  @spec execute(Bpmn.element(), Bpmn.context()) :: Bpmn.result()
  def execute(
        {:bpmn_activity_task_service, %{outgoing: outgoing, handler: handler} = attrs},
        context
      ) do
    data = Bpmn.Context.get(context, :data)

    case handler.execute(attrs, data) do
      {:ok, result} when is_map(result) ->
        Enum.each(result, fn {key, value} ->
          Bpmn.Context.put_data(context, key, value)
        end)

        Bpmn.release_token(outgoing, context)

      {:ok, _result} ->
        Bpmn.release_token(outgoing, context)

      {:error, reason} ->
        {:error, reason}
    end
  end

  def execute(_elem, _context), do: {:not_implemented}
end
