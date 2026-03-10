defmodule RodarBpmn.Activity.Task.Script do
  @moduledoc """
  Handle passing the token through a script task element.

  Executes an inline script defined on the BPMN element. The script language
  and content come from the element's attributes. Results are written back
  to the context under the task's output variable(s).

  Supports `"elixir"` scripts (sandboxed AST evaluation) and `"feel"` scripts
  (FEEL expression language).

  ## Examples

      iex> end_event = {:bpmn_event_end, %{id: "end", incoming: ["flow_out"], outgoing: []}}
      iex> flow_out = {:bpmn_sequence_flow, %{id: "flow_out", sourceRef: "task", targetRef: "end", conditionExpression: nil, isImmediate: nil}}
      iex> elem = {:bpmn_activity_task_script, %{id: "task", outgoing: ["flow_out"], type: "elixir", script: "2 + 2"}}
      iex> process = %{"flow_out" => flow_out, "end" => end_event}
      iex> {:ok, context} = Context.start_link(process, %{})
      iex> {:ok, ^context} = RodarBpmn.Activity.Task.Script.token_in(elem, context)
      iex> Context.get_data(context, :script_result)
      4

  """

  alias RodarBpmn.Context
  alias RodarBpmn.Expression.Feel
  alias RodarBpmn.Expression.Sandbox

  @doc """
  Receive the token for the element and execute the script.
  """
  @spec token_in(RodarBpmn.element(), RodarBpmn.context()) :: RodarBpmn.result()
  def token_in(elem, context), do: execute(elem, context)

  @doc """
  Execute the script task business logic.
  """
  @spec execute(RodarBpmn.element(), RodarBpmn.context()) :: RodarBpmn.result()
  def execute(
        {:bpmn_activity_task_script, %{outgoing: outgoing, type: type, script: script} = attrs},
        context
      ) do
    data = Context.get(context, :data)
    output_var = Map.get(attrs, :output_variable, :script_result)

    case run_script(type, script, data) do
      {:ok, result} ->
        Context.put_data(context, output_var, result)
        token_out(outgoing, context)

      {:error, reason} ->
        {:error, reason}
    end
  end

  def execute(_elem, _context), do: {:not_implemented}

  defp token_out(targets, context), do: RodarBpmn.release_token(targets, context)

  defp run_script("elixir", {:bpmn_script, %{expression: script}}, data) do
    Sandbox.eval(script, %{"data" => data})
  end

  defp run_script("elixir", script, data) when is_binary(script) do
    Sandbox.eval(script, %{"data" => data})
  end

  defp run_script("feel", {:bpmn_script, %{expression: script}}, data) do
    Feel.eval(script, data)
  end

  defp run_script("feel", script, data) when is_binary(script) do
    Feel.eval(script, data)
  end

  defp run_script(lang, _script, _data) do
    {:error, "Unsupported script language: #{lang}. Only Elixir and FEEL are supported."}
  end
end
