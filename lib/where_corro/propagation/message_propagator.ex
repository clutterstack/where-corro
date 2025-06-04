defmodule WhereCorro.Propagation.MessagePropagator do
  use GenServer
  require Logger
  alias WhereCorro.Propagation.{Acknowledgment, MetricsCollector}

  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_opts) do
    # Check Corrosion is available
    WhereCorro.StartupChecks.do_corro_checks()

    vm_id = Application.fetch_env!(:where_corro, :fly_vm_id)

    # Initialize this node's entry
    init_node_message(vm_id)

    # Start watching for changes from other nodes
    WhereCorro.CorroCalls.start_watch({
      "message_watch",
      "SELECT node_id, message, sequence, timestamp FROM node_messages"
    })

    {:ok, %{
      node_id: vm_id,
      last_seen_sequences: %{}  # Track what we've seen from each node
    }}
  end

  # Called by button in LiveView
  def send_message do
    GenServer.call(__MODULE__, :send_message)
  end

  def handle_call(:send_message, _from, state) do
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()

    # Get next sequence number (stored in node_messages table)
    sequence = get_next_sequence(state.node_id)

    # Update our message in Corrosion
    transactions = ["""
    UPDATE node_messages
    SET message = '#{timestamp}',
        sequence = #{sequence},
        timestamp = '#{timestamp}'
    WHERE pk = '#{state.node_id}'
    """]

    case WhereCorro.CorroCalls.execute_corro(transactions) do
      {:ok, _} ->
        Logger.info("Sent message #{sequence} with timestamp #{timestamp}")

        # Initialize metrics for this message
        MetricsCollector.start_tracking(state.node_id, sequence)

        # Broadcast to LiveView
        Phoenix.PubSub.broadcast(WhereCorro.PubSub, "propagation:#{state.node_id}",
          {:message_sent, %{sequence: sequence, timestamp: timestamp}}
        )

        {:reply, :ok, state}

      {:error, reason} ->
        Logger.error("Failed to send message: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end

  # Handle incoming messages from Corrosion watch
  def handle_info({"message_watch", [node_id, message, sequence, timestamp]}, state) do
    # Skip our own messages
    if node_id != state.node_id do
      last_sequence = Map.get(state.last_seen_sequences, node_id, -1)

      # Only process if this is a new message
      if sequence > last_sequence do
        Logger.info("Received message #{sequence} from #{node_id}")

        # Send acknowledgment
        Acknowledgment.send_ack(node_id, sequence, state.node_id)

        # Update state
        new_state = put_in(state.last_seen_sequences[node_id], sequence)

        # Broadcast to LiveView
        Phoenix.PubSub.broadcast(WhereCorro.PubSub, "propagation:updates",
          {:message_received, %{
            from: node_id,
            sequence: sequence,
            timestamp: timestamp,
            received_at: DateTime.utc_now()
          }}
        )

        {:noreply, new_state}
      else
        {:noreply, state}
      end
    else
      {:noreply, state}
    end
  end

  defp init_node_message(node_id) do
    transactions = ["""
    INSERT OR IGNORE INTO node_messages (pk, node_id, message, sequence, timestamp)
    VALUES ('#{node_id}', '#{node_id}', '', 0, '#{DateTime.utc_now() |> DateTime.to_iso8601()}')
    """]

    case WhereCorro.CorroCalls.execute_corro(transactions) do
      {:ok, _} -> Logger.info("Initialized node message entry")
      {:error, reason} -> Logger.error("Failed to initialize: #{inspect(reason)}")
    end
  end

  defp get_next_sequence(node_id) do
    # Query current sequence
    case WhereCorro.CorroCalls.query_corro("SELECT sequence FROM node_messages WHERE pk = '#{node_id}'") do
      {:ok, %{"results" => [%{"sequence" => current}]}} -> current + 1
      _ -> 1
    end
  end
end
