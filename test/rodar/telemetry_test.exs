defmodule Rodar.TelemetryTest do
  use ExUnit.Case, async: false

  alias Rodar.Event.Bus

  setup do
    test_pid = self()
    handler_id = "test-handler-#{:erlang.unique_integer([:positive])}"

    :telemetry.attach_many(
      handler_id,
      Rodar.Telemetry.events(),
      fn event, measurements, metadata, _config ->
        send(test_pid, {:telemetry_event, event, measurements, metadata})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    :ok
  end

  describe "events/0" do
    test "returns all 8 event names" do
      events = Rodar.Telemetry.events()
      assert length(events) == 8
      assert [:rodar, :node, :start] in events
      assert [:rodar, :node, :stop] in events
      assert [:rodar, :node, :exception] in events
      assert [:rodar, :process, :start] in events
      assert [:rodar, :process, :stop] in events
      assert [:rodar, :token, :create] in events
      assert [:rodar, :event_bus, :publish] in events
      assert [:rodar, :event_bus, :subscribe] in events
    end
  end

  describe "node_span/2" do
    test "emits start and stop events" do
      metadata = %{node_id: "task_1", node_type: :bpmn_activity_task_user, token_id: "tok-1"}

      result = Rodar.Telemetry.node_span(metadata, fn -> {:ok, :done} end)

      assert result == {:ok, :done}

      assert_receive {:telemetry_event, [:rodar, :node, :start], %{system_time: _}, meta}
      assert meta.node_id == "task_1"
      assert meta.node_type == :bpmn_activity_task_user
      assert meta.token_id == "tok-1"

      assert_receive {:telemetry_event, [:rodar, :node, :stop], %{duration: duration}, meta}
      assert is_integer(duration)
      assert meta.result == :ok
    end

    test "emits exception event on raise" do
      metadata = %{node_id: "task_2", node_type: :bpmn_activity_task_script, token_id: "tok-2"}

      assert_raise RuntimeError, fn ->
        Rodar.Telemetry.node_span(metadata, fn -> raise "boom" end)
      end

      assert_receive {:telemetry_event, [:rodar, :node, :start], _, _}

      assert_receive {:telemetry_event, [:rodar, :node, :exception], %{duration: _}, meta}
      assert meta.kind == :error
      assert meta.node_id == "task_2"
    end
  end

  describe "token_created/1" do
    test "emits token create event" do
      token = %Rodar.Token{id: "tok-123", parent_id: "tok-parent", current_node: "start_1"}
      Rodar.Telemetry.token_created(token)

      assert_receive {:telemetry_event, [:rodar, :token, :create], %{system_time: _}, meta}
      assert meta.token_id == "tok-123"
      assert meta.parent_id == "tok-parent"
      assert meta.node_id == "start_1"
    end
  end

  describe "Token.new/1 integration" do
    test "emits token create event when creating a token" do
      _token = Rodar.Token.new()

      assert_receive {:telemetry_event, [:rodar, :token, :create], %{system_time: _}, meta}
      assert is_binary(meta.token_id)
    end
  end

  describe "process_started/2 and process_stopped/4" do
    test "emits process start and stop events" do
      Rodar.Telemetry.process_started("inst-1", "proc-1")

      assert_receive {:telemetry_event, [:rodar, :process, :start], %{system_time: _}, meta}
      assert meta.instance_id == "inst-1"
      assert meta.process_id == "proc-1"

      start_time = System.monotonic_time()
      Rodar.Telemetry.process_stopped("inst-1", "proc-1", :completed, start_time)

      assert_receive {:telemetry_event, [:rodar, :process, :stop], %{duration: _}, meta}
      assert meta.instance_id == "inst-1"
      assert meta.status == :completed
    end
  end

  describe "event_published/3" do
    test "emits event bus publish event" do
      Rodar.Telemetry.event_published(:signal, "order_placed", 3)

      assert_receive {:telemetry_event, [:rodar, :event_bus, :publish], %{system_time: _}, meta}

      assert meta.event_type == :signal
      assert meta.event_name == "order_placed"
      assert meta.subscriber_count == 3
    end
  end

  describe "event_subscribed/3" do
    test "emits event bus subscribe event" do
      Rodar.Telemetry.event_subscribed(:message, "order_received", "catch_1")

      assert_receive {:telemetry_event, [:rodar, :event_bus, :subscribe], %{system_time: _}, meta}

      assert meta.event_type == :message
      assert meta.event_name == "order_received"
      assert meta.node_id == "catch_1"
    end
  end

  describe "Event.Bus integration" do
    test "subscribe emits telemetry event" do
      name = "sub_test_#{:erlang.unique_integer([:positive])}"
      Bus.subscribe(:message, name, %{node_id: "catch_node"})

      assert_receive {:telemetry_event, [:rodar, :event_bus, :subscribe], _, meta}
      assert meta.event_type == :message
      assert meta.event_name == name
      assert meta.node_id == "catch_node"
    end

    test "publish emits telemetry event" do
      name = "pub_test_#{:erlang.unique_integer([:positive])}"
      Bus.publish(:signal, name, %{data: "test"})

      assert_receive {:telemetry_event, [:rodar, :event_bus, :publish], _, meta}
      assert meta.event_type == :signal
      assert meta.event_name == name
      assert meta.subscriber_count == 0
    end
  end

  describe "execute/3 integration" do
    test "emits node start and stop events" do
      process = %{
        "start" => {:bpmn_event_start, %{id: "start", outgoing: ["end"]}},
        "end" => {:bpmn_event_end, %{id: "end", incoming: ["start"]}}
      }

      {:ok, context} = Rodar.Context.start_supervised(process, %{})
      token = Rodar.Token.new()

      # Drain the token create event
      assert_receive {:telemetry_event, [:rodar, :token, :create], _, _}

      Rodar.execute({:bpmn_event_start, %{id: "start", outgoing: ["end"]}}, context, token)

      assert_receive {:telemetry_event, [:rodar, :node, :start], _, %{node_id: "start"}}

      assert_receive {:telemetry_event, [:rodar, :node, :stop], %{duration: _},
                      %{node_id: "start", result: :ok}}
    end
  end

  describe "Process lifecycle integration" do
    test "activation emits process start and stop events" do
      process_id = "telemetry_test_#{:erlang.unique_integer([:positive])}"

      definition =
        {:bpmn_process, %{id: process_id},
         [
           {:bpmn_event_start, %{id: "start", outgoing: ["end"]}},
           {:bpmn_event_end, %{id: "end", incoming: ["start"]}}
         ]}

      Rodar.Registry.register(process_id, definition)

      {:ok, pid} = Rodar.Process.create_and_run(process_id)

      # Drain token events first
      drain_events([:rodar, :token, :create])

      assert_receive {:telemetry_event, [:rodar, :process, :start], %{system_time: _}, meta},
                     500

      assert meta.process_id == process_id

      assert_receive {:telemetry_event, [:rodar, :process, :stop], %{duration: _}, meta},
                     500

      assert meta.process_id == process_id

      Rodar.Process.terminate(pid)
      Rodar.Registry.unregister(process_id)
    end
  end

  defp drain_events(event_name) do
    receive do
      {:telemetry_event, ^event_name, _, _} -> drain_events(event_name)
    after
      0 -> :ok
    end
  end
end
