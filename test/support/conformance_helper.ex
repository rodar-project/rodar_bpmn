defmodule Rodar.Conformance.TestHelper do
  @moduledoc false

  alias Rodar.{Context, Engine.Diagram}

  @fixture_base "test/fixtures/conformance"

  @doc "Load a BPMN fixture file and parse it."
  def load_fixture(category, filename) do
    path = Path.join([@fixture_base, to_string(category), filename])
    Diagram.load(File.read!(path))
  end

  @doc "Extract elements from the first process in a diagram."
  def first_process_elements(diagram) do
    [{:bpmn_process, _attrs, elements} | _] = diagram.processes
    elements
  end

  @doc "Execute a diagram from its start event with optional init data."
  def execute_from_start(elements, init_data \\ %{}) do
    {:ok, context} = Context.start_link(elements, init_data)

    # Populate :data map so conditions can evaluate (init_data goes to :init only)
    Enum.each(init_data, fn {key, value} ->
      Context.put_data(context, key, value)
    end)

    start = find_start_event(elements)
    result = Rodar.execute(start, context)
    {result, context}
  end

  @doc "Find the first start event with outgoing flows."
  def find_start_event(elements) do
    elements
    |> Enum.find(fn
      {_id, {:bpmn_event_start, %{outgoing: [_ | _]}}} -> true
      _ -> false
    end)
    |> case do
      {_id, event} -> event
      nil -> nil
    end
  end

  @doc "Get unique visited node IDs from execution history."
  def visited_node_ids(context) do
    context
    |> Context.get_history()
    |> Enum.map(& &1.node_id)
    |> Enum.uniq()
  end

  @doc "Assert that the given node IDs were visited during execution."
  def assert_visited(context, node_ids) do
    visited = visited_node_ids(context)

    for id <- List.wrap(node_ids) do
      unless id in visited do
        raise ExUnit.AssertionError,
          message: "Expected node #{inspect(id)} to be visited.\nVisited: #{inspect(visited)}"
      end
    end
  end

  @doc "Assert that the given node IDs were NOT visited during execution."
  def assert_not_visited(context, node_ids) do
    visited = visited_node_ids(context)

    for id <- List.wrap(node_ids) do
      if id in visited do
        raise ExUnit.AssertionError,
          message: "Expected node #{inspect(id)} NOT to be visited.\nVisited: #{inspect(visited)}"
      end
    end
  end

  @doc "Count elements of a given type in a process elements map."
  def count_elements_by_type(elements, type) do
    Enum.count(elements, fn
      {_id, {^type, _}} -> true
      _ -> false
    end)
  end
end

defmodule Rodar.Conformance.PassThroughHandler do
  @moduledoc false
  @behaviour Rodar.TaskHandler

  @impl true
  def token_in({_type, %{outgoing: outgoing}}, context) do
    Rodar.release_token(outgoing, context)
  end
end

defmodule Rodar.Conformance.ErrorHandler do
  @moduledoc false
  @behaviour Rodar.TaskHandler

  @impl true
  def token_in(_elem, _context) do
    {:error, "service_error"}
  end
end
