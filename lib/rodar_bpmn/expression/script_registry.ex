defmodule RodarBpmn.Expression.ScriptRegistry do
  @moduledoc """
  Registry for custom script language engines.

  Maps language strings (e.g., `"lua"`, `"python"`) to engine modules
  implementing the `RodarBpmn.Expression.ScriptEngine` behaviour. Used by
  `RodarBpmn.Activity.Task.Script` to resolve script languages beyond the
  built-in `"elixir"` and `"feel"` engines.

  This GenServer is started automatically as part of the application
  supervision tree. Register engines at application startup (e.g., in your
  `Application.start/2` callback) so they are available before process
  instances execute.

  ## Usage

      # Register an engine for a language
      RodarBpmn.Expression.ScriptRegistry.register("lua", MyApp.LuaEngine)

      # Look up an engine
      {:ok, MyApp.LuaEngine} = RodarBpmn.Expression.ScriptRegistry.lookup("lua")

      # List all registered engines
      RodarBpmn.Expression.ScriptRegistry.list()
      # => [{"lua", MyApp.LuaEngine}]

      # Remove a registration
      RodarBpmn.Expression.ScriptRegistry.unregister("lua")

  ## See Also

  - `RodarBpmn.Expression.ScriptEngine` -- behaviour that engine modules must implement
  - `RodarBpmn.TaskRegistry` -- analogous registry for custom task handlers
  """

  use GenServer

  # --- Client API ---

  @doc """
  Start the script registry GenServer.

  Accepts an optional `:name` keyword (defaults to `__MODULE__`).
  Normally started by the supervision tree -- you should not need to
  call this directly.
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, %{}, name: name)
  end

  @doc """
  Register an engine module for a script language string.

  The `engine_module` must implement the `RodarBpmn.Expression.ScriptEngine`
  behaviour. If a registration already exists for the given `language`, it
  is silently replaced.

  Returns `:ok`.
  """
  @spec register(String.t(), module()) :: :ok
  def register(language, engine_module) do
    GenServer.call(__MODULE__, {:register, language, engine_module})
  end

  @doc """
  Remove an engine registration for the given language string.

  Returns `:ok` regardless of whether the language was registered.
  """
  @spec unregister(String.t()) :: :ok
  def unregister(language) do
    GenServer.call(__MODULE__, {:unregister, language})
  end

  @doc """
  Look up the engine module for a language string.

  Returns `{:ok, module}` if a registration exists, or `:error` otherwise.
  Called internally by `RodarBpmn.Activity.Task.Script` when the script
  language is not `"elixir"` or `"feel"`.
  """
  @spec lookup(String.t()) :: {:ok, module()} | :error
  def lookup(language) do
    GenServer.call(__MODULE__, {:lookup, language})
  end

  @doc """
  List all registered script engines.

  Returns a list of `{language, module}` tuples.
  """
  @spec list() :: [{String.t(), module()}]
  def list do
    GenServer.call(__MODULE__, :list)
  end

  # --- GenServer Callbacks ---

  @impl true
  def init(state) do
    {:ok, state}
  end

  @impl true
  def handle_call({:register, language, engine_module}, _from, state) do
    {:reply, :ok, Map.put(state, language, engine_module)}
  end

  def handle_call({:unregister, language}, _from, state) do
    {:reply, :ok, Map.delete(state, language)}
  end

  def handle_call({:lookup, language}, _from, state) do
    case Map.fetch(state, language) do
      {:ok, module} -> {:reply, {:ok, module}, state}
      :error -> {:reply, :error, state}
    end
  end

  def handle_call(:list, _from, state) do
    {:reply, Enum.into(state, []), state}
  end
end
