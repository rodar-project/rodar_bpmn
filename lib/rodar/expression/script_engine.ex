defmodule Rodar.Expression.ScriptEngine do
  @moduledoc """
  Behaviour for pluggable script language engines.

  Implement this behaviour to add support for custom script languages in
  BPMN script tasks. The engine receives the script source text and a map
  of bindings (the current process data) and must return a result tuple.

  The built-in languages `"elixir"` and `"feel"` are handled directly by
  `Rodar.Activity.Task.Script`. Any other language string is resolved
  through `Rodar.Expression.ScriptRegistry`, which maps language names
  to modules implementing this behaviour.

  ## Implementing an Engine

      defmodule MyApp.LuaEngine do
        @behaviour Rodar.Expression.ScriptEngine

        @impl true
        def eval(script, bindings) do
          case Lua.eval(script, bindings) do
            {:ok, result} -> {:ok, result}
            {:error, reason} -> {:error, reason}
          end
        end
      end

  ## Registration

  Register the engine at application startup so it is available before
  any process instance executes:

      Rodar.Expression.ScriptRegistry.register("lua", MyApp.LuaEngine)

  Once registered, any BPMN script task with `type: "lua"` will delegate
  to `MyApp.LuaEngine.eval/2`.

  ## Companion Packages

  The following packages provide ready-made engine implementations:

  - `rodar_lua` -- Lua engine via Luerl (planned)
  - `rodar_python` -- Python engine via Erlport (planned)

  ## See Also

  - `Rodar.Expression.ScriptRegistry` -- runtime registration of engines
  - `Rodar.Activity.Task.Script` -- script task execution and language dispatch
  """

  @doc """
  Evaluate a script with the given bindings.

  Receives the script source text and a map of process data bindings.
  Returns `{:ok, result}` on success or `{:error, reason}` on failure.

  The `bindings` map contains the current process data (the same map
  returned by `Rodar.Context.get(context, :data)`).
  """
  @callback eval(script :: String.t(), bindings :: map()) :: {:ok, any()} | {:error, any()}
end
