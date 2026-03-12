defmodule RodarBpmn.Telemetry.LogHandler do
  @moduledoc """
  Default telemetry handler that logs BPMN engine events via `Logger`.

  Converts telemetry events to structured log output at appropriate levels:

  - Node start/stop: `Logger.debug`
  - Node exception: `Logger.error`
  - Process start/stop: `Logger.info`
  - Token create, event bus: `Logger.debug`

  ## Usage

      # Attach the handler (typically in Application.start/2)
      RodarBpmn.Telemetry.LogHandler.attach()

      # Detach when no longer needed
      RodarBpmn.Telemetry.LogHandler.detach()

  """

  require Logger

  @handler_id "rodar_bpmn-default-log-handler"

  @doc """
  Attach the log handler to all BPMN telemetry events.
  """
  @spec attach() :: :ok | {:error, :already_exists}
  def attach do
    :telemetry.attach_many(
      @handler_id,
      RodarBpmn.Telemetry.events(),
      &handle_event/4,
      nil
    )
  end

  @doc """
  Detach the log handler.
  """
  @spec detach() :: :ok | {:error, :not_found}
  def detach do
    :telemetry.detach(@handler_id)
  end

  @doc false
  def handle_event([:rodar_bpmn, :node, :start], _measurements, metadata, _config) do
    Logger.debug(fn ->
      "BPMN node started: #{metadata.node_id} (#{metadata.node_type}) token=#{metadata.token_id}"
    end)
  end

  def handle_event([:rodar_bpmn, :node, :stop], measurements, metadata, _config) do
    duration_us = System.convert_time_unit(measurements.duration, :native, :microsecond)

    Logger.debug(fn ->
      "BPMN node completed: #{metadata.node_id} (#{metadata.node_type}) " <>
        "result=#{metadata.result} duration=#{duration_us}us"
    end)
  end

  def handle_event([:rodar_bpmn, :node, :exception], measurements, metadata, _config) do
    duration_us = System.convert_time_unit(measurements.duration, :native, :microsecond)

    Logger.error(fn ->
      "BPMN node exception: #{metadata.node_id} (#{metadata.node_type}) " <>
        "kind=#{metadata.kind} reason=#{inspect(metadata.reason)} duration=#{duration_us}us"
    end)
  end

  def handle_event([:rodar_bpmn, :process, :start], _measurements, metadata, _config) do
    Logger.info(fn ->
      "BPMN process started: instance=#{metadata.instance_id} process=#{metadata.process_id}"
    end)
  end

  def handle_event([:rodar_bpmn, :process, :stop], measurements, metadata, _config) do
    duration_us = System.convert_time_unit(measurements.duration, :native, :microsecond)

    Logger.info(fn ->
      "BPMN process stopped: instance=#{metadata.instance_id} process=#{metadata.process_id} " <>
        "status=#{metadata.status} duration=#{duration_us}us"
    end)
  end

  def handle_event([:rodar_bpmn, :token, :create], _measurements, metadata, _config) do
    Logger.debug(fn ->
      "BPMN token created: #{metadata.token_id} parent=#{inspect(metadata.parent_id)} " <>
        "node=#{inspect(metadata.node_id)}"
    end)
  end

  def handle_event([:rodar_bpmn, :event_bus, :publish], _measurements, metadata, _config) do
    Logger.debug(fn ->
      "BPMN event published: #{metadata.event_type}/#{metadata.event_name} " <>
        "subscribers=#{metadata.subscriber_count}"
    end)
  end

  def handle_event([:rodar_bpmn, :event_bus, :subscribe], _measurements, metadata, _config) do
    Logger.debug(fn ->
      "BPMN event subscription: #{metadata.event_type}/#{metadata.event_name} " <>
        "node=#{inspect(metadata.node_id)}"
    end)
  end
end
