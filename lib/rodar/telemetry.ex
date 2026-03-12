defmodule Rodar.Telemetry do
  @moduledoc """
  Telemetry event definitions and helpers for BPMN engine instrumentation.

  Centralizes all telemetry event names and provides typed wrapper functions
  to emit events consistently. Uses `:telemetry.span/3` for timed operations.

  ## Events

  | Event | Measurements | Metadata |
  |-------|-------------|----------|
  | `[:rodar, :node, :start]` | `%{system_time}` | `%{node_id, node_type, token_id}` |
  | `[:rodar, :node, :stop]` | `%{duration}` | `%{node_id, node_type, token_id, result}` |
  | `[:rodar, :node, :exception]` | `%{duration}` | `%{node_id, node_type, token_id, kind, reason}` |
  | `[:rodar, :process, :start]` | `%{system_time}` | `%{instance_id, process_id}` |
  | `[:rodar, :process, :stop]` | `%{duration}` | `%{instance_id, process_id, status}` |
  | `[:rodar, :token, :create]` | `%{system_time}` | `%{token_id, parent_id, node_id}` |
  | `[:rodar, :event_bus, :publish]` | `%{system_time}` | `%{event_type, event_name, subscriber_count}` |
  | `[:rodar, :event_bus, :subscribe]` | `%{system_time}` | `%{event_type, event_name, node_id}` |

  ## Usage

  Attach to all events:

      :telemetry.attach_many("my-handler", Rodar.Telemetry.events(), &handler/4, nil)

  """

  @doc """
  Returns all telemetry event names emitted by the BPMN engine.
  """
  @spec events() :: [list(atom())]
  def events do
    [
      [:rodar, :node, :start],
      [:rodar, :node, :stop],
      [:rodar, :node, :exception],
      [:rodar, :process, :start],
      [:rodar, :process, :stop],
      [:rodar, :token, :create],
      [:rodar, :event_bus, :publish],
      [:rodar, :event_bus, :subscribe]
    ]
  end

  @doc """
  Wraps a function with a telemetry span for node execution.

  Emits `[:rodar, :node, :start]`, `[:rodar, :node, :stop]`, and
  `[:rodar, :node, :exception]` events automatically.
  """
  @spec node_span(map(), (-> any())) :: any()
  def node_span(metadata, fun) when is_map(metadata) and is_function(fun, 0) do
    :telemetry.span([:rodar, :node], metadata, fn ->
      result = fun.()
      {result, Map.put(metadata, :result, result_type(result))}
    end)
  end

  @doc """
  Emit a token creation event.
  """
  @spec token_created(Rodar.Token.t()) :: :ok
  def token_created(%Rodar.Token{} = token) do
    :telemetry.execute(
      [:rodar, :token, :create],
      %{system_time: System.system_time()},
      %{token_id: token.id, parent_id: token.parent_id, node_id: token.current_node}
    )
  end

  @doc """
  Emit a process started event.
  """
  @spec process_started(String.t(), String.t()) :: :ok
  def process_started(instance_id, process_id) do
    :telemetry.execute(
      [:rodar, :process, :start],
      %{system_time: System.system_time()},
      %{instance_id: instance_id, process_id: process_id}
    )
  end

  @doc """
  Emit a process stopped event with duration.
  """
  @spec process_stopped(String.t(), String.t(), atom(), integer()) :: :ok
  def process_stopped(instance_id, process_id, status, start_time) do
    duration = System.monotonic_time() - start_time

    :telemetry.execute(
      [:rodar, :process, :stop],
      %{duration: duration},
      %{instance_id: instance_id, process_id: process_id, status: status}
    )
  end

  @doc """
  Emit an event bus publish event.
  """
  @spec event_published(atom(), String.t(), non_neg_integer()) :: :ok
  def event_published(event_type, event_name, subscriber_count) do
    :telemetry.execute(
      [:rodar, :event_bus, :publish],
      %{system_time: System.system_time()},
      %{event_type: event_type, event_name: event_name, subscriber_count: subscriber_count}
    )
  end

  @doc """
  Emit an event bus subscribe event.
  """
  @spec event_subscribed(atom(), String.t(), String.t() | nil) :: :ok
  def event_subscribed(event_type, event_name, node_id) do
    :telemetry.execute(
      [:rodar, :event_bus, :subscribe],
      %{system_time: System.system_time()},
      %{event_type: event_type, event_name: event_name, node_id: node_id}
    )
  end

  defp result_type({:ok, _}), do: :ok
  defp result_type({:error, _}), do: :error
  defp result_type({:manual, _}), do: :manual
  defp result_type({:fatal, _}), do: :fatal
  defp result_type({:not_implemented}), do: :not_implemented
  defp result_type(_), do: :unknown
end
