defmodule Rodar.Gateway.ExclusiveTest do
  use ExUnit.Case, async: true

  alias Rodar.{Context, Gateway.Exclusive}

  describe "diverging (split)" do
    test "routes token to the first flow whose condition is true" do
      end_a = {:bpmn_event_end, %{id: "end_a", incoming: ["flow_a"], outgoing: []}}
      end_b = {:bpmn_event_end, %{id: "end_b", incoming: ["flow_b"], outgoing: []}}

      flow_a =
        {:bpmn_sequence_flow,
         %{
           id: "flow_a",
           sourceRef: "gw",
           targetRef: "end_a",
           conditionExpression: {:bpmn_expression, {"elixir", "data[\"count\"] > 5"}},
           isImmediate: nil
         }}

      flow_b =
        {:bpmn_sequence_flow,
         %{
           id: "flow_b",
           sourceRef: "gw",
           targetRef: "end_b",
           conditionExpression: {:bpmn_expression, {"elixir", "data[\"count\"] <= 5"}},
           isImmediate: nil
         }}

      gateway =
        {:bpmn_gateway_exclusive,
         %{id: "gw", incoming: ["in"], outgoing: ["flow_a", "flow_b"], default: nil}}

      process = %{
        "flow_a" => flow_a,
        "flow_b" => flow_b,
        "end_a" => end_a,
        "end_b" => end_b
      }

      {:ok, context} = Context.start_link(process, %{})
      Context.put_data(context, "count", 10)

      assert {:ok, ^context} = Exclusive.token_in(gateway, context)
    end

    test "falls through to second flow when first condition is false" do
      end_a = {:bpmn_event_end, %{id: "end_a", incoming: ["flow_a"], outgoing: []}}
      end_b = {:bpmn_event_end, %{id: "end_b", incoming: ["flow_b"], outgoing: []}}

      flow_a =
        {:bpmn_sequence_flow,
         %{
           id: "flow_a",
           sourceRef: "gw",
           targetRef: "end_a",
           conditionExpression: {:bpmn_expression, {"elixir", "data[\"count\"] > 5"}},
           isImmediate: nil
         }}

      flow_b =
        {:bpmn_sequence_flow,
         %{
           id: "flow_b",
           sourceRef: "gw",
           targetRef: "end_b",
           conditionExpression: {:bpmn_expression, {"elixir", "data[\"count\"] <= 5"}},
           isImmediate: nil
         }}

      gateway =
        {:bpmn_gateway_exclusive,
         %{id: "gw", incoming: ["in"], outgoing: ["flow_a", "flow_b"], default: nil}}

      process = %{
        "flow_a" => flow_a,
        "flow_b" => flow_b,
        "end_a" => end_a,
        "end_b" => end_b
      }

      {:ok, context} = Context.start_link(process, %{})
      Context.put_data(context, "count", 2)

      assert {:ok, ^context} = Exclusive.token_in(gateway, context)
    end

    test "uses default flow when no conditions match" do
      end_a = {:bpmn_event_end, %{id: "end_a", incoming: ["flow_a"], outgoing: []}}

      end_default =
        {:bpmn_event_end, %{id: "end_default", incoming: ["flow_default"], outgoing: []}}

      flow_a =
        {:bpmn_sequence_flow,
         %{
           id: "flow_a",
           sourceRef: "gw",
           targetRef: "end_a",
           conditionExpression: {:bpmn_expression, {"elixir", "false"}},
           isImmediate: nil
         }}

      flow_default =
        {:bpmn_sequence_flow,
         %{
           id: "flow_default",
           sourceRef: "gw",
           targetRef: "end_default",
           conditionExpression: nil,
           isImmediate: nil
         }}

      gateway =
        {:bpmn_gateway_exclusive,
         %{
           id: "gw",
           incoming: ["in"],
           outgoing: ["flow_a", "flow_default"],
           default: "flow_default"
         }}

      process = %{
        "flow_a" => flow_a,
        "flow_default" => flow_default,
        "end_a" => end_a,
        "end_default" => end_default
      }

      {:ok, context} = Context.start_link(process, %{})

      assert {:ok, ^context} = Exclusive.token_in(gateway, context)
    end

    test "returns error when no conditions match and no default" do
      flow_a =
        {:bpmn_sequence_flow,
         %{
           id: "flow_a",
           sourceRef: "gw",
           targetRef: "end_a",
           conditionExpression: {:bpmn_expression, {"elixir", "false"}},
           isImmediate: nil
         }}

      gateway =
        {:bpmn_gateway_exclusive,
         %{id: "gw", incoming: ["in"], outgoing: ["flow_a"], default: nil}}

      process = %{"flow_a" => flow_a}

      {:ok, context} = Context.start_link(process, %{})

      assert {:error, _msg} = Exclusive.token_in(gateway, context)
    end
  end

  describe "converging (merge)" do
    test "passes token through to single outgoing flow" do
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

      gateway =
        {:bpmn_gateway_exclusive,
         %{id: "gw", incoming: ["flow_a", "flow_b"], outgoing: ["flow_out"], default: nil}}

      process = %{"flow_out" => flow_out, "end" => end_event}

      {:ok, context} = Context.start_link(process, %{})

      assert {:ok, ^context} = Exclusive.token_in(gateway, context)
    end
  end
end
