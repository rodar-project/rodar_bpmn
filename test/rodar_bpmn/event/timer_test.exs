defmodule RodarBpmn.Event.TimerTest do
  use ExUnit.Case, async: true

  alias RodarBpmn.Event.Timer

  describe "parse_duration/1" do
    test "parses seconds" do
      assert Timer.parse_duration("PT5S") == {:ok, 5_000}
      assert Timer.parse_duration("PT30S") == {:ok, 30_000}
    end

    test "parses minutes" do
      assert Timer.parse_duration("PT1M") == {:ok, 60_000}
      assert Timer.parse_duration("PT15M") == {:ok, 900_000}
    end

    test "parses hours" do
      assert Timer.parse_duration("PT1H") == {:ok, 3_600_000}
      assert Timer.parse_duration("PT2H") == {:ok, 7_200_000}
    end

    test "parses combined duration" do
      assert Timer.parse_duration("PT1H30M") == {:ok, 5_400_000}
      assert Timer.parse_duration("PT1M30S") == {:ok, 90_000}
      assert Timer.parse_duration("PT2H15M30S") == {:ok, 8_130_000}
    end

    test "returns error for invalid format" do
      assert {:error, _} = Timer.parse_duration("invalid")
      assert {:error, _} = Timer.parse_duration("P1D")
      assert {:error, _} = Timer.parse_duration("")
      assert {:error, _} = Timer.parse_duration("PT")
    end
  end

  describe "parse_cycle/1" do
    test "parses finite repetition with duration" do
      assert Timer.parse_cycle("R3/PT10S") == {:ok, %{repetitions: 3, duration_ms: 10_000}}
      assert Timer.parse_cycle("R5/PT1M") == {:ok, %{repetitions: 5, duration_ms: 60_000}}
      assert Timer.parse_cycle("R1/PT2H30M") == {:ok, %{repetitions: 1, duration_ms: 9_000_000}}
    end

    test "parses infinite repetition (R without count)" do
      assert Timer.parse_cycle("R/PT1M") == {:ok, %{repetitions: :infinite, duration_ms: 60_000}}
      assert Timer.parse_cycle("R/PT30S") == {:ok, %{repetitions: :infinite, duration_ms: 30_000}}
    end

    test "bare duration treated as infinite cycle" do
      assert Timer.parse_cycle("PT30S") == {:ok, %{repetitions: :infinite, duration_ms: 30_000}}
      assert Timer.parse_cycle("PT1H") == {:ok, %{repetitions: :infinite, duration_ms: 3_600_000}}
    end

    test "returns error for invalid cycle format" do
      assert {:error, _} = Timer.parse_cycle("invalid")
      assert {:error, _} = Timer.parse_cycle("R3/invalid")
      assert {:error, _} = Timer.parse_cycle("")
    end
  end

  describe "schedule/4 and cancel/1" do
    test "schedules a timer and receives the message" do
      {:ok, _context} = RodarBpmn.Context.start_link(%{}, %{})
      timer_ref = Timer.schedule(10, self(), "node1", ["flow_out"])

      assert is_reference(timer_ref)
      assert_receive {:timer_fired, "node1", ["flow_out"]}, 100
    end

    test "cancel prevents the timer from firing" do
      timer_ref = Timer.schedule(50, self(), "node1", ["flow_out"])
      Timer.cancel(timer_ref)

      refute_receive {:timer_fired, _, _}, 100
    end
  end

  describe "schedule_cycle/5" do
    test "sends timer_cycle_fired with remaining count" do
      timer_ref = Timer.schedule_cycle(10, self(), "node1", ["flow_out"], 3)

      assert is_reference(timer_ref)
      assert_receive {:timer_cycle_fired, "node1", ["flow_out"], 2, 10}, 100
    end

    test "infinite repetition sends :infinite as remaining" do
      timer_ref = Timer.schedule_cycle(10, self(), "node1", ["flow_out"], :infinite)

      assert is_reference(timer_ref)
      assert_receive {:timer_cycle_fired, "node1", ["flow_out"], :infinite, 10}, 100
    end

    test "cancel prevents cycle timer from firing" do
      timer_ref = Timer.schedule_cycle(50, self(), "node1", ["flow_out"], 3)
      Timer.cancel(timer_ref)

      refute_receive {:timer_cycle_fired, _, _, _, _}, 100
    end
  end

  describe "cycle timer integration with Context" do
    test "context marks node completed on last cycle firing" do
      {:ok, context} = RodarBpmn.Context.start_link(%{}, %{})

      # Simulate last cycle firing (remaining = 0)
      send(context, {:timer_cycle_fired, "node1", [], 0, 10})
      Process.sleep(20)

      meta = RodarBpmn.Context.get_meta(context, "node1")
      assert meta.completed == true
      assert meta.active == false
    end

    test "context reschedules when remaining > 0" do
      {:ok, context} = RodarBpmn.Context.start_link(%{}, %{})

      # Simulate a cycle firing with 1 remaining
      send(context, {:timer_cycle_fired, "node1", [], 1, 500})
      Process.sleep(20)

      # Should have rescheduled — node stays active
      meta = RodarBpmn.Context.get_meta(context, "node1")
      assert meta.active == true
      assert meta.completed == false
      assert is_reference(meta.timer_ref)

      # Cancel to avoid leaking timers
      Timer.cancel(meta.timer_ref)
    end

    test "full cycle fires expected number of times" do
      {:ok, context} = RodarBpmn.Context.start_link(%{}, %{})

      # 2 repetitions at 20ms interval
      Timer.schedule_cycle(20, context, "node1", [], 2)

      # Wait enough for both firings to complete (2 * 20ms + buffer)
      Process.sleep(100)

      meta = RodarBpmn.Context.get_meta(context, "node1")
      assert meta.completed == true
      assert meta.active == false
    end
  end
end
