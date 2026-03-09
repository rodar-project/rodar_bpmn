defmodule BpmnTest do
  use ExUnit.Case
  doctest Bpmn
  doctest Bpmn.Activity.Subprocess
  doctest Bpmn.Activity.Subprocess.Embedded
  doctest Bpmn.Activity.Task.Manual
  doctest Bpmn.Activity.Task.Receive
  doctest Bpmn.Activity.Task.Send
  doctest Bpmn.Event.Boundary
  doctest Bpmn.Event.Intermediate
  doctest Bpmn.Gateway.Exclusive.Event
  doctest Bpmn.Gateway.Complex
  doctest Bpmn.Gateway.Inclusive
end
