defmodule Bpmn.Activity.Task.Script do
  @moduledoc """
  Handle passing the token through a script task element.

  Executes an inline script defined on the BPMN element. The script language
  and content come from the element's attributes. Results are written back
  to the context under the task's output variable(s).

  Currently supports:
  - `"elixir"` — Evaluates via `Code.eval_string/2` with context data bindings
  - `"javascript"` / `"nodejs"` — Delegates to the Node.js port

  ## Examples

      iex> end_event = {:bpmn_event_end, %{id: "end", incoming: ["flow_out"], outgoing: []}}
      iex> flow_out = {:bpmn_sequence_flow, %{id: "flow_out", sourceRef: "task", targetRef: "end", conditionExpression: nil, isImmediate: nil}}
      iex> elem = {:bpmn_activity_task_script, %{id: "task", outgoing: ["flow_out"], type: "elixir", script: "2 + 2"}}
      iex> process = %{"flow_out" => flow_out, "end" => end_event}
      iex> {:ok, context} = Bpmn.Context.start_link(process, %{})
      iex> {:ok, ^context} = Bpmn.Activity.Task.Script.token_in(elem, context)
      iex> Bpmn.Context.get_data(context, :script_result)
      4

  """

  @doc """
  Receive the token for the element and execute the script.
  """
  @spec token_in(Bpmn.element(), Bpmn.context()) :: Bpmn.result()
  def token_in(elem, context), do: execute(elem, context)

  @doc """
  Execute the script task business logic.
  """
  @spec execute(Bpmn.element(), Bpmn.context()) :: Bpmn.result()
  def execute(
        {:bpmn_activity_task_script, %{outgoing: outgoing, type: type, script: script} = attrs},
        context
      ) do
    data = Bpmn.Context.get(context, :data)
    output_var = Map.get(attrs, :output_variable, :script_result)

    case run_script(type, script, data) do
      {:ok, result} ->
        Bpmn.Context.put_data(context, output_var, result)
        token_out(outgoing, context)

      {:error, reason} ->
        {:error, reason}
    end
  end

  def execute(_elem, _context), do: {:not_implemented}

  defp token_out(targets, context), do: Bpmn.release_token(targets, context)

  defp run_script("elixir", script, data) do
    try do
      {result, _binding} = Code.eval_string(script, data: data)
      {:ok, result}
    rescue
      e -> {:error, Exception.message(e)}
    end
  end

  defp run_script(lang, script, data) when lang in ["javascript", "nodejs"] do
    try do
      result = Bpmn.Port.Nodejs.eval_string(script, data)
      {:ok, result}
    rescue
      e -> {:error, Exception.message(e)}
    end
  end

  defp run_script(lang, _script, _data) do
    {:error, "Unsupported script language: #{lang}"}
  end
end
