defmodule Bpmn.Observability do
  @moduledoc """
  Read-only query APIs for operational visibility into the BPMN engine.

  Queries existing supervisors and registries — no duplicated state.
  Useful for dashboards, health checks, and debugging.
  """

  @doc """
  List all running process instances with their status.

  Returns a list of maps with `:pid`, `:instance_id`, and `:status` for
  each process managed by `Bpmn.ProcessSupervisor`.
  """
  @spec running_instances() :: [map()]
  def running_instances do
    Bpmn.ProcessSupervisor
    |> DynamicSupervisor.which_children()
    |> Enum.flat_map(fn
      {:undefined, pid, :worker, _} when is_pid(pid) ->
        try do
          [build_instance_info(pid)]
        catch
          :exit, _ -> []
        end

      _ ->
        []
    end)
  end

  @doc """
  List process instances filtered by process ID and optional version.

  When called with just a process ID, returns all instances of that process
  across all versions. When called with a version, returns only instances
  running that specific version.
  """
  @spec instances_by_version(String.t(), pos_integer() | nil) :: [map()]
  def instances_by_version(process_id, version \\ nil) do
    running_instances()
    |> Enum.filter(fn instance ->
      instance.process_id == process_id and
        (is_nil(version) or instance.definition_version == version)
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
    context = Bpmn.Process.get_context(process_pid)
    Bpmn.Context.get_history(context)
  end

  @doc """
  Health check for the BPMN engine supervision tree.

  Returns a map with:
  - `:supervisor_alive` — whether `Bpmn.ProcessSupervisor` is alive
  - `:process_count` — number of process instances
  - `:context_count` — number of supervised contexts
  - `:registry_definitions` — number of registered process definitions
  - `:event_subscriptions` — number of event bus subscriptions
  """
  @spec health() :: map()
  def health do
    supervisor_alive = Process.whereis(Bpmn.ProcessSupervisor) != nil

    process_count =
      if supervisor_alive do
        Bpmn.ProcessSupervisor
        |> DynamicSupervisor.which_children()
        |> length()
      else
        0
      end

    context_count =
      case Process.whereis(Bpmn.ContextSupervisor) do
        nil ->
          0

        _pid ->
          Bpmn.ContextSupervisor
          |> DynamicSupervisor.which_children()
          |> length()
      end

    registry_definitions = length(Bpmn.Registry.list())

    event_subscriptions = Registry.count(Bpmn.EventRegistry)

    %{
      supervisor_alive: supervisor_alive,
      process_count: process_count,
      context_count: context_count,
      registry_definitions: registry_definitions,
      event_subscriptions: event_subscriptions
    }
  end

  # --- Private helpers ---

  defp build_instance_info(pid) do
    instance_id = Bpmn.Process.instance_id(pid)
    status = Bpmn.Process.status(pid)
    process_id = Bpmn.Process.process_id(pid)
    definition_version = Bpmn.Process.definition_version(pid)

    %{
      pid: pid,
      instance_id: instance_id,
      status: status,
      process_id: process_id,
      definition_version: definition_version
    }
  end
end
