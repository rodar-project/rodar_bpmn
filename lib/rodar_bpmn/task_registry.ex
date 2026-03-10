defmodule RodarBpmn.TaskRegistry do
  @moduledoc """
  Registry for custom task handlers.

  Maps task type atoms or task ID strings to handler modules implementing
  the `RodarBpmn.TaskHandler` behaviour. Lookup priority: task ID (string) first,
  then task type (atom).

  ## Examples

      iex> RodarBpmn.TaskRegistry.register(:my_task, MyHandler)
      :ok
      iex> {:ok, MyHandler} = RodarBpmn.TaskRegistry.lookup(:my_task)
      iex> RodarBpmn.TaskRegistry.unregister(:my_task)
      :ok

  """

  use GenServer

  # --- Client API ---

  @doc "Start the task registry GenServer."
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, %{}, name: name)
  end

  @doc """
  Register a handler module for a task type (atom) or task ID (string).
  """
  @spec register(atom() | String.t(), module()) :: :ok
  def register(key, handler_module) do
    GenServer.call(__MODULE__, {:register, key, handler_module})
  end

  @doc """
  Remove a handler registration.
  """
  @spec unregister(atom() | String.t()) :: :ok
  def unregister(key) do
    GenServer.call(__MODULE__, {:unregister, key})
  end

  @doc """
  Look up a handler by task type atom or task ID string.

  Returns `{:ok, module}` or `:error`.
  """
  @spec lookup(atom() | String.t()) :: {:ok, module()} | :error
  def lookup(key) do
    GenServer.call(__MODULE__, {:lookup, key})
  end

  @doc """
  List all registered handlers.

  Returns a list of `{key, module}` tuples.
  """
  @spec list() :: [{atom() | String.t(), module()}]
  def list do
    GenServer.call(__MODULE__, :list)
  end

  # --- GenServer Callbacks ---

  @impl true
  def init(state) do
    {:ok, state}
  end

  @impl true
  def handle_call({:register, key, handler_module}, _from, state) do
    {:reply, :ok, Map.put(state, key, handler_module)}
  end

  def handle_call({:unregister, key}, _from, state) do
    {:reply, :ok, Map.delete(state, key)}
  end

  def handle_call({:lookup, key}, _from, state) do
    case Map.fetch(state, key) do
      {:ok, module} -> {:reply, {:ok, module}, state}
      :error -> {:reply, :error, state}
    end
  end

  def handle_call(:list, _from, state) do
    {:reply, Enum.into(state, []), state}
  end
end
