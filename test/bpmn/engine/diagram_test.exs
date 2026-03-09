defmodule Bpmn.Engine.DiagramTest do
  use ExUnit.Case, async: true
  doctest Bpmn.Engine.Diagram

  describe "parser support for task types" do
    test "parses sendTask elements" do
      %{processes: [process]} = load_elements()
      {:bpmn_process, _, elements} = process
      assert {:bpmn_activity_task_send, attrs} = elements["Task_10yp281"]
      assert is_list(attrs.incoming)
      assert is_list(attrs.outgoing)
    end

    test "parses receiveTask elements" do
      %{processes: [process]} = load_elements()
      {:bpmn_process, _, elements} = process
      assert {:bpmn_activity_task_receive, attrs} = elements["Task_0k0tvr8"]
      assert is_list(attrs.incoming)
      assert is_list(attrs.outgoing)
    end

    test "parses subProcess elements" do
      %{processes: [process]} = load_elements()
      {:bpmn_process, _, elements} = process
      assert {:bpmn_activity_subprocess_embeded, attrs} = elements["Task_188rh46"]
      assert is_list(attrs.incoming)
      assert is_list(attrs.outgoing)
      assert is_map(attrs.elements)
    end
  end

  describe "parser support for inline BPMN" do
    test "parses manualTask elements" do
      xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <bpmn:definitions xmlns:bpmn="http://www.omg.org/spec/BPMN/20100524/MODEL" id="Definitions_1">
        <bpmn:process id="Process_1" isExecutable="true">
          <bpmn:manualTask id="ManualTask_1" name="Sign Doc">
            <bpmn:incoming>Flow_1</bpmn:incoming>
            <bpmn:outgoing>Flow_2</bpmn:outgoing>
          </bpmn:manualTask>
        </bpmn:process>
      </bpmn:definitions>
      """

      %{processes: [process]} = Bpmn.Engine.Diagram.load(xml)
      {:bpmn_process, _, elements} = process
      assert {:bpmn_activity_task_manual, attrs} = elements["ManualTask_1"]
      assert attrs.incoming == ["Flow_1"]
      assert attrs.outgoing == ["Flow_2"]
    end

    test "parses boundaryEvent elements" do
      xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <bpmn:definitions xmlns:bpmn="http://www.omg.org/spec/BPMN/20100524/MODEL" id="Definitions_1">
        <bpmn:process id="Process_1" isExecutable="true">
          <bpmn:userTask id="Task_1" name="Do Work">
            <bpmn:incoming>Flow_1</bpmn:incoming>
            <bpmn:outgoing>Flow_2</bpmn:outgoing>
          </bpmn:userTask>
          <bpmn:boundaryEvent id="Boundary_1" attachedToRef="Task_1" cancelActivity="true">
            <bpmn:outgoing>Flow_3</bpmn:outgoing>
            <bpmn:timerEventDefinition id="Timer_1" />
          </bpmn:boundaryEvent>
        </bpmn:process>
      </bpmn:definitions>
      """

      %{processes: [process]} = Bpmn.Engine.Diagram.load(xml)
      {:bpmn_process, _, elements} = process
      assert {:bpmn_event_boundary, attrs} = elements["Boundary_1"]
      assert attrs.outgoing == ["Flow_3"]
      assert attrs.attachedToRef == "Task_1"
      assert attrs.cancelActivity == "true"
    end
  end

  defp load_elements do
    Bpmn.Engine.Diagram.load(File.read!("./priv/bpmn/examples/elements.bpmn"))
  end
end
