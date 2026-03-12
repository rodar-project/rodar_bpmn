defmodule RodarBpmnTest do
  use ExUnit.Case
  doctest RodarBpmn
  doctest RodarBpmn.Activity.Subprocess
  doctest RodarBpmn.Event.Boundary
  doctest RodarBpmn.Event.Intermediate
  doctest RodarBpmn.Event.Intermediate.Throw
  doctest RodarBpmn.Event.Intermediate.Catch
  doctest RodarBpmn.Event.Bus
  doctest RodarBpmn.Event.Timer
  doctest RodarBpmn.Gateway.Exclusive.Event
  doctest RodarBpmn.Gateway.Complex
end
