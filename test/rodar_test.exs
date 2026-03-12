defmodule RodarTest do
  use ExUnit.Case
  doctest Rodar
  doctest Rodar.Activity.Subprocess
  doctest Rodar.Event.Boundary
  doctest Rodar.Event.Intermediate
  doctest Rodar.Event.Intermediate.Throw
  doctest Rodar.Event.Intermediate.Catch
  doctest Rodar.Event.Bus
  doctest Rodar.Event.Timer
  doctest Rodar.Gateway.Exclusive.Event
  doctest Rodar.Gateway.Complex
end
