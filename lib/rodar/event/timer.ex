defmodule RodarBpmn.Event.Timer do
  @moduledoc """
  Timer parsing and scheduling utilities for BPMN timer events.

  Parses ISO 8601 duration strings and repeating intervals, and schedules
  callbacks using `Process.send_after/3`.

  ## Duration Examples

      iex> RodarBpmn.Event.Timer.parse_duration("PT5S")
      {:ok, 5_000}

      iex> RodarBpmn.Event.Timer.parse_duration("PT1H")
      {:ok, 3_600_000}

      iex> RodarBpmn.Event.Timer.parse_duration("PT1M30S")
      {:ok, 90_000}

      iex> RodarBpmn.Event.Timer.parse_duration("invalid")
      {:error, "invalid ISO 8601 duration: \\"invalid\\""}

  ## Cycle Examples

      iex> RodarBpmn.Event.Timer.parse_cycle("R3/PT10S")
      {:ok, %{repetitions: 3, duration_ms: 10_000}}

      iex> RodarBpmn.Event.Timer.parse_cycle("R/PT1M")
      {:ok, %{repetitions: :infinite, duration_ms: 60_000}}

      iex> RodarBpmn.Event.Timer.parse_cycle("PT30S")
      {:ok, %{repetitions: :infinite, duration_ms: 30_000}}

  """

  @doc """
  Parse an ISO 8601 duration string into milliseconds.

  Supports the `PT` (period time) format with hours (H), minutes (M),
  and seconds (S) components.
  """
  @spec parse_duration(String.t()) :: {:ok, non_neg_integer()} | {:error, String.t()}
  def parse_duration(iso_string) do
    case Regex.named_captures(
           ~r/^PT(?:(?<hours>\d+)H)?(?:(?<minutes>\d+)M)?(?:(?<seconds>\d+)S)?$/,
           iso_string
         ) do
      nil ->
        {:error, "invalid ISO 8601 duration: #{inspect(iso_string)}"}

      %{"hours" => h, "minutes" => m, "seconds" => s} ->
        hours = parse_int(h)
        minutes = parse_int(m)
        seconds = parse_int(s)

        if hours == 0 and minutes == 0 and seconds == 0 do
          {:error, "invalid ISO 8601 duration: #{inspect(iso_string)}"}
        else
          {:ok, (hours * 3600 + minutes * 60 + seconds) * 1000}
        end
    end
  end

  @doc """
  Parse an ISO 8601 repeating interval string.

  Supports formats:
  - `R3/PT10S` — repeat 3 times every 10 seconds
  - `R/PT1M` — repeat indefinitely every 1 minute
  - `PT30S` — bare duration treated as infinite repetition

  Returns `{:ok, %{repetitions: count | :infinite, duration_ms: ms}}`.
  """
  @spec parse_cycle(String.t()) ::
          {:ok, %{repetitions: non_neg_integer() | :infinite, duration_ms: non_neg_integer()}}
          | {:error, String.t()}
  def parse_cycle(cycle_string) do
    case Regex.named_captures(
           ~r/^R(?<reps>\d*)\/(?<duration>.+)$/,
           cycle_string
         ) do
      %{"reps" => reps, "duration" => duration} ->
        parse_cycle_parts(reps, duration)

      nil ->
        # Bare duration string — treat as infinite repetition
        case parse_duration(cycle_string) do
          {:ok, ms} -> {:ok, %{repetitions: :infinite, duration_ms: ms}}
          {:error, _} -> {:error, "invalid ISO 8601 cycle: #{inspect(cycle_string)}"}
        end
    end
  end

  @doc """
  Schedule a timer that sends `{:timer_fired, node_id, outgoing}` to the
  context process after `duration_ms` milliseconds.

  Returns the timer reference which can be used to cancel.
  """
  @spec schedule(non_neg_integer(), pid(), String.t(), [String.t()]) :: reference()
  def schedule(duration_ms, context, node_id, outgoing) do
    Process.send_after(context, {:timer_fired, node_id, outgoing}, duration_ms)
  end

  @doc """
  Schedule a repeating cycle timer.

  Sends `{:timer_cycle_fired, node_id, outgoing, remaining, duration_ms}` to
  the context process. The context handles re-scheduling subsequent firings.

  Returns the timer reference for the first firing.
  """
  @spec schedule_cycle(
          non_neg_integer(),
          pid(),
          String.t(),
          [String.t()],
          non_neg_integer() | :infinite
        ) :: reference()
  def schedule_cycle(duration_ms, context, node_id, outgoing, repetitions) do
    remaining = decrement_repetitions(repetitions)

    Process.send_after(
      context,
      {:timer_cycle_fired, node_id, outgoing, remaining, duration_ms},
      duration_ms
    )
  end

  @doc """
  Cancel a scheduled timer.
  """
  @spec cancel(reference()) :: :ok
  def cancel(timer_ref) do
    Process.cancel_timer(timer_ref)
    :ok
  end

  defp parse_cycle_parts(reps, duration) do
    repetitions = if reps == "", do: :infinite, else: String.to_integer(reps)

    case parse_duration(duration) do
      {:ok, ms} -> {:ok, %{repetitions: repetitions, duration_ms: ms}}
      {:error, _} -> {:error, "invalid ISO 8601 cycle: #{inspect("R#{reps}/#{duration}")}"}
    end
  end

  defp decrement_repetitions(:infinite), do: :infinite
  defp decrement_repetitions(n) when n > 0, do: n - 1
  defp decrement_repetitions(0), do: 0

  defp parse_int(""), do: 0
  defp parse_int(s), do: String.to_integer(s)
end
