defmodule Bpmn.Telemetry.LogHandlerTest do
  use ExUnit.Case, async: false

  alias Bpmn.Telemetry.LogHandler

  describe "attach/0 and detach/0" do
    test "attach and detach work without error" do
      assert :ok = LogHandler.attach()
      assert :ok = LogHandler.detach()
    end

    test "attach returns error when already attached" do
      :ok = LogHandler.attach()
      assert {:error, :already_exists} = LogHandler.attach()
      :ok = LogHandler.detach()
    end

    test "detach returns error when not attached" do
      assert {:error, :not_found} = LogHandler.detach()
    end
  end

  describe "handle_event/4" do
    setup do
      :ok = LogHandler.attach()
      on_exit(fn -> LogHandler.detach() end)
      :ok
    end

    test "handles node start event" do
      assert :ok =
               LogHandler.handle_event(
                 [:bpmn, :node, :start],
                 %{system_time: System.system_time()},
                 %{node_id: "task_1", node_type: :bpmn_activity_task_user, token_id: "tok-1"},
                 nil
               )
    end

    test "handles node stop event" do
      assert :ok =
               LogHandler.handle_event(
                 [:bpmn, :node, :stop],
                 %{duration: 1000},
                 %{
                   node_id: "task_1",
                   node_type: :bpmn_activity_task_user,
                   token_id: "tok-1",
                   result: :ok
                 },
                 nil
               )
    end

    test "handles node exception event" do
      assert :ok =
               LogHandler.handle_event(
                 [:bpmn, :node, :exception],
                 %{duration: 500},
                 %{
                   node_id: "task_1",
                   node_type: :bpmn_activity_task_script,
                   token_id: "tok-1",
                   kind: :error,
                   reason: %RuntimeError{message: "boom"}
                 },
                 nil
               )
    end

    test "handles process start event" do
      assert :ok =
               LogHandler.handle_event(
                 [:bpmn, :process, :start],
                 %{system_time: System.system_time()},
                 %{instance_id: "inst-1", process_id: "proc-1"},
                 nil
               )
    end

    test "handles process stop event" do
      assert :ok =
               LogHandler.handle_event(
                 [:bpmn, :process, :stop],
                 %{duration: 5000},
                 %{instance_id: "inst-1", process_id: "proc-1", status: :completed},
                 nil
               )
    end

    test "handles token create event" do
      assert :ok =
               LogHandler.handle_event(
                 [:bpmn, :token, :create],
                 %{system_time: System.system_time()},
                 %{token_id: "tok-1", parent_id: nil, node_id: nil},
                 nil
               )
    end

    test "handles event bus publish event" do
      assert :ok =
               LogHandler.handle_event(
                 [:bpmn, :event_bus, :publish],
                 %{system_time: System.system_time()},
                 %{event_type: :signal, event_name: "test", subscriber_count: 2},
                 nil
               )
    end

    test "handles event bus subscribe event" do
      assert :ok =
               LogHandler.handle_event(
                 [:bpmn, :event_bus, :subscribe],
                 %{system_time: System.system_time()},
                 %{event_type: :message, event_name: "test", node_id: "catch_1"},
                 nil
               )
    end
  end
end
