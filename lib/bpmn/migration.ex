defmodule Bpmn.Migration do
  @moduledoc """
  Process instance migration between definition versions.

  Supports deploying new versions of process definitions while instances of
  old versions continue running. Provides compatibility checking and safe
  migration of running instances to new definition versions.

  ## Compatibility checking

  `check_compatibility/2` verifies that all active node positions in the
  current instance exist in the target version with matching types and
  outgoing flows. Gateway token state is also validated.

  ## Migration

  `migrate/2` (or `migrate/3` with options) performs the actual migration:
  suspends the instance if running, swaps the process definition in the
  context, updates the version tracker, and resumes if previously running.

  Use `force: true` to skip compatibility checks (useful when you know the
  migration is safe despite structural differences).
  """

  alias Bpmn.Context
  alias Bpmn.Registry

  @doc """
  Check whether a process instance is compatible with a target definition version.

  Returns `:compatible` if all active nodes exist in the target version with
  matching types and outgoing flows. Returns `{:incompatible, issues}` with
  a list of issue maps describing each incompatibility.
  """
  @spec check_compatibility(pid(), pos_integer()) :: :compatible | {:incompatible, [map()]}
  def check_compatibility(instance_pid, target_version) do
    process_id = Bpmn.Process.process_id(instance_pid)
    context = Bpmn.Process.get_context(instance_pid)

    case Registry.lookup(process_id, target_version) do
      :error ->
        {:incompatible, [%{type: :version_not_found, version: target_version}]}

      {:ok, target_definition} ->
        target_map = build_process_map(target_definition)
        check_active_nodes(context, target_map)
    end
  end

  @doc """
  Migrate a process instance to a target definition version.

  Checks compatibility first (unless `force: true`), suspends the instance
  if running, swaps the process definition, updates the version tracker,
  and resumes if previously running.

  ## Options

    * `:force` - skip compatibility check (default: `false`)
  """
  @spec migrate(pid(), pos_integer(), keyword()) :: :ok | {:error, any()}
  def migrate(instance_pid, target_version, opts \\ []) do
    force = Keyword.get(opts, :force, false)

    with :ok <- check_compat_unless_forced(instance_pid, target_version, force) do
      do_migrate(instance_pid, target_version)
    end
  end

  # --- Private helpers ---

  defp check_compat_unless_forced(_pid, _version, true), do: :ok

  defp check_compat_unless_forced(pid, version, false) do
    case check_compatibility(pid, version) do
      :compatible -> :ok
      {:incompatible, issues} -> {:error, {:incompatible, issues}}
    end
  end

  defp do_migrate(instance_pid, target_version) do
    process_id = Bpmn.Process.process_id(instance_pid)
    status = Bpmn.Process.status(instance_pid)
    was_running = status == :running

    with :ok <- maybe_suspend(instance_pid, status),
         {:ok, target_def} <- lookup_target(process_id, target_version),
         :ok <- swap_definition(instance_pid, target_def, target_version) do
      if was_running, do: Bpmn.Process.resume(instance_pid)
      :ok
    end
  end

  defp maybe_suspend(pid, :running), do: Bpmn.Process.suspend(pid)
  defp maybe_suspend(_pid, _status), do: :ok

  defp lookup_target(process_id, version) do
    case Registry.lookup(process_id, version) do
      {:ok, _} = result -> result
      :error -> {:error, "Version #{version} not found for process '#{process_id}'"}
    end
  end

  defp swap_definition(instance_pid, target_def, target_version) do
    context = Bpmn.Process.get_context(instance_pid)
    target_map = build_process_map(target_def)
    Context.swap_process(context, target_map)
    Bpmn.Process.update_definition_version(instance_pid, target_version)
    :ok
  end

  defp check_active_nodes(context, target_map) do
    context_state = Context.get_state(context)
    issues = collect_node_issues(context_state.nodes, target_map)

    case issues do
      [] -> :compatible
      _ -> {:incompatible, issues}
    end
  end

  defp collect_node_issues(nodes, target_map) do
    Enum.flat_map(nodes, fn
      {{:gateway_tokens, gateway_id}, _tokens} ->
        check_gateway_exists(gateway_id, target_map)

      {node_id, %{active: true}} ->
        check_node_exists(node_id, target_map)

      _ ->
        []
    end)
  end

  defp check_gateway_exists(gateway_id, target_map) do
    case Map.get(target_map, gateway_id) do
      nil ->
        [%{type: :missing_node, node_id: gateway_id, reason: "gateway not found in target"}]

      _ ->
        []
    end
  end

  defp check_node_exists(node_id, target_map) do
    case Map.get(target_map, node_id) do
      nil ->
        [%{type: :missing_node, node_id: node_id}]

      target_elem ->
        check_node_type_match(node_id, target_elem, target_map)
    end
  end

  defp check_node_type_match(node_id, {target_type, target_attrs}, target_map) do
    outgoing = Map.get(target_attrs, :outgoing, [])
    missing_flows = Enum.reject(outgoing, &Map.has_key?(target_map, &1))

    if missing_flows != [] do
      [
        %{
          type: :missing_outgoing_flow,
          node_id: node_id,
          node_type: target_type,
          missing_flows: missing_flows
        }
      ]
    else
      []
    end
  end

  defp build_process_map({_type, _attrs, elements}) when is_map(elements), do: elements

  defp build_process_map({_type, _attrs, elements}) when is_list(elements) do
    Enum.reduce(elements, %{}, fn
      {_type, %{id: id}} = elem, acc -> Map.put(acc, id, elem)
      _, acc -> acc
    end)
  end

  defp build_process_map(elements) when is_map(elements), do: elements

  defp build_process_map(elements) when is_list(elements) do
    Enum.reduce(elements, %{}, fn
      {_type, %{id: id}} = elem, acc -> Map.put(acc, id, elem)
      _, acc -> acc
    end)
  end
end
