defmodule WhereCorro.Propagation.MessagePropagator do
  use GenServer
  require Logger
  alias WhereCorro.Propagation.{Acknowledgment, MetricsCollector}

  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_opts) do
    # **LOGIC CHANGE**: More robust local development handling
    corro_builtin = Application.fetch_env!(:where_corro, :corro_builtin)
    node_id = Application.fetch_env!(:where_corro, :fly_vm_id)

    # **LOGIC CHANGE**: Skip all DNS checks and Corrosion connectivity in local mode
    if corro_builtin == "1" and node_id == "localhost" do
      Logger.info("Running in local development mode - skipping DNS and Corrosion checks")
    else
      # Production mode - check Corrosion availability with better error handling
      case safe_corro_checks() do
        {:ok, []} ->
          Logger.info("Corrosion connectivity checks passed")
        {:error, reason} ->
          Logger.warning("Corrosion connectivity checks failed: #{inspect(reason)}")
          # Continue anyway for now - you might want to exit here in production
      end
    end

    # Initialize this node's entry
    init_node_message(node_id)

    # **LOGIC CHANGE**: Only start watching if not in local single-node mode
    if should_start_watching?(corro_builtin, node_id) do
      start_corrosion_watch()
    else
      Logger.info("Skipping Corrosion watch in local single-node mode")
    end

    {:ok, %{
      node_id: node_id,
      last_seen_sequences: %{},
      processed_messages: %{}  # **LOGIC CHANGE**: Add deduplication state
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
      # **LOGIC CHANGE**: Use compound key for deduplication
      message_key = {node_id, sequence}

      unless Map.has_key?(state.processed_messages, message_key) do
        Logger.info("Received message #{sequence} from #{node_id}")

        # Send acknowledgment
        Acknowledgment.send_ack(node_id, sequence, state.node_id)

        # **LOGIC CHANGE**: Update state with processed message tracking
        new_state = state
        |> put_in([:last_seen_sequences, node_id], sequence)
        |> put_in([:processed_messages, message_key], true)

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

  # **LOGIC CHANGE**: New helper functions for safer initialization

  defp safe_corro_checks do
    try do
      WhereCorro.StartupChecks.do_corro_checks()
    rescue
      exception ->
        Logger.warning("Exception during Corrosion checks: #{inspect(exception)}")
        {:error, {:exception, exception}}
    catch
      :exit, reason ->
        Logger.warning("Exit during Corrosion checks: #{inspect(reason)}")
        {:error, {:exit, reason}}
    end
  end

  defp should_start_watching?(corro_builtin, node_id) do
    # **LOGIC CHANGE**: Don't start watching in local single-node development
    not (corro_builtin == "1" and node_id == "localhost")
  end

  defp start_corrosion_watch do
    try do
      WhereCorro.CorroCalls.start_watch({
        "message_watch",
        "SELECT node_id, message, sequence, timestamp FROM node_messages"
      })
      Logger.info("Started Corrosion message watch")
    rescue
      exception ->
        Logger.error("Failed to start Corrosion watch: #{inspect(exception)}")
        # **LOGIC CHANGE**: Don't crash the GenServer, just log and continue
    catch
      :exit, reason ->
        Logger.error("Exit while starting Corrosion watch: #{inspect(reason)}")
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
