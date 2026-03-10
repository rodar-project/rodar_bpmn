defmodule Bpmn.Persistence.Adapter.ETSTest do
  use ExUnit.Case, async: false

  alias Bpmn.Persistence.Adapter.ETS

  setup do
    # The ETS adapter is started by the application supervision tree via config.
    # Clear table between tests.
    :ets.delete_all_objects(:bpmn_persistence)
    :ok
  end

  test "save and load roundtrip" do
    snapshot = %{version: 1, instance_id: "id-1", data: "hello"}
    assert :ok = ETS.save("id-1", snapshot)

    assert {:ok, loaded} = ETS.load("id-1")
    assert loaded == snapshot
  end

  test "load returns error for missing key" do
    assert {:error, :not_found} = ETS.load("nonexistent")
  end

  test "delete removes an entry" do
    ETS.save("id-2", %{data: "test"})
    assert {:ok, _} = ETS.load("id-2")

    assert :ok = ETS.delete("id-2")
    assert {:error, :not_found} = ETS.load("id-2")
  end

  test "list returns all instance IDs" do
    ETS.save("a", %{data: 1})
    ETS.save("b", %{data: 2})
    ETS.save("c", %{data: 3})

    ids = ETS.list()
    assert Enum.sort(ids) == ["a", "b", "c"]
  end

  test "overwrite existing entry" do
    ETS.save("id-3", %{data: "original"})
    ETS.save("id-3", %{data: "updated"})

    assert {:ok, loaded} = ETS.load("id-3")
    assert loaded == %{data: "updated"}
  end

  test "delete on nonexistent key is no-op" do
    assert :ok = ETS.delete("nope")
  end
end
