defmodule RodarBpmn.Activity.Task.SendTest do
  use ExUnit.Case, async: true

  alias RodarBpmn.{Activity.Task.Send, Context}

  doctest RodarBpmn.Activity.Task.Send

  defp build_process do
    end_event = {:bpmn_event_end, %{id: "end", incoming: ["flow_out"], outgoing: []}}

    flow_out =
      {:bpmn_sequence_flow,
       %{
         id: "flow_out",
         sourceRef: "task_1",
         targetRef: "end",
         conditionExpression: nil,
         isImmediate: nil
       }}

    %{"flow_out" => flow_out, "end" => end_event}
  end

  describe "token_in/2" do
    test "stores message metadata and releases token immediately" do
      process = build_process()
      {:ok, context} = Context.start_link(process, %{})

      elem =
        {:bpmn_activity_task_send, %{id: "task_1", name: "Send Invoice", outgoing: ["flow_out"]}}

      assert {:ok, ^context} = Send.token_in(elem, context)

      meta = Context.get_meta(context, "task_1")
      assert meta.completed == true
      assert meta.active == false
      assert meta.type == :send_task
      assert meta.message_name == "Send Invoice"
    end

    test "completes without name attribute" do
      process = build_process()
      {:ok, context} = Context.start_link(process, %{})

      elem = {:bpmn_activity_task_send, %{id: "task_1", outgoing: ["flow_out"]}}

      assert {:ok, ^context} = Send.token_in(elem, context)

      meta = Context.get_meta(context, "task_1")
      assert meta.message_name == nil
    end
  end
end
