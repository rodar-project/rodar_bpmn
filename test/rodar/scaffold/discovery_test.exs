defmodule RodarBpmn.Scaffold.DiscoveryTest do
  use ExUnit.Case, async: true

  alias RodarBpmn.Engine.Diagram
  alias RodarBpmn.Scaffold.Discovery

  @service_tasks_xml """
  <?xml version="1.0" encoding="UTF-8"?>
  <bpmn:definitions xmlns:bpmn="http://www.omg.org/spec/BPMN/20100524/MODEL" id="D1">
    <bpmn:process id="P1" isExecutable="true">
      <bpmn:startEvent id="Start_1">
        <bpmn:outgoing>Flow_1</bpmn:outgoing>
      </bpmn:startEvent>
      <bpmn:serviceTask id="Task_1" name="Validate Order">
        <bpmn:incoming>Flow_1</bpmn:incoming>
        <bpmn:outgoing>Flow_2</bpmn:outgoing>
      </bpmn:serviceTask>
      <bpmn:serviceTask id="Task_2" name="Fulfill Order">
        <bpmn:incoming>Flow_2</bpmn:incoming>
        <bpmn:outgoing>Flow_3</bpmn:outgoing>
      </bpmn:serviceTask>
      <bpmn:endEvent id="End_1">
        <bpmn:incoming>Flow_3</bpmn:incoming>
      </bpmn:endEvent>
      <bpmn:sequenceFlow id="Flow_1" sourceRef="Start_1" targetRef="Task_1" />
      <bpmn:sequenceFlow id="Flow_2" sourceRef="Task_1" targetRef="Task_2" />
      <bpmn:sequenceFlow id="Flow_3" sourceRef="Task_2" targetRef="End_1" />
    </bpmn:process>
  </bpmn:definitions>
  """

  @mixed_tasks_xml """
  <?xml version="1.0" encoding="UTF-8"?>
  <bpmn:definitions xmlns:bpmn="http://www.omg.org/spec/BPMN/20100524/MODEL" id="D1">
    <bpmn:process id="P1" isExecutable="true">
      <bpmn:startEvent id="Start_1">
        <bpmn:outgoing>Flow_1</bpmn:outgoing>
      </bpmn:startEvent>
      <bpmn:serviceTask id="Task_Svc" name="Check Stock">
        <bpmn:incoming>Flow_1</bpmn:incoming>
        <bpmn:outgoing>Flow_2</bpmn:outgoing>
      </bpmn:serviceTask>
      <bpmn:userTask id="Task_User" name="Approve Order">
        <bpmn:incoming>Flow_2</bpmn:incoming>
        <bpmn:outgoing>Flow_3</bpmn:outgoing>
      </bpmn:userTask>
      <bpmn:endEvent id="End_1">
        <bpmn:incoming>Flow_3</bpmn:incoming>
      </bpmn:endEvent>
      <bpmn:sequenceFlow id="Flow_1" sourceRef="Start_1" targetRef="Task_Svc" />
      <bpmn:sequenceFlow id="Flow_2" sourceRef="Task_Svc" targetRef="Task_User" />
      <bpmn:sequenceFlow id="Flow_3" sourceRef="Task_User" targetRef="End_1" />
    </bpmn:process>
  </bpmn:definitions>
  """

  describe "discover/2" do
    test "returns not_found when no modules exist" do
      diagram = Diagram.load(@service_tasks_xml)

      result =
        Discovery.discover(diagram, module_prefix: "NonExistent.Prefix.That.Does.Not.Exist")

      assert result.handler_map == %{}
      assert result.task_registry_entries == []
      assert "Task_1" in result.not_found
      assert "Task_2" in result.not_found
    end

    test "discovers service task handler module" do
      diagram = Diagram.load(@service_tasks_xml)

      result =
        Discovery.discover(diagram,
          module_prefix: "RodarBpmn.Scaffold.DiscoveryTest.Handlers"
        )

      assert result.handler_map["Task_1"] ==
               RodarBpmn.Scaffold.DiscoveryTest.Handlers.ValidateOrder

      assert "Task_2" in result.not_found
    end

    test "discovers user task handler as task_registry_entry" do
      diagram = Diagram.load(@mixed_tasks_xml)

      result =
        Discovery.discover(diagram,
          module_prefix: "RodarBpmn.Scaffold.DiscoveryTest.Handlers"
        )

      assert {"Task_User", RodarBpmn.Scaffold.DiscoveryTest.Handlers.ApproveOrder} in result.task_registry_entries
    end

    test "skips module without correct callback" do
      diagram = Diagram.load(@service_tasks_xml)

      result =
        Discovery.discover(diagram,
          module_prefix: "RodarBpmn.Scaffold.DiscoveryTest.BadHandlers"
        )

      assert "Task_1" in result.not_found
    end
  end

  describe "discover_from_file/3" do
    test "derives prefix from file path and app name" do
      diagram = Diagram.load(@service_tasks_xml)

      result =
        Discovery.discover_from_file(diagram, "order_processing.bpmn", app_name: "NonExistent")

      # No modules exist, but we verify prefix was correctly derived
      assert "Task_1" in result.not_found
      assert "Task_2" in result.not_found
    end
  end

  describe "apply_handlers/2" do
    test "injects handler into service task elements" do
      diagram = Diagram.load(@service_tasks_xml)
      handler_map = %{"Task_1" => SomeModule}

      updated = Discovery.apply_handlers(diagram, handler_map)
      {:bpmn_process, _, elements} = hd(updated.processes)

      {:bpmn_activity_task_service, attrs} = elements["Task_1"]
      assert attrs.handler == SomeModule

      {:bpmn_activity_task_service, attrs2} = elements["Task_2"]
      refute Map.has_key?(attrs2, :handler)
    end

    test "returns diagram unchanged with empty handler_map" do
      diagram = Diagram.load(@service_tasks_xml)
      assert Discovery.apply_handlers(diagram, %{}) == diagram
    end
  end

  describe "register_discovered/1" do
    test "registers entries in TaskRegistry" do
      result = %{
        handler_map: %{},
        task_registry_entries: [
          {"test_discovery_task_1", RodarBpmn.Scaffold.DiscoveryTest.Handlers.ValidateOrder}
        ],
        not_found: []
      }

      registered = Discovery.register_discovered(result)
      assert registered == ["test_discovery_task_1"]

      assert {:ok, RodarBpmn.Scaffold.DiscoveryTest.Handlers.ValidateOrder} ==
               RodarBpmn.TaskRegistry.lookup("test_discovery_task_1")

      # Cleanup
      RodarBpmn.TaskRegistry.unregister("test_discovery_task_1")
    end
  end

  # --- Test handler modules ---

  defmodule Handlers.ValidateOrder do
    @behaviour RodarBpmn.Activity.Task.Service.Handler

    @impl true
    def execute(_attrs, _data), do: {:ok, %{}}
  end

  defmodule Handlers.ApproveOrder do
    @behaviour RodarBpmn.TaskHandler

    @impl true
    def token_in(_element, _context), do: {:ok, nil}
  end

  # Module that exists but has wrong callback
  defmodule BadHandlers.ValidateOrder do
    def wrong_function, do: :nope
  end
end
