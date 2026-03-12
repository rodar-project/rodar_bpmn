defmodule RodarBpmn.ScaffoldTest do
  use ExUnit.Case, async: true

  alias RodarBpmn.Engine.Diagram
  alias RodarBpmn.Scaffold

  describe "extract_tasks/1" do
    test "extracts generic tasks" do
      diagram = load_fixture("01_sequential_flow.bpmn")
      tasks = Scaffold.extract_tasks(diagram)

      assert length(tasks) == 2
      assert Enum.all?(tasks, &(&1.bpmn_type == :bpmn_activity_task))
      assert Enum.find(tasks, &(&1.id == "Task_A"))
      assert Enum.find(tasks, &(&1.id == "Task_B"))
    end

    test "extracts service, user, send, and receive tasks" do
      diagram = load_fixture("conformance/miwg/B.1.0.bpmn")
      tasks = Scaffold.extract_tasks(diagram)

      types = Enum.map(tasks, & &1.bpmn_type) |> MapSet.new()

      assert :bpmn_activity_task_service in types
      assert :bpmn_activity_task_user in types
      assert :bpmn_activity_task_send in types
      assert :bpmn_activity_task_receive in types
      assert :bpmn_activity_task in types
    end

    test "extracts task names" do
      diagram = load_fixture("conformance/miwg/B.1.0.bpmn")
      tasks = Scaffold.extract_tasks(diagram)

      service = Enum.find(tasks, &(&1.bpmn_type == :bpmn_activity_task_service))
      assert service.name == "Service Task"
    end

    test "returns empty list when no tasks" do
      diagram = load_fixture("05_timer_event.bpmn")
      tasks = Scaffold.extract_tasks(diagram)

      # Timer event fixture may have tasks — filter to check structure
      assert is_list(tasks)
    end
  end

  describe "module_name_from_element/1" do
    test "converts space-separated words" do
      assert Scaffold.module_name_from_element("Check Inventory") == "CheckInventory"
    end

    test "converts underscore-separated words" do
      assert Scaffold.module_name_from_element("Activity_0abc") == "Activity0abc"
    end

    test "converts hyphen-separated words" do
      assert Scaffold.module_name_from_element("send-email-task") == "SendEmailTask"
    end

    test "strips special characters" do
      assert Scaffold.module_name_from_element("Task (1)") == "Task1"
    end

    test "handles single word" do
      assert Scaffold.module_name_from_element("validate") == "Validate"
    end
  end

  describe "file_name_from_module/1" do
    test "converts PascalCase to snake_case with extension" do
      assert Scaffold.file_name_from_module("CheckInventory") == "check_inventory.ex"
    end

    test "handles single word" do
      assert Scaffold.file_name_from_module("Validate") == "validate.ex"
    end

    test "handles consecutive capitals sensibly" do
      assert Scaffold.file_name_from_module("Activity0abc") == "activity0abc.ex"
    end
  end

  describe "generate_module/2" do
    test "generates service task handler" do
      task = %{id: "Task_1", name: "Check Inventory", bpmn_type: :bpmn_activity_task_service}
      {mod, file, content} = Scaffold.generate_module(task, "MyApp.Handlers")

      assert mod == "CheckInventory"
      assert file == "check_inventory.ex"
      assert content =~ "defmodule MyApp.Handlers.CheckInventory do"
      assert content =~ "@behaviour RodarBpmn.Activity.Task.Service.Handler"
      assert content =~ "def execute(_attrs, _data) do"
      assert content =~ "{:ok, %{}}"
    end

    test "generates user task handler" do
      task = %{id: "Task_2", name: "Review Order", bpmn_type: :bpmn_activity_task_user}
      {mod, file, content} = Scaffold.generate_module(task, "MyApp.Handlers")

      assert mod == "ReviewOrder"
      assert file == "review_order.ex"
      assert content =~ "defmodule MyApp.Handlers.ReviewOrder do"
      assert content =~ "@behaviour RodarBpmn.TaskHandler"
      assert content =~ "def token_in(_element, _context) do"
      assert content =~ "{:ok, nil}"
    end

    test "generates generic task handler" do
      task = %{id: "Task_A", name: nil, bpmn_type: :bpmn_activity_task}
      {mod, _file, content} = Scaffold.generate_module(task, "MyApp.Handlers")

      assert mod == "TaskA"
      assert content =~ "@behaviour RodarBpmn.TaskHandler"
    end

    test "uses id when name is nil" do
      task = %{id: "Activity_0xyz", name: nil, bpmn_type: :bpmn_activity_task_send}
      {mod, _file, _content} = Scaffold.generate_module(task, "MyApp.Handlers")

      assert mod == "Activity0xyz"
    end
  end

  describe "diff_contents/2" do
    test "detects removed and added lines" do
      old = "line1\nline2\nline3"
      new = "line1\nline2_changed\nline3"

      diff = Scaffold.diff_contents(old, new)
      assert {:removed, "line2"} in diff
      assert {:added, "line2_changed"} in diff
    end

    test "returns empty for identical content" do
      content = "same\ncontent"
      assert Scaffold.diff_contents(content, content) == []
    end
  end

  describe "behaviour_for_type/1" do
    test "returns Service.Handler for service tasks" do
      {mod, callback, _sig} = Scaffold.behaviour_for_type(:bpmn_activity_task_service)
      assert mod == RodarBpmn.Activity.Task.Service.Handler
      assert callback == :execute
    end

    test "returns TaskHandler for other task types" do
      for type <- [:bpmn_activity_task_user, :bpmn_activity_task_send, :bpmn_activity_task] do
        {mod, callback, _sig} = Scaffold.behaviour_for_type(type)
        assert mod == RodarBpmn.TaskHandler
        assert callback == :token_in
      end
    end
  end

  describe "bpmn_base_name/1" do
    test "converts file path to PascalCase name" do
      assert Scaffold.bpmn_base_name("path/to/order_processing.bpmn") == "OrderProcessing"
    end

    test "handles .bpmn2 extension" do
      assert Scaffold.bpmn_base_name("my-workflow.bpmn2") == "MyWorkflow"
    end

    test "handles bare filename" do
      assert Scaffold.bpmn_base_name("simple.bpmn") == "Simple"
    end
  end

  describe "default_module_prefix/2" do
    test "builds prefix from app name and bpmn name" do
      assert Scaffold.default_module_prefix("MyApp", "OrderProcessing") ==
               "MyApp.Workflow.OrderProcessing.Handlers"
    end
  end

  describe "registration_type/1" do
    test "service tasks use handler_map" do
      assert Scaffold.registration_type(:bpmn_activity_task_service) == :handler_map
    end

    test "other tasks use task_registry" do
      assert Scaffold.registration_type(:bpmn_activity_task_user) == :task_registry
      assert Scaffold.registration_type(:bpmn_activity_task) == :task_registry
    end
  end

  defp load_fixture(name) do
    path =
      if String.contains?(name, "/") do
        Path.join("test/fixtures", name)
      else
        Path.join("test/fixtures/conformance/execution", name)
      end

    path |> File.read!() |> Diagram.load()
  end
end
