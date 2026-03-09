defmodule Bpmn.Activity.Task.ServiceTest do
  use ExUnit.Case, async: true

  doctest Bpmn.Activity.Task.Service

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
      {:ok, context} = Bpmn.Context.start_link(process, %{})

      elem =
        {:bpmn_activity_task_service,
         %{
           id: "task",
           outgoing: ["flow_out"],
           handler: Bpmn.Activity.Task.Service.TestHandler
         }}

      assert {:ok, ^context} = Bpmn.Activity.Task.Service.token_in(elem, context)
      assert Bpmn.Context.get_data(context, :result) == "handled"
    end
  end

  describe "with a handler that returns {:error, reason}" do
    defmodule ErrorHandler do
      @moduledoc false
      @behaviour Bpmn.Activity.Task.Service.Handler

      @impl true
      def execute(_attrs, _data), do: {:error, "something went wrong"}
    end

    test "returns the error" do
      process = build_process()
      {:ok, context} = Bpmn.Context.start_link(process, %{})

      elem =
        {:bpmn_activity_task_service,
         %{id: "task", outgoing: ["flow_out"], handler: ErrorHandler}}

      assert {:error, "something went wrong"} =
               Bpmn.Activity.Task.Service.token_in(elem, context)
    end
  end

  describe "fallback" do
    test "returns {:not_implemented} for unrecognized element shape" do
      assert {:not_implemented} = Bpmn.Activity.Task.Service.execute(:bad, nil)
    end
  end
end
