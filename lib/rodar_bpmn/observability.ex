defmodule RodarBpmn.Observability do
  @moduledoc """
  Read-only query APIs for operational visibility into the BPMN engine.

  Queries existing supervisors and registries — no duplicated state.
  Useful for dashboards, health checks, and debugging.
  """

  @doc """
  List all running process instances with their status.

  Returns a list of maps with `:pid`, `:instance_id`, and `:status` for
  each process managed by `RodarBpmn.ProcessSupervisor`.
  """
  @spec running_instances() :: [map()]
  def running_instances do
    RodarBpmn.ProcessSupervisor
    |> DynamicSupervisor.which_children()
    |> Enum.flat_map(fn
      {:undefined, pid, :worker, _} when is_pid(pid) ->
        try do
          instance_id = RodarBpmn.Process.instance_id(pid)
          status = RodarBpmn.Process.status(pid)
          [%{pid: pid, instance_id: instance_id, status: status}]
        catch
          :exit, _ -> []
        end

      _ ->
        []
    end)
  end

  @doc """
  List process instances that are currently suspended (waiting for external input).
  """
  @spec waiting_instances() :: [map()]
  def waiting_instances do
    running_instances()
    |> Enum.filter(&(&1.status == :suspended))
  end

  @doc """
  Get the execution history for a process instance.
  """
  @spec execution_history(pid()) :: [map()]
  def execution_history(process_pid) do
    context = RodarBpmn.Process.get_context(process_pid)
    RodarBpmn.Context.get_history(context)
  end

  @doc """
  Health check for the BPMN engine supervision tree.

  Returns a map with:
  - `:supervisor_alive` — whether `RodarBpmn.ProcessSupervisor` is alive
  - `:process_count` — number of process instances
  - `:context_count` — number of supervised contexts
  - `:registry_definitions` — number of registered process definitions
  - `:event_subscriptions` — number of event bus subscriptions
  """
  @spec health() :: map()
  def health do
    supervisor_alive = Process.whereis(RodarBpmn.ProcessSupervisor) != nil

    process_count =
      if supervisor_alive do
        RodarBpmn.ProcessSupervisor
        |> DynamicSupervisor.which_children()
        |> length()
      else
        0
      end

    context_count =
      case Process.whereis(RodarBpmn.ContextSupervisor) do
        nil ->
          0

        _pid ->
          RodarBpmn.ContextSupervisor
          |> DynamicSupervisor.which_children()
          |> length()
      end

    registry_definitions = length(RodarBpmn.Registry.list())

    event_subscriptions = Registry.count(RodarBpmn.EventRegistry)

    %{
      supervisor_alive: supervisor_alive,
      process_count: process_count,
      context_count: context_count,
      registry_definitions: registry_definitions,
      event_subscriptions: event_subscriptions
    }
  end
end
