defmodule RodarBpmn.Gateway.ParallelTest do
  use ExUnit.Case, async: true

  alias RodarBpmn.{Context, Gateway.Parallel}

  describe "fork (diverge)" do
    test "releases tokens to all outgoing flows" do
      end_a = {:bpmn_event_end, %{id: "end_a", incoming: ["flow_a"], outgoing: []}}
      end_b = {:bpmn_event_end, %{id: "end_b", incoming: ["flow_b"], outgoing: []}}

      flow_a =
        {:bpmn_sequence_flow,
         %{
           id: "flow_a",
           sourceRef: "gw",
           targetRef: "end_a",
           conditionExpression: nil,
           isImmediate: nil
         }}

      flow_b =
        {:bpmn_sequence_flow,
         %{
           id: "flow_b",
           sourceRef: "gw",
           targetRef: "end_b",
           conditionExpression: nil,
           isImmediate: nil
         }}

      gateway =
        {:bpmn_gateway_parallel, %{id: "gw", incoming: ["in"], outgoing: ["flow_a", "flow_b"]}}

      process = %{
        "flow_a" => flow_a,
        "flow_b" => flow_b,
        "end_a" => end_a,
        "end_b" => end_b
      }

      {:ok, context} = Context.start_link(process, %{})

      assert {:ok, ^context} = Parallel.token_in(gateway, context)
    end
  end

  describe "join (converge)" do
    test "waits for all incoming tokens before continuing" do
      end_event = {:bpmn_event_end, %{id: "end", incoming: ["flow_out"], outgoing: []}}

      flow_out =
        {:bpmn_sequence_flow,
         %{
           id: "flow_out",
           sourceRef: "gw_join",
           targetRef: "end",
           conditionExpression: nil,
           isImmediate: nil
         }}

      gateway =
        {:bpmn_gateway_parallel,
         %{id: "gw_join", incoming: ["flow_a", "flow_b"], outgoing: ["flow_out"]}}

      process = %{"flow_out" => flow_out, "end" => end_event}

      {:ok, context} = Context.start_link(process, %{})

      # First token arrives — should wait
      assert {:ok, ^context} =
               Parallel.token_in(gateway, context, "flow_a")

      # Second token arrives — should release
      assert {:ok, ^context} =
               Parallel.token_in(gateway, context, "flow_b")
    end

    test "first token does not trigger outgoing flow" do
      gateway =
        {:bpmn_gateway_parallel,
         %{id: "gw_join", incoming: ["flow_a", "flow_b"], outgoing: ["flow_out"]}}

      # No flow_out in process — if the join tried to release, it would error
      process = %{}
      {:ok, context} = Context.start_link(process, %{})

      # First token should just wait, not try to release
      assert {:ok, ^context} =
               Parallel.token_in(gateway, context, "flow_a")
    end
  end
end
