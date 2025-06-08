defmodule WhereCorro.Propagation.MetricsCollector do
  @moduledoc """
  Collects and stores propagation metrics for analysis.
  Tracks round-trip times, success rates, and per-node statistics.
  """

  use GenServer
  require Logger

  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_) do
    # Initialize metrics storage
    {:ok, %{
      active_messages: %{},  # {sender_id, sequence} => %{sent_at, acks: %{}, expected_nodes: []}
      completed_metrics: [], # List of completed propagation metrics
      known_nodes: []        # **LOGIC CHANGE**: Nodes from existing discovery system
    }}
  end

  # Client API

  @doc """
  Update the list of known nodes from the discovery system
  """
  def update_known_nodes(node_list) do
    GenServer.cast(__MODULE__, {:update_nodes, node_list})
  end

  @doc """
  Start tracking a new message
  """
  def start_tracking(sender_id, sequence) do
    GenServer.cast(__MODULE__, {:start_tracking, sender_id, sequence, DateTime.utc_now()})
  end

  @doc """
  Record an acknowledgment
  """
  def record_acknowledgment(sender_id, sequence, receiver_id) do
    GenServer.cast(__MODULE__, {:record_ack, sender_id, sequence, receiver_id, DateTime.utc_now()})
  end

  @doc """
  Get current metrics summary
  """
  def get_summary do
    GenServer.call(__MODULE__, :get_summary)
  end

  @doc """
  Get metrics for a specific message
  """
  def get_message_metrics(sender_id, sequence) do
    GenServer.call(__MODULE__, {:get_message_metrics, sender_id, sequence})
  end

  # Server callbacks

  def handle_cast({:update_nodes, node_list}, state) do
    Logger.debug("Updated known nodes: #{inspect(node_list)}")
    {:noreply, %{state | known_nodes: node_list}}
  end

  def handle_cast({:start_tracking, sender_id, sequence, sent_at}, state) do
    key = {sender_id, sequence}

    # **LOGIC CHANGE**: Use known_nodes from discovery system instead of DNS
    expected_nodes = state.known_nodes |> Enum.reject(&(&1 == sender_id))

    message_data = %{
      sent_at: sent_at,
      acks: %{},
      expected_nodes: expected_nodes
    }

    new_state = put_in(state.active_messages[key], message_data)

    # Set a timeout to finalize metrics after 30 seconds
    Process.send_after(self(), {:finalize_metrics, key}, 30_000)

    {:noreply, new_state}
  end

  def handle_cast({:record_ack, sender_id, sequence, receiver_id, ack_time}, state) do
    key = {sender_id, sequence}

    case Map.get(state.active_messages, key) do
      nil ->
        Logger.warning("Received ack for unknown message: #{sender_id}:#{sequence}")
        {:noreply, state}

      message_data ->
        # Calculate round-trip time
        rtt = DateTime.diff(ack_time, message_data.sent_at, :millisecond)

        # Update acks
        updated_acks = Map.put(message_data.acks, receiver_id, %{
          ack_time: ack_time,
          rtt: rtt
        })

        updated_message = Map.put(message_data, :acks, updated_acks)
        new_state = put_in(state.active_messages[key], updated_message)

        # Broadcast metrics update
        broadcast_metrics_update(sender_id, sequence, receiver_id, rtt)

        {:noreply, new_state}
    end
  end

  def handle_call(:get_summary, _from, state) do
    summary = calculate_summary(state.completed_metrics)
    {:reply, summary, state}
  end

  def handle_call({:get_message_metrics, sender_id, sequence}, _from, state) do
    key = {sender_id, sequence}

    metrics = case Map.get(state.active_messages, key) do
      nil ->
        # Check completed metrics
        find_completed_metrics(state.completed_metrics, sender_id, sequence)

      active ->
        calculate_message_metrics(active)
    end

    {:reply, metrics, state}
  end

  def handle_info({:finalize_metrics, key}, state) do
    case Map.get(state.active_messages, key) do
      nil ->
        {:noreply, state}

      message_data ->
        # Calculate final metrics
        metrics = calculate_final_metrics(key, message_data)

        # Store in completed metrics (keep last 100)
        completed = [metrics | state.completed_metrics] |> Enum.take(100)

        # Remove from active
        new_active = Map.delete(state.active_messages, key)

        new_state = %{state |
          active_messages: new_active,
          completed_metrics: completed
        }

        # **LOGIC CHANGE**: Simplified storage - just log for now, remove Corrosion storage
        Logger.info("Message #{elem(key, 0)}:#{elem(key, 1)} metrics: #{format_metrics_summary(metrics)}")

        {:noreply, new_state}
    end
  end

  # Private helpers

  defp calculate_message_metrics(message_data) do
    acked_nodes = Map.keys(message_data.acks)
    expected_count = length(message_data.expected_nodes)
    ack_count = length(acked_nodes)

    rtts = message_data.acks
    |> Map.values()
    |> Enum.map(& &1.rtt)

    %{
      sent_at: message_data.sent_at,
      expected_nodes: expected_count,
      acknowledged_nodes: ack_count,
      success_rate: if(expected_count > 0, do: ack_count / expected_count * 100, else: 0),
      min_rtt: Enum.min(rtts, fn -> nil end),
      max_rtt: Enum.max(rtts, fn -> nil end),
      avg_rtt: if(length(rtts) > 0, do: Enum.sum(rtts) / length(rtts), else: nil),
      missing_nodes: message_data.expected_nodes -- acked_nodes
    }
  end

  defp calculate_final_metrics({sender_id, sequence}, message_data) do
    metrics = calculate_message_metrics(message_data)

    Map.merge(metrics, %{
      sender_id: sender_id,
      sequence: sequence,
      finalized_at: DateTime.utc_now(),
      topology_id: "default"  # For future topology comparisons
    })
  end

  defp calculate_summary(completed_metrics) do
    return_val = %{
      total_messages: 0,
      avg_success_rate: 0,
      avg_rtt: nil,
      min_rtt: nil,
      max_rtt: nil,
      by_node: %{}
    }

    if length(completed_metrics) == 0 do
      return_val
    else
      # Overall stats
      total = length(completed_metrics)
      avg_success = Enum.sum(Enum.map(completed_metrics, & &1.success_rate)) / total

      all_rtts = completed_metrics
      |> Enum.flat_map(fn m -> Map.values(m.acks || %{}) |> Enum.map(& &1.rtt) end)

      # Per-node stats
      by_node = completed_metrics
      |> Enum.reduce(%{}, fn metrics, acc ->
        Enum.reduce(metrics.acks || %{}, acc, fn {node_id, ack_data}, node_acc ->
          update_in(node_acc[node_id], fn
            nil -> %{count: 1, total_rtt: ack_data.rtt, min_rtt: ack_data.rtt, max_rtt: ack_data.rtt}
            existing -> %{
              count: existing.count + 1,
              total_rtt: existing.total_rtt + ack_data.rtt,
              min_rtt: min(existing.min_rtt, ack_data.rtt),
              max_rtt: max(existing.max_rtt, ack_data.rtt)
            }
          end)
        end)
      end)
      |> Enum.map(fn {node_id, stats} ->
        {node_id, Map.put(stats, :avg_rtt, stats.total_rtt / stats.count)}
      end)
      |> Enum.into(%{})

      %{
        total_messages: total,
        avg_success_rate: avg_success,
        avg_rtt: if(length(all_rtts) > 0, do: Enum.sum(all_rtts) / length(all_rtts), else: nil),
        min_rtt: Enum.min(all_rtts, fn -> nil end),
        max_rtt: Enum.max(all_rtts, fn -> nil end),
        by_node: by_node
      }
    end
  end

  defp find_completed_metrics(completed, sender_id, sequence) do
    Enum.find(completed, fn m ->
      m.sender_id == sender_id && m.sequence == sequence
    end)
  end

  defp broadcast_metrics_update(sender_id, sequence, receiver_id, rtt) do
    Phoenix.PubSub.broadcast(WhereCorro.PubSub, "metrics:updates",
      {:metrics_update, %{
        sender_id: sender_id,
        sequence: sequence,
        receiver_id: receiver_id,
        rtt: rtt
      }}
    )
  end

  # **LOGIC CHANGE**: Simple logging instead of Corrosion storage for now
  defp format_metrics_summary(metrics) do
    "Success: #{Float.round(metrics.success_rate, 1)}%, " <>
    "Nodes: #{metrics.acknowledged_nodes}/#{metrics.expected_nodes}, " <>
    "RTT: #{format_rtt(metrics.avg_rtt)}"
  end

  defp format_rtt(nil), do: "N/A"
  defp format_rtt(rtt), do: "#{Float.round(rtt, 1)}ms"
end
