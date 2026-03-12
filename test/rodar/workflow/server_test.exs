defmodule Rodar.Workflow.ServerTest do
  use ExUnit.Case, async: false

  defmodule TestServer do
    use Rodar.Workflow.Server,
      bpmn_file: Path.join([__DIR__, "..", "..", "fixtures", "run_user_task.bpmn"]),
      process_id: "server-test-process",
      app_name: nil

    @impl Rodar.Workflow.Server
    def init_data(params, instance_id) do
      %{
        "customer" => Map.get(params, "customer", "test"),
        "order_id" => instance_id
      }
    end
  end

  defmodule TestServerWithMapStatus do
    use Rodar.Workflow.Server,
      bpmn_file: Path.join([__DIR__, "..", "..", "fixtures", "run_user_task.bpmn"]),
      process_id: "server-map-status-process",
      app_name: nil

    @impl Rodar.Workflow.Server
    def init_data(params, instance_id) do
      %{
        "customer" => Map.get(params, "customer", "test"),
        "order_id" => instance_id
      }
    end

    @impl Rodar.Workflow.Server
    def map_status(:suspended), do: :pending_approval
    def map_status(:completed), do: :fulfilled
    def map_status(other), do: other
  end

  setup do
    # Stop any previously started servers
    stop_if_alive(TestServer)
    stop_if_alive(TestServerWithMapStatus)
    :ok
  end

  defp stop_if_alive(name) do
    case GenServer.whereis(name) do
      nil -> :ok
      pid -> GenServer.stop(pid)
    end
  end

  describe "start_link/1" do
    test "starts the server and loads BPMN" do
      assert {:ok, pid} = TestServer.start_link()
      assert Process.alive?(pid)
      GenServer.stop(pid)
    end

    test "accepts name option" do
      assert {:ok, pid} = TestServer.start_link(name: :custom_server_name)
      assert GenServer.whereis(:custom_server_name) == pid
      GenServer.stop(pid)
    end
  end

  describe "create_instance/1" do
    test "creates an instance with data from init_data callback" do
      {:ok, _} = TestServer.start_link()

      assert {:ok, instance} = TestServer.create_instance(%{"customer" => "Alice"})
      assert instance.id == 1
      assert is_pid(instance.process_pid)
      assert instance.status == :suspended
      assert %DateTime{} = instance.created_at
    end

    test "increments instance IDs" do
      {:ok, _} = TestServer.start_link()

      {:ok, inst1} = TestServer.create_instance()
      {:ok, inst2} = TestServer.create_instance()
      assert inst1.id == 1
      assert inst2.id == 2
    end

    test "passes instance_id to init_data" do
      {:ok, _} = TestServer.start_link()

      {:ok, instance} = TestServer.create_instance(%{"customer" => "Bob"})
      data = Rodar.Workflow.process_data(instance.process_pid)
      assert data["order_id"] == 1
      assert data["customer"] == "Bob"
    end
  end

  describe "complete_task/3" do
    test "resumes user task and updates instance status" do
      {:ok, _} = TestServer.start_link()
      {:ok, instance} = TestServer.create_instance()

      assert {:ok, updated} =
               TestServer.complete_task(instance.id, "Task_Approval", %{"approved" => true})

      assert updated.status == :completed
    end

    test "returns error for unknown instance" do
      {:ok, _} = TestServer.start_link()

      assert {:error, :not_found} = TestServer.complete_task(999, "Task_Approval", %{})
    end
  end

  describe "list_instances/0" do
    test "returns instances sorted by id desc" do
      {:ok, _} = TestServer.start_link()
      {:ok, _} = TestServer.create_instance(%{"customer" => "A"})
      {:ok, _} = TestServer.create_instance(%{"customer" => "B"})

      instances = TestServer.list_instances()
      assert length(instances) == 2
      assert hd(instances).id == 2
      assert List.last(instances).id == 1
    end

    test "returns empty list when no instances" do
      {:ok, _} = TestServer.start_link()
      assert TestServer.list_instances() == []
    end
  end

  describe "get_instance/1" do
    test "returns instance by id" do
      {:ok, _} = TestServer.start_link()
      {:ok, created} = TestServer.create_instance()

      assert {:ok, instance} = TestServer.get_instance(created.id)
      assert instance.id == created.id
    end

    test "returns error for unknown id" do
      {:ok, _} = TestServer.start_link()
      assert {:error, :not_found} = TestServer.get_instance(999)
    end
  end

  describe "map_status callback" do
    test "applies map_status when defined" do
      {:ok, _} = TestServerWithMapStatus.start_link()
      {:ok, instance} = TestServerWithMapStatus.create_instance()

      # User task suspends the process; map_status translates :suspended → :pending_approval
      assert instance.status == :pending_approval
    end

    test "applies map_status after task completion" do
      {:ok, _} = TestServerWithMapStatus.start_link()
      {:ok, instance} = TestServerWithMapStatus.create_instance()

      {:ok, updated} =
        TestServerWithMapStatus.complete_task(
          instance.id,
          "Task_Approval",
          %{"approved" => true}
        )

      # :completed → :fulfilled via map_status
      assert updated.status == :fulfilled
    end

    test "uses identity when map_status not defined" do
      {:ok, _} = TestServer.start_link()
      {:ok, instance} = TestServer.create_instance()

      # No map_status defined, so :suspended stays as :suspended
      assert instance.status == :suspended
    end
  end

  describe "Layer 1 functions accessible from server module" do
    test "process_status/1 works via inherited workflow" do
      {:ok, _} = TestServer.start_link()
      {:ok, instance} = TestServer.create_instance()
      assert TestServer.process_status(instance.process_pid) == :suspended
    end

    test "process_data/1 works via inherited workflow" do
      {:ok, _} = TestServer.start_link()
      {:ok, instance} = TestServer.create_instance(%{"customer" => "Carol"})
      data = TestServer.process_data(instance.process_pid)
      assert data["customer"] == "Carol"
    end
  end
end
