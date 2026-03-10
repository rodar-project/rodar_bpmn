defmodule RodarBpmn.Gateway.ComplexTest do
  use ExUnit.Case, async: true

  alias RodarBpmn.{Context, Gateway.Complex}

  describe "fork (single incoming)" do
    test "releases token to all matching outgoing flows" do
      end1 = {:bpmn_event_end, %{id: "end1", incoming: ["f1"], outgoing: []}}
      end2 = {:bpmn_event_end, %{id: "end2", incoming: ["f2"], outgoing: []}}

      f1 =
        {:bpmn_sequence_flow,
         %{
           id: "f1",
           sourceRef: "gw",
           targetRef: "end1",
           conditionExpression: nil,
           isImmediate: nil
         }}

      f2 =
        {:bpmn_sequence_flow,
         %{
           id: "f2",
           sourceRef: "gw",
           targetRef: "end2",
           conditionExpression: nil,
           isImmediate: nil
         }}

      process = %{"f1" => f1, "f2" => f2, "end1" => end1, "end2" => end2}
      {:ok, context} = Context.start_link(process, %{})

      gw = {:bpmn_gateway_complex, %{id: "gw", incoming: ["in"], outgoing: ["f1", "f2"]}}
      assert {:ok, ^context} = Complex.token_in(gw, context)
    end

    test "uses default flow when no conditions match" do
      end1 = {:bpmn_event_end, %{id: "end1", incoming: ["f_default"], outgoing: []}}

      f1 =
        {:bpmn_sequence_flow,
         %{
           id: "f1",
           sourceRef: "gw",
           targetRef: "end1",
           conditionExpression: {:bpmn_expression, {"elixir", "false"}},
           isImmediate: nil
         }}

      f_default =
        {:bpmn_sequence_flow,
         %{
           id: "f_default",
           sourceRef: "gw",
           targetRef: "end1",
           conditionExpression: nil,
           isImmediate: nil
         }}

      process = %{"f1" => f1, "f_default" => f_default, "end1" => end1}
      {:ok, context} = Context.start_link(process, %{})

      gw =
        {:bpmn_gateway_complex,
         %{id: "gw", incoming: ["in"], outgoing: ["f1", "f_default"], default: "f_default"}}

      assert {:ok, ^context} = Complex.token_in(gw, context)
    end

    test "returns error when no conditions match and no default" do
      f1 =
        {:bpmn_sequence_flow,
         %{
           id: "f1",
           sourceRef: "gw",
           targetRef: "end1",
           conditionExpression: {:bpmn_expression, {"elixir", "false"}},
           isImmediate: nil
         }}

      process = %{"f1" => f1}
      {:ok, context} = Context.start_link(process, %{})

      gw = {:bpmn_gateway_complex, %{id: "gw", incoming: ["in"], outgoing: ["f1"]}}
      assert {:error, msg} = Complex.token_in(gw, context)
      assert msg =~ "no matching condition"
    end
  end

  describe "join (multiple incoming)" do
    test "waits for all incoming tokens" do
      end1 = {:bpmn_event_end, %{id: "end1", incoming: ["f_out"], outgoing: []}}

      f_out =
        {:bpmn_sequence_flow,
         %{
           id: "f_out",
           sourceRef: "gw",
           targetRef: "end1",
           conditionExpression: nil,
           isImmediate: nil
         }}

      process = %{"f_out" => f_out, "end1" => end1}
      {:ok, context} = Context.start_link(process, %{})

      gw =
        {:bpmn_gateway_complex, %{id: "gw", incoming: ["in1", "in2"], outgoing: ["f_out"]}}

      # First token — should wait
      assert {:ok, ^context} = Complex.token_in(gw, context, "in1")

      # Second token — should release
      assert {:ok, ^context} = Complex.token_in(gw, context, "in2")
    end
  end

  describe "dispatch via RodarBpmn.execute/2" do
    test "dispatches complex gateway correctly" do
      end_event = {:bpmn_event_end, %{id: "end", incoming: ["flow_out"], outgoing: []}}

      flow_out =
        {:bpmn_sequence_flow,
         %{
           id: "flow_out",
           sourceRef: "gw",
           targetRef: "end",
           conditionExpression: nil,
           isImmediate: nil
         }}

      process = %{"flow_out" => flow_out, "end" => end_event}
      {:ok, context} = Context.start_link(process, %{})

      gw = {:bpmn_gateway_complex, %{id: "gw", incoming: ["in"], outgoing: ["flow_out"]}}
      assert {:ok, ^context} = RodarBpmn.execute(gw, context)
    end
  end
end
