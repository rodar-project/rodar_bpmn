defmodule Rodar.TokenTest do
  use ExUnit.Case, async: true

  alias Rodar.Token

  doctest Rodar.Token

  describe "new/1" do
    test "generates unique IDs" do
      token1 = Token.new()
      token2 = Token.new()
      assert token1.id != token2.id
    end

    test "defaults state to :active" do
      token = Token.new()
      assert token.state == :active
    end

    test "defaults parent_id to nil" do
      token = Token.new()
      assert token.parent_id == nil
    end

    test "accepts options" do
      token = Token.new(current_node: "node_1", state: :waiting)
      assert token.current_node == "node_1"
      assert token.state == :waiting
    end

    test "sets created_at timestamp" do
      token = Token.new()
      assert is_integer(token.created_at)
    end
  end

  describe "fork/1" do
    test "creates child with parent reference" do
      parent = Token.new(current_node: "gateway_1")
      child = Token.fork(parent)

      assert child.parent_id == parent.id
      assert child.id != parent.id
      assert child.current_node == parent.current_node
      assert child.state == :active
    end

    test "each fork creates unique tokens" do
      parent = Token.new()
      child1 = Token.fork(parent)
      child2 = Token.fork(parent)

      assert child1.id != child2.id
      assert child1.parent_id == parent.id
      assert child2.parent_id == parent.id
    end
  end
end
