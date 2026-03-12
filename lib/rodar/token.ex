defmodule RodarBpmn.Token do
  @moduledoc """
  Token struct for tracking execution flow through BPMN processes.

  Tokens represent the point of execution within a process. They track
  which node is currently being executed and can form parent-child
  relationships when execution forks (e.g., at parallel gateways).
  """

  @type state :: :active | :completed | :waiting | :error

  @type t :: %__MODULE__{
          id: String.t(),
          current_node: String.t() | nil,
          state: state(),
          parent_id: String.t() | nil,
          created_at: integer()
        }

  defstruct [:id, :current_node, :parent_id, state: :active, created_at: nil]

  @doc """
  Create a new token with a generated UUID and timestamp.

  ## Options

    * `:current_node` - the node ID where the token starts
    * `:parent_id` - the parent token ID (for forked tokens)
    * `:state` - initial state (defaults to `:active`)

  ## Examples

      iex> token = RodarBpmn.Token.new()
      iex> is_binary(token.id) and byte_size(token.id) == 36
      true

      iex> token = RodarBpmn.Token.new(current_node: "start_1")
      iex> token.current_node
      "start_1"

      iex> token = RodarBpmn.Token.new()
      iex> token.state
      :active

      iex> token = RodarBpmn.Token.new()
      iex> is_integer(token.created_at)
      true
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    token =
      struct!(
        __MODULE__,
        Keyword.merge(
          [id: generate_id(), created_at: System.monotonic_time(:millisecond)],
          opts
        )
      )

    RodarBpmn.Telemetry.token_created(token)
    token
  end

  @doc """
  Fork a child token from a parent token.

  The child token gets a new ID and has its `parent_id` set to the parent's ID.
  The child inherits the parent's `current_node`.

  ## Examples

      iex> parent = RodarBpmn.Token.new(current_node: "gateway_1")
      iex> child = RodarBpmn.Token.fork(parent)
      iex> child.parent_id == parent.id
      true

      iex> parent = RodarBpmn.Token.new(current_node: "gateway_1")
      iex> child = RodarBpmn.Token.fork(parent)
      iex> child.id != parent.id
      true

      iex> parent = RodarBpmn.Token.new(current_node: "gateway_1")
      iex> child = RodarBpmn.Token.fork(parent)
      iex> child.current_node
      "gateway_1"
  """
  @spec fork(t()) :: t()
  def fork(%__MODULE__{} = parent) do
    new(parent_id: parent.id, current_node: parent.current_node)
  end

  defp generate_id do
    <<a::32, b::16, c::16, d::16, e::48>> = :crypto.strong_rand_bytes(16)

    [
      pad(a, 8),
      "-",
      pad(b, 4),
      "-",
      pad(c, 4),
      "-",
      pad(d, 4),
      "-",
      pad(e, 12)
    ]
    |> IO.iodata_to_binary()
  end

  defp pad(int, len) do
    int
    |> Integer.to_string(16)
    |> String.downcase()
    |> String.pad_leading(len, "0")
  end
end
