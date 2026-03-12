defmodule RodarBpmn.Expression.ScriptRegistryTest do
  use ExUnit.Case, async: false

  alias RodarBpmn.Expression.ScriptRegistry

  setup do
    on_exit(fn ->
      for {lang, _mod} <- ScriptRegistry.list() do
        ScriptRegistry.unregister(lang)
      end
    end)
  end

  describe "register/2 and lookup/1" do
    test "registers an engine module for a language" do
      assert :ok = ScriptRegistry.register("test_lang", SomeModule)
      assert {:ok, SomeModule} = ScriptRegistry.lookup("test_lang")
    end

    test "returns :error for unregistered language" do
      assert :error = ScriptRegistry.lookup("nonexistent")
    end

    test "overwrites previous registration" do
      ScriptRegistry.register("test_lang", ModuleA)
      ScriptRegistry.register("test_lang", ModuleB)
      assert {:ok, ModuleB} = ScriptRegistry.lookup("test_lang")
    end
  end

  describe "unregister/1" do
    test "removes a registered engine" do
      ScriptRegistry.register("test_lang", SomeModule)
      assert :ok = ScriptRegistry.unregister("test_lang")
      assert :error = ScriptRegistry.lookup("test_lang")
    end

    test "is a no-op for unregistered language" do
      assert :ok = ScriptRegistry.unregister("nonexistent")
    end
  end

  describe "list/0" do
    test "returns empty list when nothing is registered" do
      assert [] = ScriptRegistry.list()
    end

    test "returns all registered engines" do
      ScriptRegistry.register("lang_a", ModuleA)
      ScriptRegistry.register("lang_b", ModuleB)

      entries = ScriptRegistry.list()
      assert length(entries) == 2
      assert {"lang_a", ModuleA} in entries
      assert {"lang_b", ModuleB} in entries
    end
  end
end
