defmodule RodarBpmn.Event.Start do
  @moduledoc """
  Handle passing the token through an event element.

  # Start Event

  A BPMN start event can have the following BPMN contents:

    <bpmn:startEvent id="StartEvent_1" name="START" camunda:initiator="HTTP">
      <bpmn:outgoing>SequenceFlow_0u2ggjm</bpmn:outgoing>

      <bpmn:extensionElements>
        <camunda:formData>
          <camunda:formField id="username" label="Username" type="string">
            <camunda:validation>
              <camunda:constraint name="username" config="required" />
              <camunda:constraint name="password" config="required" />
            </camunda:validation>
          </camunda:formField>
          <camunda:formField id="password" label="Password" type="string" />
        </camunda:formData>
        <camunda:executionListener class="bpmn.event.start.listener" event="start" />
      </bpmn:extensionElements>
    </bpmn:startEvent>

  This node can be represented as the following Elixir token:

    {:bpmn_event_start,
      %{
        id: "StartEvent_1",
        name: "START",
        outgoing: ["SequenceFlow_0u2ggjm"],
        inputs: [%{"username"=>"user", "password"=>"password"}],
        definitions: [{:error_event_definition, %{}}]
      }
    }

  ## Examples

    iex> {:ok, context} = RodarBpmn.Context.start_link(%{}, %{})
    iex> {:ok, pid} = RodarBpmn.Event.Start.token_in({:bpmn_event_start, %{outgoing: []}}, context)
    iex> context == pid
    true

    iex> {:ok, context} = RodarBpmn.Context.start_link(%{"to" => {:bpmn_activity_task_script, %{}}}, %{})
    iex> {:not_implemented} = RodarBpmn.Event.Start.token_in({:bpmn_event_start, %{outgoing: ["to"]}}, context)
    iex> true
    true

  """

  @doc """
  Receive the token for the element and decide if the business logic should be executed

  @todo:
    - Load input data into the context based on the given inputs
    - Check the event definitions and wait for the event to be triggered before executing the event

  """
  @spec token_in(RodarBpmn.element(), RodarBpmn.context()) :: RodarBpmn.result()
  def token_in({:bpmn_event_start, %{outgoing: []}}, context), do: {:ok, context}
  def token_in(elem, context), do: execute(elem, context)

  @doc """
  Execute the start event business logic
  """
  @spec execute(RodarBpmn.element(), RodarBpmn.context()) :: RodarBpmn.result()
  def execute({:bpmn_event_start, %{outgoing: outgoing} = _event}, context) do
    token_out(outgoing, context)
  end

  defp token_out(targets, context), do: RodarBpmn.release_token(targets, context)
end
