defmodule Bpmn.TaskRegistryTest do
  use ExUnit.Case, async: false

  alias Bpmn.TaskRegistry

  setup do
    # Clean up any registrations from previous tests
    for {key, _mod} <- TaskRegistry.list() do
      TaskRegistry.unregister(key)
    end

    :ok
  end

  describe "register/2 and lookup/1" do
    test "register by type atom, lookup succeeds" do
      assert :ok = TaskRegistry.register(:my_custom_task, MyTestHandler)
      assert {:ok, MyTestHandler} = TaskRegistry.lookup(:my_custom_task)
    end

    test "register by task ID string, lookup succeeds" do
      assert :ok = TaskRegistry.register("Task_123", MyTestHandler)
      assert {:ok, MyTestHandler} = TaskRegistry.lookup("Task_123")
    end

    test "overwrites previous registration for same key" do
      TaskRegistry.register(:my_task, ModuleA)
      TaskRegistry.register(:my_task, ModuleB)
      assert {:ok, ModuleB} = TaskRegistry.lookup(:my_task)
    end
  end

  describe "unregister/1" do
    test "removes a registered handler" do
      TaskRegistry.register(:temp_task, MyTestHandler)
      assert {:ok, MyTestHandler} = TaskRegistry.lookup(:temp_task)
      assert :ok = TaskRegistry.unregister(:temp_task)
      assert :error = TaskRegistry.lookup(:temp_task)
    end
  end

  describe "lookup/1" do
    test "returns :error for unregistered key" do
      assert :error = TaskRegistry.lookup(:nonexistent)
      assert :error = TaskRegistry.lookup("nonexistent_id")
    end
  end

  describe "list/0" do
    test "returns all registered entries" do
      TaskRegistry.register(:task_a, ModuleA)
      TaskRegistry.register("Task_B", ModuleB)
      entries = TaskRegistry.list()
      assert length(entries) == 2
      assert {:task_a, ModuleA} in entries
      assert {"Task_B", ModuleB} in entries
    end

    test "returns empty list when nothing registered" do
      assert [] = TaskRegistry.list()
    end
  end
end
