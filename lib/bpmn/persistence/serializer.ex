defmodule Bpmn.Persistence.Serializer do
  @moduledoc """
  Converts live process state into persistable snapshots and back.

  Handles non-serializable values (PIDs, timer refs, MapSets) by converting
  them during serialization and reconstituting them during deserialization.

  Uses Erlang term format (`:erlang.term_to_binary`/`binary_to_term`) which
  preserves tuples, atoms, and MapSets natively.
  """

  @doc """
  Build a snapshot map from process state components.
  """
  @spec snapshot(map()) :: map()
  def snapshot(state) do
    %{
      version: 1,
      instance_id: state.instance_id,
      process_id: state.process_id,
      definition_version: Map.get(state, :definition_version),
      status: state.status,
      root_token: serialize_token(state.root_token),
      context_state: serialize_context_state(state.context_state),
      dehydrated_at: System.system_time(:millisecond)
    }
  end

  @doc """
  Serialize a snapshot map to binary using Erlang term format.
  """
  @spec serialize(map()) :: binary()
  def serialize(snapshot) do
    :erlang.term_to_binary(snapshot)
  end

  @doc """
  Deserialize binary data back to a snapshot map.

  Uses `:safe` option to prevent atom creation from untrusted data.
  """
  @spec deserialize(binary()) :: map()
  def deserialize(binary) do
    :erlang.binary_to_term(binary, [:safe])
  end

  @doc """
  Convert a Token struct to a plain map for serialization.
  """
  @spec serialize_token(Bpmn.Token.t() | nil) :: map() | nil
  def serialize_token(nil), do: nil

  def serialize_token(%Bpmn.Token{} = token) do
    %{
      id: token.id,
      current_node: token.current_node,
      state: token.state,
      parent_id: token.parent_id,
      created_at: token.created_at
    }
  end

  @doc """
  Reconstruct a Token struct from a plain map.
  """
  @spec deserialize_token(map() | nil) :: Bpmn.Token.t() | nil
  def deserialize_token(nil), do: nil

  def deserialize_token(map) when is_map(map) do
    %Bpmn.Token{
      id: map.id,
      current_node: map.current_node,
      state: map.state,
      parent_id: map.parent_id,
      created_at: map.created_at
    }
  end

  @doc """
  Serialize context state, converting MapSets to sorted lists and stripping
  timer refs and PIDs from node metadata.
  """
  @spec serialize_context_state(map()) :: map()
  def serialize_context_state(state) do
    %{
      init: state.init,
      data: state.data,
      process: state.process,
      nodes: serialize_nodes(state.nodes),
      history: state.history
    }
  end

  @doc """
  Deserialize context state, converting sorted lists back to MapSets
  for gateway token entries.
  """
  @spec deserialize_context_state(map()) :: map()
  def deserialize_context_state(state) do
    %{
      init: state.init,
      data: state.data,
      process: state.process,
      nodes: deserialize_nodes(state.nodes),
      history: state.history
    }
  end

  defp serialize_nodes(nodes) do
    Map.new(nodes, fn
      {{:gateway_tokens, _gateway_id} = key, %MapSet{} = mapset} ->
        {key, MapSet.to_list(mapset) |> Enum.sort()}

      {key, %{timer_ref: _ref} = meta} ->
        {key, Map.delete(meta, :timer_ref)}

      {key, value} ->
        {key, value}
    end)
  end

  defp deserialize_nodes(nodes) do
    Map.new(nodes, fn
      {{:gateway_tokens, _gateway_id} = key, list} when is_list(list) ->
        {key, MapSet.new(list)}

      {key, value} ->
        {key, value}
    end)
  end
end
