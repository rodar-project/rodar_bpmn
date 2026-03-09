defmodule BpmnTest do
  use ExUnit.Case
  doctest Bpmn
  doctest Bpmn.Activity.Subprocess
  doctest Bpmn.Event.Boundary
  doctest Bpmn.Event.Intermediate
  doctest Bpmn.Gateway.Exclusive.Event
  doctest Bpmn.Gateway.Complex
end
