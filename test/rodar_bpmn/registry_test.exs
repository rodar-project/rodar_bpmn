defmodule RodarBpmn.RegistryTest do
  use ExUnit.Case, async: false

  alias RodarBpmn.Registry

  setup do
    # Clean up any registered processes between tests
    for id <- Registry.list() do
      Registry.unregister(id)
    end

    :ok
  end

  describe "register/2" do
    test "registers a process definition" do
      definition = {:bpmn_process, %{id: "proc_1"}, %{}}
      assert :ok = Registry.register("proc_1", definition)
    end

    test "overwrites existing registration" do
      definition1 = {:bpmn_process, %{id: "proc_1"}, %{v: 1}}
      definition2 = {:bpmn_process, %{id: "proc_1"}, %{v: 2}}

      Registry.register("proc_1", definition1)
      Registry.register("proc_1", definition2)

      assert {:ok, ^definition2} = Registry.lookup("proc_1")
    end
  end

  describe "lookup/1" do
    test "returns definition for registered process" do
      definition = {:bpmn_process, %{id: "proc_1"}, %{}}
      Registry.register("proc_1", definition)

      assert {:ok, ^definition} = Registry.lookup("proc_1")
    end

    test "returns :error for unregistered process" do
      assert :error = Registry.lookup("nonexistent")
    end
  end

  describe "unregister/1" do
    test "removes a registered process" do
      definition = {:bpmn_process, %{id: "proc_1"}, %{}}
      Registry.register("proc_1", definition)
      Registry.unregister("proc_1")

      assert :error = Registry.lookup("proc_1")
    end
  end

  describe "list/0" do
    test "returns all registered process IDs" do
      Registry.register("proc_1", {:bpmn_process, %{}, %{}})
      Registry.register("proc_2", {:bpmn_process, %{}, %{}})

      ids = Registry.list()
      assert "proc_1" in ids
      assert "proc_2" in ids
    end

    test "returns empty list when nothing registered" do
      assert [] = Registry.list()
    end
  end
end
