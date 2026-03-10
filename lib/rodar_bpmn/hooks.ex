defmodule RodarBpmn.Hooks do
  @moduledoc """
  Per-context hook/listener system for observing BPMN execution.

  Hooks are observational-only — they cannot modify execution flow.
  They are stored per-context to avoid cross-process interference.

  ## Hook Events

  - `:before_node` — Called before a node is dispatched. Metadata: `%{node_id, node_type, token}`.
  - `:after_node` — Called after a node completes. Metadata: `%{node_id, node_type, token, result}`.
  - `:on_error` — Called when dispatch returns `{:error, _}`. Metadata: `%{node_id, error}`.
  - `:on_complete` — Called when an end event fires. Metadata: `%{node_id}`.

  ## Example

      {:ok, context} = RodarBpmn.Context.start_link(process, %{})
      RodarBpmn.Hooks.register(context, :before_node, fn meta ->
        IO.inspect(meta.node_id, label: "entering")
        :ok
      end)

  """

  @type hook_event :: :before_node | :after_node | :on_error | :on_complete
  @type hook_fn :: (map() -> :ok)

  @doc """
  Register a hook function for a specific event on the given context.

  Multiple hooks can be registered for the same event; they are called in order.
  """
  @spec register(pid(), hook_event(), hook_fn()) :: :ok
  def register(context, event, fun) when is_function(fun, 1) do
    hooks = RodarBpmn.Context.get_meta(context, :hooks) || %{}
    existing = Map.get(hooks, event, [])
    updated = Map.put(hooks, event, existing ++ [fun])
    RodarBpmn.Context.put_meta(context, :hooks, updated)
  end

  @doc """
  Remove all hooks for a specific event on the given context.
  """
  @spec unregister(pid(), hook_event()) :: :ok
  def unregister(context, event) do
    hooks = RodarBpmn.Context.get_meta(context, :hooks) || %{}
    updated = Map.delete(hooks, event)
    RodarBpmn.Context.put_meta(context, :hooks, updated)
  end

  @doc """
  Notify all registered hooks for an event. Gracefully no-ops if no hooks are registered.

  Hook exceptions are caught and logged to prevent breaking execution flow.
  """
  @spec notify(pid(), hook_event(), map()) :: :ok
  def notify(context, event, metadata) do
    hooks = RodarBpmn.Context.get_meta(context, :hooks) || %{}
    funs = Map.get(hooks, event, [])

    Enum.each(funs, fn fun ->
      try do
        fun.(metadata)
      rescue
        e ->
          require Logger
          Logger.warning("Hook #{event} raised: #{inspect(e)}")
      end
    end)

    :ok
  end
end
