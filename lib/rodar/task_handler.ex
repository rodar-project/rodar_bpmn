defmodule Rodar.TaskHandler do
  @moduledoc """
  Behaviour for custom task handlers.

  Implement this behaviour to register custom task types or override
  specific task instances in the BPMN execution engine.

  ## Example

      defmodule MyApp.ApprovalHandler do
        @behaviour Rodar.TaskHandler

        @impl true
        def token_in({_type, %{id: id}} = _element, context) do
          Rodar.Context.put_data(context, "approved_by", id)
          {:ok, context}
        end
      end

      # Register for a custom type atom
      Rodar.TaskRegistry.register(:my_custom_task, MyApp.ApprovalHandler)

      # Or register for a specific task ID
      Rodar.TaskRegistry.register("Task_approval_1", MyApp.ApprovalHandler)

  """

  @callback token_in(element :: Rodar.element(), context :: Rodar.context()) ::
              Rodar.result()
end
