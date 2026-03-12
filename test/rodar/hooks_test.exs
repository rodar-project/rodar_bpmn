defmodule Rodar.HooksTest do
  use ExUnit.Case, async: true

  alias Rodar.Hooks

  defp simple_process do
    %{
      "start" => {:bpmn_event_start, %{id: "start", incoming: [], outgoing: ["f1"]}},
      "f1" =>
        {:bpmn_sequence_flow,
         %{id: "f1", sourceRef: "start", targetRef: "end", conditionExpression: nil}},
      "end" => {:bpmn_event_end, %{id: "end", incoming: ["f1"], outgoing: []}}
    }
  end

  defp error_process do
    %{
      "start" => {:bpmn_event_start, %{id: "start", incoming: [], outgoing: ["f1"]}},
      "f1" =>
        {:bpmn_sequence_flow,
         %{id: "f1", sourceRef: "start", targetRef: "end_err", conditionExpression: nil}},
      "end_err" =>
        {:bpmn_event_end,
         %{
           id: "end_err",
           incoming: ["f1"],
           outgoing: [],
           errorEventDefinition: {:bpmn_event_definition_error, %{errorRef: "Err_1"}}
         }}
    }
  end

  describe "register/3 and notify/3" do
    test "before_node hook is called with correct metadata" do
      test_pid = self()
      {:ok, context} = Rodar.Context.start_link(simple_process(), %{})

      Hooks.register(context, :before_node, fn meta ->
        send(test_pid, {:before, meta})
        :ok
      end)

      start = simple_process()["start"]
      Rodar.execute(start, context)

      assert_received {:before, %{node_id: "start", node_type: :bpmn_event_start}}
    end

    test "after_node hook is called with result" do
      test_pid = self()
      {:ok, context} = Rodar.Context.start_link(simple_process(), %{})

      Hooks.register(context, :after_node, fn meta ->
        send(test_pid, {:after, meta})
        :ok
      end)

      start = simple_process()["start"]
      Rodar.execute(start, context)

      assert_received {:after, %{node_id: "start", result: {:ok, _}}}
    end

    test "multiple hooks for same event are all called" do
      test_pid = self()
      {:ok, context} = Rodar.Context.start_link(simple_process(), %{})

      Hooks.register(context, :before_node, fn _meta ->
        send(test_pid, :hook_1)
        :ok
      end)

      Hooks.register(context, :before_node, fn _meta ->
        send(test_pid, :hook_2)
        :ok
      end)

      start = simple_process()["start"]
      Rodar.execute(start, context)

      assert_received :hook_1
      assert_received :hook_2
    end

    test "on_complete hook fires on process completion" do
      test_pid = self()
      {:ok, context} = Rodar.Context.start_link(simple_process(), %{})

      Hooks.register(context, :on_complete, fn meta ->
        send(test_pid, {:complete, meta})
        :ok
      end)

      start = simple_process()["start"]
      Rodar.execute(start, context)

      assert_received {:complete, %{node_id: "end"}}
    end

    test "on_error hook fires on error end event" do
      test_pid = self()
      {:ok, context} = Rodar.Context.start_link(error_process(), %{})

      Hooks.register(context, :on_error, fn meta ->
        send(test_pid, {:error_hook, meta})
        :ok
      end)

      start = error_process()["start"]
      Rodar.execute(start, context)

      assert_received {:error_hook, %{node_id: "end_err", error: "Err_1"}}
    end
  end

  describe "unregister/2" do
    test "removes hooks for event" do
      test_pid = self()
      {:ok, context} = Rodar.Context.start_link(simple_process(), %{})

      Hooks.register(context, :before_node, fn _meta ->
        send(test_pid, :should_not_fire)
        :ok
      end)

      Hooks.unregister(context, :before_node)

      start = simple_process()["start"]
      Rodar.execute(start, context)

      refute_received :should_not_fire
    end
  end

  describe "no hooks registered" do
    test "no crash when no hooks are registered" do
      {:ok, context} = Rodar.Context.start_link(simple_process(), %{})
      start = simple_process()["start"]
      assert {:ok, ^context} = Rodar.execute(start, context)
    end
  end

  describe "error handling" do
    test "hook exception does not break execution" do
      {:ok, context} = Rodar.Context.start_link(simple_process(), %{})

      Hooks.register(context, :before_node, fn _meta ->
        raise "boom"
      end)

      start = simple_process()["start"]
      assert {:ok, ^context} = Rodar.execute(start, context)
    end
  end
end
