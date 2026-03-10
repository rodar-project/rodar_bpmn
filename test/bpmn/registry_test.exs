defmodule Bpmn.RegistryTest do
  use ExUnit.Case, async: false

  alias Bpmn.Registry

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

  describe "register/3" do
    test "returns version number" do
      definition = {:bpmn_process, %{id: "proc_1"}, %{}}
      assert {:ok, 1} = Registry.register("proc_1", definition, [])
    end

    test "auto-increments version on re-registration" do
      def1 = {:bpmn_process, %{id: "proc_1"}, %{v: 1}}
      def2 = {:bpmn_process, %{id: "proc_1"}, %{v: 2}}

      assert {:ok, 1} = Registry.register("proc_1", def1, [])
      assert {:ok, 2} = Registry.register("proc_1", def2, [])
    end

    test "allows explicit version number" do
      definition = {:bpmn_process, %{id: "proc_1"}, %{}}
      assert {:ok, 5} = Registry.register("proc_1", definition, version: 5)
    end
  end

  describe "lookup/2" do
    test "returns specific version" do
      def1 = {:bpmn_process, %{id: "proc_1"}, %{v: 1}}
      def2 = {:bpmn_process, %{id: "proc_1"}, %{v: 2}}

      Registry.register("proc_1", def1)
      Registry.register("proc_1", def2)

      assert {:ok, ^def1} = Registry.lookup("proc_1", 1)
      assert {:ok, ^def2} = Registry.lookup("proc_1", 2)
    end

    test "returns :error for nonexistent version" do
      Registry.register("proc_1", {:bpmn_process, %{}, %{}})
      assert :error = Registry.lookup("proc_1", 99)
    end

    test "returns :error for nonexistent process" do
      assert :error = Registry.lookup("nonexistent", 1)
    end
  end

  describe "versions/1" do
    test "returns all versions sorted ascending" do
      Registry.register("proc_1", {:bpmn_process, %{}, %{v: 1}})
      Registry.register("proc_1", {:bpmn_process, %{}, %{v: 2}})
      Registry.register("proc_1", {:bpmn_process, %{}, %{v: 3}})

      versions = Registry.versions("proc_1")
      assert length(versions) == 3
      assert Enum.map(versions, & &1.version) == [1, 2, 3]
      assert Enum.all?(versions, &(&1.deprecated == false))
    end

    test "returns empty list for nonexistent process" do
      assert [] = Registry.versions("nonexistent")
    end
  end

  describe "latest_version/1" do
    test "returns latest version number" do
      Registry.register("proc_1", {:bpmn_process, %{}, %{v: 1}})
      Registry.register("proc_1", {:bpmn_process, %{}, %{v: 2}})

      assert {:ok, 2} = Registry.latest_version("proc_1")
    end

    test "returns :error for nonexistent process" do
      assert :error = Registry.latest_version("nonexistent")
    end
  end

  describe "deprecate/2" do
    test "marks a version as deprecated" do
      Registry.register("proc_1", {:bpmn_process, %{}, %{v: 1}})
      Registry.register("proc_1", {:bpmn_process, %{}, %{v: 2}})

      assert :ok = Registry.deprecate("proc_1", 1)

      versions = Registry.versions("proc_1")
      v1 = Enum.find(versions, &(&1.version == 1))
      v2 = Enum.find(versions, &(&1.version == 2))
      assert v1.deprecated == true
      assert v2.deprecated == false
    end

    test "deprecated version remains accessible" do
      def1 = {:bpmn_process, %{}, %{v: 1}}
      Registry.register("proc_1", def1)
      Registry.deprecate("proc_1", 1)

      assert {:ok, ^def1} = Registry.lookup("proc_1", 1)
    end

    test "returns :error for nonexistent process" do
      assert :error = Registry.deprecate("nonexistent", 1)
    end

    test "returns :error for nonexistent version" do
      Registry.register("proc_1", {:bpmn_process, %{}, %{}})
      assert :error = Registry.deprecate("proc_1", 99)
    end
  end

  describe "backward compatibility" do
    test "register/2 still returns :ok" do
      assert :ok = Registry.register("proc_1", {:bpmn_process, %{}, %{}})
    end

    test "lookup/1 returns latest after multiple registrations" do
      def1 = {:bpmn_process, %{}, %{v: 1}}
      def2 = {:bpmn_process, %{}, %{v: 2}}

      Registry.register("proc_1", def1)
      Registry.register("proc_1", def2)

      assert {:ok, ^def2} = Registry.lookup("proc_1")
    end

    test "unregister/1 removes all versions" do
      Registry.register("proc_1", {:bpmn_process, %{}, %{v: 1}})
      Registry.register("proc_1", {:bpmn_process, %{}, %{v: 2}})
      Registry.unregister("proc_1")

      assert :error = Registry.lookup("proc_1")
      assert :error = Registry.lookup("proc_1", 1)
      assert [] = Registry.versions("proc_1")
    end
  end
end
