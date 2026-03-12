defmodule Rodar.Gateway.InclusiveTest do
  use ExUnit.Case, async: true

  alias Rodar.{Context, Gateway.Inclusive}

  defp make_flow(id, target, condition \\ nil) do
    {:bpmn_sequence_flow,
     %{
       id: id,
       sourceRef: "gw",
       targetRef: target,
       conditionExpression: condition,
       isImmediate: nil
     }}
  end

  defp make_end(id, incoming_flow) do
    {:bpmn_event_end, %{id: id, incoming: [incoming_flow], outgoing: []}}
  end

  describe "fork (diverge)" do
    test "releases tokens to all flows whose conditions are true" do
      cond_true = {:bpmn_expression, {"elixir", "1 == 1"}}
      flow_a = make_flow("flow_a", "end_a", cond_true)
      flow_b = make_flow("flow_b", "end_b", cond_true)
      end_a = make_end("end_a", "flow_a")
      end_b = make_end("end_b", "flow_b")

      gateway =
        {:bpmn_gateway_inclusive, %{id: "gw", incoming: ["in"], outgoing: ["flow_a", "flow_b"]}}

      process = %{
        "flow_a" => flow_a,
        "flow_b" => flow_b,
        "end_a" => end_a,
        "end_b" => end_b
      }

      {:ok, context} = Context.start_link(process, %{})
      assert {:ok, ^context} = Inclusive.token_in(gateway, context)

      # Both paths should be recorded as activated
      paths = Context.get_activated_paths(context, "gw")
      assert length(paths) == 2
      assert "flow_a" in paths
      assert "flow_b" in paths
    end

    test "releases token only to flows with true conditions" do
      cond_true = {:bpmn_expression, {"elixir", "1 == 1"}}
      cond_false = {:bpmn_expression, {"elixir", "1 == 2"}}
      flow_a = make_flow("flow_a", "end_a", cond_true)
      flow_b = make_flow("flow_b", "end_b", cond_false)
      end_a = make_end("end_a", "flow_a")

      gateway =
        {:bpmn_gateway_inclusive, %{id: "gw", incoming: ["in"], outgoing: ["flow_a", "flow_b"]}}

      process = %{
        "flow_a" => flow_a,
        "flow_b" => flow_b,
        "end_a" => end_a
      }

      {:ok, context} = Context.start_link(process, %{})
      assert {:ok, ^context} = Inclusive.token_in(gateway, context)

      paths = Context.get_activated_paths(context, "gw")
      assert paths == ["flow_a"]
    end

    test "uses default flow when no conditions match" do
      cond_false = {:bpmn_expression, {"elixir", "1 == 2"}}
      flow_a = make_flow("flow_a", "end_a", cond_false)
      flow_default = make_flow("flow_default", "end_default")
      end_default = make_end("end_default", "flow_default")

      gateway =
        {:bpmn_gateway_inclusive,
         %{
           id: "gw",
           incoming: ["in"],
           outgoing: ["flow_a", "flow_default"],
           default: "flow_default"
         }}

      process = %{
        "flow_a" => flow_a,
        "flow_default" => flow_default,
        "end_default" => end_default
      }

      {:ok, context} = Context.start_link(process, %{})
      assert {:ok, ^context} = Inclusive.token_in(gateway, context)

      paths = Context.get_activated_paths(context, "gw")
      assert paths == ["flow_default"]
    end

    test "returns error when no conditions match and no default flow" do
      cond_false = {:bpmn_expression, {"elixir", "1 == 2"}}
      flow_a = make_flow("flow_a", "end_a", cond_false)

      gateway =
        {:bpmn_gateway_inclusive, %{id: "gw", incoming: ["in"], outgoing: ["flow_a"]}}

      process = %{"flow_a" => flow_a}

      {:ok, context} = Context.start_link(process, %{})

      assert {:error, "Inclusive gateway: no matching condition and no default flow"} =
               Inclusive.token_in(gateway, context)
    end

    test "unconditional flows (no condition) are treated as matching" do
      flow_a = make_flow("flow_a", "end_a")
      end_a = make_end("end_a", "flow_a")

      gateway =
        {:bpmn_gateway_inclusive, %{id: "gw", incoming: ["in"], outgoing: ["flow_a"]}}

      process = %{"flow_a" => flow_a, "end_a" => end_a}

      {:ok, context} = Context.start_link(process, %{})
      assert {:ok, ^context} = Inclusive.token_in(gateway, context)
    end
  end

  describe "join (converge)" do
    test "waits for all activated paths before continuing" do
      end_event = make_end("end", "flow_out")

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
        {:bpmn_gateway_inclusive,
         %{id: "gw_join", incoming: ["flow_a", "flow_b"], outgoing: ["flow_out"]}}

      process = %{"flow_out" => flow_out, "end" => end_event}
      {:ok, context} = Context.start_link(process, %{})

      # Record that only flow_a was activated at the fork
      Context.record_activated_paths(context, "gw_join", ["flow_a"])

      # flow_a arrives — should complete since it's the only activated path
      assert {:ok, ^context} =
               Inclusive.token_in(gateway, context, "flow_a")
    end

    test "waits for all incoming when no activation record exists" do
      end_event = make_end("end", "flow_out")

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
        {:bpmn_gateway_inclusive,
         %{id: "gw_join", incoming: ["flow_a", "flow_b"], outgoing: ["flow_out"]}}

      process = %{"flow_out" => flow_out, "end" => end_event}
      {:ok, context} = Context.start_link(process, %{})

      # No activation record — falls back to parallel behavior (wait for all)
      assert {:ok, ^context} =
               Inclusive.token_in(gateway, context, "flow_a")

      # First token waits
      assert Context.token_count(context, "gw_join") == 1

      # Second token completes the join
      assert {:ok, ^context} =
               Inclusive.token_in(gateway, context, "flow_b")
    end

    test "first token does not trigger outgoing flow when two are expected" do
      gateway =
        {:bpmn_gateway_inclusive,
         %{id: "gw_join", incoming: ["flow_a", "flow_b"], outgoing: ["flow_out"]}}

      # No flow_out in process — if join tried to release, it would error
      process = %{}
      {:ok, context} = Context.start_link(process, %{})

      # Both paths activated
      Context.record_activated_paths(context, "gw_join", ["flow_a", "flow_b"])

      assert {:ok, ^context} =
               Inclusive.token_in(gateway, context, "flow_a")
    end
  end

  describe "merge (pass-through)" do
    test "single outgoing flow passes token through" do
      end_event = make_end("end", "flow_out")

      flow_out =
        {:bpmn_sequence_flow,
         %{
           id: "flow_out",
           sourceRef: "gw",
           targetRef: "end",
           conditionExpression: nil,
           isImmediate: nil
         }}

      gateway =
        {:bpmn_gateway_inclusive, %{id: "gw", incoming: ["in"], outgoing: ["flow_out"]}}

      process = %{"flow_out" => flow_out, "end" => end_event}
      {:ok, context} = Context.start_link(process, %{})

      assert {:ok, ^context} = Inclusive.token_in(gateway, context)
    end
  end
end
