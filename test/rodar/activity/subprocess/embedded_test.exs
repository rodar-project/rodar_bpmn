defmodule Rodar.Activity.Subprocess.EmbeddedTest.SubprocessHandler do
  @behaviour Rodar.Activity.Task.Service.Handler

  @impl true
  def execute(_attrs, _data) do
    {:ok, %{from_subprocess: true}}
  end
end

defmodule Rodar.Activity.Subprocess.EmbeddedTest do
  use ExUnit.Case, async: true

  alias Rodar.{Activity.Subprocess.Embedded, Context}
  alias Rodar.Activity.Subprocess.EmbeddedTest.SubprocessHandler

  doctest Rodar.Activity.Subprocess.Embedded

  defp build_nested_elements do
    start = {:bpmn_event_start, %{id: "sub_start", incoming: [], outgoing: ["sub_flow"]}}
    sub_end = {:bpmn_event_end, %{id: "sub_end", incoming: ["sub_flow"], outgoing: []}}

    sub_flow =
      {:bpmn_sequence_flow,
       %{
         id: "sub_flow",
         sourceRef: "sub_start",
         targetRef: "sub_end",
         conditionExpression: nil,
         isImmediate: nil
       }}

    %{"sub_start" => start, "sub_end" => sub_end, "sub_flow" => sub_flow}
  end

  defp build_parent_process do
    end_event = {:bpmn_event_end, %{id: "end", incoming: ["flow_out"], outgoing: []}}

    flow_out =
      {:bpmn_sequence_flow,
       %{
         id: "flow_out",
         sourceRef: "sub",
         targetRef: "end",
         conditionExpression: nil,
         isImmediate: nil
       }}

    %{"flow_out" => flow_out, "end" => end_event}
  end

  describe "token_in/2" do
    test "linear subprocess completes and releases token to parent" do
      nested = build_nested_elements()
      process = build_parent_process()
      {:ok, context} = Context.start_link(process, %{})

      elem =
        {:bpmn_activity_subprocess_embeded,
         %{id: "sub", outgoing: ["flow_out"], elements: nested}}

      assert {:ok, ^context} =
               Embedded.token_in(elem, context)

      meta = Context.get_meta(context, "sub")
      assert meta.active == false
      assert meta.completed == true
    end

    test "nested task writes data visible after subprocess completes" do
      # Build nested process with a service task that writes data
      start = {:bpmn_event_start, %{id: "sub_start", incoming: [], outgoing: ["to_task"]}}

      to_task =
        {:bpmn_sequence_flow,
         %{
           id: "to_task",
           sourceRef: "sub_start",
           targetRef: "sub_task",
           conditionExpression: nil,
           isImmediate: nil
         }}

      sub_task =
        {:bpmn_activity_task_service,
         %{
           id: "sub_task",
           incoming: ["to_task"],
           outgoing: ["to_end"],
           handler: SubprocessHandler
         }}

      to_end =
        {:bpmn_sequence_flow,
         %{
           id: "to_end",
           sourceRef: "sub_task",
           targetRef: "sub_end",
           conditionExpression: nil,
           isImmediate: nil
         }}

      sub_end = {:bpmn_event_end, %{id: "sub_end", incoming: ["to_end"], outgoing: []}}

      nested = %{
        "sub_start" => start,
        "to_task" => to_task,
        "sub_task" => sub_task,
        "to_end" => to_end,
        "sub_end" => sub_end
      }

      process = build_parent_process()
      {:ok, context} = Context.start_link(process, %{})

      elem =
        {:bpmn_activity_subprocess_embeded,
         %{id: "sub", outgoing: ["flow_out"], elements: nested}}

      assert {:ok, ^context} =
               Embedded.token_in(elem, context)

      # Data written by nested task should be visible in parent context
      assert Context.get_data(context, :from_subprocess) == true
    end

    test "restores parent process after execution" do
      nested = build_nested_elements()
      process = build_parent_process()
      {:ok, context} = Context.start_link(process, %{})

      elem =
        {:bpmn_activity_subprocess_embeded,
         %{id: "sub", outgoing: ["flow_out"], elements: nested}}

      {:ok, ^context} = Embedded.token_in(elem, context)

      # Parent process should be restored
      current_process = Context.get(context, :process)
      assert Map.has_key?(current_process, "flow_out")
      assert Map.has_key?(current_process, "end")
    end

    test "returns error when no start event in nested elements" do
      nested = %{
        "sub_end" => {:bpmn_event_end, %{id: "sub_end", incoming: [], outgoing: []}}
      }

      process = build_parent_process()
      {:ok, context} = Context.start_link(process, %{})

      elem =
        {:bpmn_activity_subprocess_embeded,
         %{id: "sub", outgoing: ["flow_out"], elements: nested}}

      assert {:error, "Embedded subprocess 'sub': no start event found"} =
               Embedded.token_in(elem, context)
    end
  end
end
