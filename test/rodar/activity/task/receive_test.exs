defmodule Rodar.Activity.Task.ReceiveTest do
  use ExUnit.Case, async: true

  alias Rodar.{Activity.Task.Receive, Context}

  doctest Rodar.Activity.Task.Receive

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
    test "returns {:manual, task_data} and marks task as active" do
      process = build_process()
      {:ok, context} = Context.start_link(process, %{})

      elem =
        {:bpmn_activity_task_receive,
         %{id: "task_1", name: "Wait for Payment", outgoing: ["flow_out"]}}

      assert {:manual, task_data} = Receive.token_in(elem, context)
      assert task_data.id == "task_1"
      assert task_data.name == "Wait for Payment"
      assert task_data.context == context

      meta = Context.get_meta(context, "task_1")
      assert meta.active == true
      assert meta.completed == false
      assert meta.type == :receive_task
    end
  end

  describe "resume/3" do
    test "merges message data into context and releases token" do
      process = build_process()
      {:ok, context} = Context.start_link(process, %{})

      elem =
        {:bpmn_activity_task_receive,
         %{id: "task_1", name: "Wait for Payment", outgoing: ["flow_out"]}}

      {:manual, _task_data} = Receive.token_in(elem, context)

      assert {:ok, ^context} =
               Receive.resume(elem, context, %{payment_id: "PAY-123"})

      assert Context.get_data(context, :payment_id) == "PAY-123"

      meta = Context.get_meta(context, "task_1")
      assert meta.active == false
      assert meta.completed == true
    end
  end
end
