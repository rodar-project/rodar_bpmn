defmodule RodarBpmn.Activity.Task.ServiceTest do
  use ExUnit.Case, async: true

  alias RodarBpmn.{Activity.Task.Service, Context}

  doctest RodarBpmn.Activity.Task.Service

  defp build_process do
    end_event = {:bpmn_event_end, %{id: "end", incoming: ["flow_out"], outgoing: []}}

    flow_out =
      {:bpmn_sequence_flow,
       %{
         id: "flow_out",
         sourceRef: "task",
         targetRef: "end",
         conditionExpression: nil,
         isImmediate: nil
       }}

    %{"flow_out" => flow_out, "end" => end_event}
  end

  describe "with a handler that returns {:ok, map}" do
    test "invokes handler and merges result into context" do
      process = build_process()
      {:ok, context} = Context.start_link(process, %{})

      elem =
        {:bpmn_activity_task_service,
         %{
           id: "task",
           outgoing: ["flow_out"],
           handler: Service.TestHandler
         }}

      assert {:ok, ^context} = Service.token_in(elem, context)
      assert Context.get_data(context, :result) == "handled"
    end
  end

  describe "with a handler that returns {:error, reason}" do
    defmodule ErrorHandler do
      @moduledoc false
      @behaviour Service.Handler

      @impl true
      def execute(_attrs, _data), do: {:error, "something went wrong"}
    end

    test "returns the error" do
      process = build_process()
      {:ok, context} = Context.start_link(process, %{})

      elem =
        {:bpmn_activity_task_service,
         %{id: "task", outgoing: ["flow_out"], handler: ErrorHandler}}

      assert {:error, "something went wrong"} =
               Service.token_in(elem, context)
    end
  end

  describe "TaskRegistry fallback" do
    test "uses handler from TaskRegistry when no inline handler is present" do
      process = build_process()
      {:ok, context} = Context.start_link(process, %{})

      RodarBpmn.TaskRegistry.register("task", Service.TestHandler)

      elem =
        {:bpmn_activity_task_service, %{id: "task", outgoing: ["flow_out"]}}

      assert {:ok, ^context} = Service.token_in(elem, context)
      assert Context.get_data(context, :result) == "handled"

      RodarBpmn.TaskRegistry.unregister("task")
    end

    test "returns {:not_implemented} when no handler and no registry entry" do
      process = build_process()
      {:ok, context} = Context.start_link(process, %{})

      elem =
        {:bpmn_activity_task_service, %{id: "unregistered_task", outgoing: ["flow_out"]}}

      assert {:not_implemented} = Service.token_in(elem, context)
    end
  end

  describe "fallback" do
    test "returns {:not_implemented} for unrecognized element shape" do
      assert {:not_implemented} = Service.execute(:bad, nil)
    end
  end
end
