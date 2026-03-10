defmodule Bpmn.ObservabilityTest do
  use ExUnit.Case, async: false

  setup do
    # Ensure supervision tree is fully started
    _ = Application.ensure_all_started(:bpmn)
    :ok
  end

  describe "health/0" do
    test "returns map with expected keys" do
      health = Bpmn.Observability.health()

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
      instances = Bpmn.Observability.running_instances()
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

      Bpmn.Registry.register(process_id, definition)
      {:ok, pid} = Bpmn.Process.create_and_run(process_id)

      instances = Bpmn.Observability.running_instances()
      instance = Enum.find(instances, &(&1.pid == pid))

      assert instance != nil
      assert instance.status == :suspended
      assert is_binary(instance.instance_id)

      Bpmn.Process.terminate(pid)
      Bpmn.Registry.unregister(process_id)
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

      Bpmn.Registry.register(process_id, definition)
      {:ok, pid} = Bpmn.Process.create_and_run(process_id)

      waiting = Bpmn.Observability.waiting_instances()
      instance = Enum.find(waiting, &(&1.pid == pid))

      assert instance != nil
      assert instance.status == :suspended

      Bpmn.Process.terminate(pid)
      Bpmn.Registry.unregister(process_id)
    end
  end

  describe "instances_by_version/1" do
    test "filters instances by process ID and version" do
      process_id = "obs_ver_#{:erlang.unique_integer([:positive])}"

      definition =
        {:bpmn_process, %{id: process_id},
         [
           {:bpmn_event_start, %{id: "start", outgoing: ["user_task"]}},
           {:bpmn_activity_task_user,
            %{id: "user_task", name: "Wait", incoming: ["start"], outgoing: ["end"]}},
           {:bpmn_event_end, %{id: "end", incoming: ["user_task"]}}
         ]}

      Bpmn.Registry.register(process_id, definition)
      {:ok, pid} = Bpmn.Process.create_and_run(process_id)

      instances = Bpmn.Observability.instances_by_version(process_id)
      assert instances != []
      instance = Enum.find(instances, &(&1.pid == pid))
      assert instance.process_id == process_id
      assert instance.definition_version == 1

      # Filter by specific version
      v1_instances = Bpmn.Observability.instances_by_version(process_id, 1)
      assert Enum.any?(v1_instances, &(&1.pid == pid))

      v2_instances = Bpmn.Observability.instances_by_version(process_id, 2)
      refute Enum.any?(v2_instances, &(&1.pid == pid))

      Bpmn.Process.terminate(pid)
      Bpmn.Registry.unregister(process_id)
    end
  end

  describe "running_instances/0 version info" do
    test "includes process_id and definition_version in instance info" do
      process_id = "obs_verinfo_#{:erlang.unique_integer([:positive])}"

      definition =
        {:bpmn_process, %{id: process_id},
         [
           {:bpmn_event_start, %{id: "start", outgoing: ["user_task"]}},
           {:bpmn_activity_task_user,
            %{id: "user_task", name: "Wait", incoming: ["start"], outgoing: ["end"]}},
           {:bpmn_event_end, %{id: "end", incoming: ["user_task"]}}
         ]}

      Bpmn.Registry.register(process_id, definition)
      {:ok, pid} = Bpmn.Process.create_and_run(process_id)

      instances = Bpmn.Observability.running_instances()
      instance = Enum.find(instances, &(&1.pid == pid))

      assert instance != nil
      assert instance.process_id == process_id
      assert instance.definition_version == 1

      Bpmn.Process.terminate(pid)
      Bpmn.Registry.unregister(process_id)
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

      Bpmn.Registry.register(process_id, definition)
      {:ok, pid} = Bpmn.Process.create_and_run(process_id)

      history = Bpmn.Observability.execution_history(pid)
      assert is_list(history)
      assert history != []

      Bpmn.Process.terminate(pid)
      Bpmn.Registry.unregister(process_id)
    end
  end
end
