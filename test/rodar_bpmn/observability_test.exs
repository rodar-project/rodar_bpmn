defmodule RodarBpmn.ObservabilityTest do
  use ExUnit.Case, async: false

  setup do
    # Ensure supervision tree is fully started
    _ = Application.ensure_all_started(:bpmn)
    :ok
  end

  describe "health/0" do
    test "returns map with expected keys" do
      health = RodarBpmn.Observability.health()

      assert is_map(health)
      assert health.supervisor_alive == true
      assert is_integer(health.process_count)
      assert is_integer(health.context_count)
      assert is_integer(health.registry_definitions)
      assert is_integer(health.event_subscriptions)
    end
  end

  describe "running_instances/0" do
    test "returns empty list when no processes running" do
      instances = RodarBpmn.Observability.running_instances()
      assert is_list(instances)
    end

    test "returns process instances after create_and_run" do
      process_id = "obs_test_#{:erlang.unique_integer([:positive])}"

      definition =
        {:bpmn_process, %{id: process_id},
         [
           {:bpmn_event_start, %{id: "start", outgoing: ["user_task"]}},
           {:bpmn_activity_task_user,
            %{id: "user_task", name: "Do something", incoming: ["start"], outgoing: ["end"]}},
           {:bpmn_event_end, %{id: "end", incoming: ["user_task"]}}
         ]}

      RodarBpmn.Registry.register(process_id, definition)
      {:ok, pid} = RodarBpmn.Process.create_and_run(process_id)

      instances = RodarBpmn.Observability.running_instances()
      instance = Enum.find(instances, &(&1.pid == pid))

      assert instance != nil
      assert instance.status == :suspended
      assert is_binary(instance.instance_id)

      RodarBpmn.Process.terminate(pid)
      RodarBpmn.Registry.unregister(process_id)
    end
  end

  describe "waiting_instances/0" do
    test "returns only suspended instances" do
      process_id = "obs_wait_#{:erlang.unique_integer([:positive])}"

      definition =
        {:bpmn_process, %{id: process_id},
         [
           {:bpmn_event_start, %{id: "start", outgoing: ["user_task"]}},
           {:bpmn_activity_task_user,
            %{id: "user_task", name: "Wait", incoming: ["start"], outgoing: ["end"]}},
           {:bpmn_event_end, %{id: "end", incoming: ["user_task"]}}
         ]}

      RodarBpmn.Registry.register(process_id, definition)
      {:ok, pid} = RodarBpmn.Process.create_and_run(process_id)

      waiting = RodarBpmn.Observability.waiting_instances()
      instance = Enum.find(waiting, &(&1.pid == pid))

      assert instance != nil
      assert instance.status == :suspended

      RodarBpmn.Process.terminate(pid)
      RodarBpmn.Registry.unregister(process_id)
    end
  end

  describe "execution_history/1" do
    test "returns history for a process instance" do
      process_id = "obs_hist_#{:erlang.unique_integer([:positive])}"

      definition =
        {:bpmn_process, %{id: process_id},
         [
           {:bpmn_event_start, %{id: "start", outgoing: ["end"]}},
           {:bpmn_event_end, %{id: "end", incoming: ["start"]}}
         ]}

      RodarBpmn.Registry.register(process_id, definition)
      {:ok, pid} = RodarBpmn.Process.create_and_run(process_id)

      history = RodarBpmn.Observability.execution_history(pid)
      assert is_list(history)
      assert history != []

      RodarBpmn.Process.terminate(pid)
      RodarBpmn.Registry.unregister(process_id)
    end
  end
end
