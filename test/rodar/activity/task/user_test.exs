defmodule Rodar.Activity.Task.UserTest do
  use ExUnit.Case, async: true

  alias Rodar.{Activity.Task.User, Context}

  doctest Rodar.Activity.Task.User

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
        {:bpmn_activity_task_user,
         %{id: "task_1", name: "Approve Request", outgoing: ["flow_out"]}}

      assert {:manual, task_data} = User.token_in(elem, context)
      assert task_data.id == "task_1"
      assert task_data.name == "Approve Request"
      assert task_data.context == context

      meta = Context.get_meta(context, "task_1")
      assert meta.active == true
      assert meta.completed == false
    end
  end

  describe "resume/3" do
    test "merges input data into context and releases token" do
      process = build_process()
      {:ok, context} = Context.start_link(process, %{})

      elem =
        {:bpmn_activity_task_user,
         %{id: "task_1", name: "Approve Request", outgoing: ["flow_out"]}}

      {:manual, _task_data} = User.token_in(elem, context)

      # Resume with user input
      assert {:ok, ^context} =
               User.resume(elem, context, %{approved: true})

      assert Context.get_data(context, :approved) == true

      meta = Context.get_meta(context, "task_1")
      assert meta.active == false
      assert meta.completed == true
    end
  end
end
