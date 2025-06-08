defmodule WhereCorro.Propagation.Acknowledgment do
  require Logger
  alias WhereCorro.Propagation.LocalNodeDiscovery

  @initial_backoff 100
  @max_backoff 30_000
  @max_attempts 10

  def send_ack(sender_node_id, sequence, receiver_node_id) do
    # Record that we need to send this ack
    ack_id = "#{sender_node_id}:#{sequence}:#{receiver_node_id}"
    Logger.info("🚀 Starting ack process: #{ack_id}")

    transactions = [
      """
      INSERT INTO acknowledgments
        (id, sender_id, sequence, receiver_id, received_at, ack_status)
      VALUES
        ('#{ack_id}', '#{sender_node_id}', #{sequence}, '#{receiver_node_id}',
         '#{DateTime.utc_now() |> DateTime.to_iso8601()}', 'pending')
      """
    ]

    WhereCorro.CorroCalls.execute_corro(transactions)

    # Start async ack process
    Task.Supervisor.start_child(
      WhereCorro.TaskSupervisor,
      fn ->
        Logger.info("📡 Async ack task started for #{ack_id}")
        send_with_retry(sender_node_id, sequence, receiver_node_id, 1)
      end
    )
  end

  defp send_with_retry(sender_node_id, sequence, receiver_node_id, attempt) do
    ack_id = "#{sender_node_id}:#{sequence}:#{receiver_node_id}"
    Logger.info("🔄 Ack attempt #{attempt} for #{ack_id}")

    case call_ack_api(sender_node_id, sequence, receiver_node_id) do
      :ok ->
        Logger.info("✅ Ack succeeded for #{ack_id}")
        mark_success(sender_node_id, sequence, receiver_node_id)

      :error when attempt < @max_attempts ->
        Logger.warning("⚠️  Ack attempt #{attempt} failed for #{ack_id}, retrying...")
        update_attempts(sender_node_id, sequence, receiver_node_id, attempt)
        backoff = min(@initial_backoff * :math.pow(2, attempt), @max_backoff)
        Process.sleep(round(backoff))
        send_with_retry(sender_node_id, sequence, receiver_node_id, attempt + 1)

      :error ->
        mark_failed(sender_node_id, sequence, receiver_node_id)
    end
  end

  defp call_ack_api(sender_node_id, sequence, receiver_node_id) do
    # **LOGIC CHANGE**: Use LocalNodeDiscovery to get the correct endpoint
    base_url = LocalNodeDiscovery.get_node_endpoint(sender_node_id)
    url = "#{base_url}/api/acknowledgment"

    Logger.info("🌐 Sending ack HTTP request to: #{url}")

    body =
      Jason.encode!(%{
        sequence: sequence,
        receiver_id: receiver_node_id,
        acknowledged_at: DateTime.utc_now() |> DateTime.to_iso8601()
      })

    case Finch.build(:post, url, [{"content-type", "application/json"}], body)
         |> Finch.request(WhereCorro.Finch) do
      {:ok, %{status: status}} when status in 200..299 ->
        Logger.info("✅ HTTP ack successful to #{sender_node_id} (status: #{status})")
        :ok

      {:ok, %{status: status, body: response_body}} ->
        Logger.warning("❌ HTTP ack failed to #{sender_node_id} (status: #{status}, body: #{inspect(response_body)})")
        :error

      {:error, %Mint.TransportError{reason: reason}} ->
        Logger.warning("🔌 Network error sending ack to #{sender_node_id}: #{inspect(reason)}")
        :error

      {:error, reason} ->
        Logger.warning("💥 Unexpected error sending ack to #{sender_node_id}: #{inspect(reason)}")
        :error
    end
  end

  # **LOGIC CHANGE**: Remove app_name function since endpoint is now handled by LocalNodeDiscovery

  defp mark_success(sender_id, sequence, receiver_id) do
    update_ack_status(sender_id, sequence, receiver_id, "success", DateTime.utc_now())
  end

  defp mark_failed(sender_id, sequence, receiver_id) do
    update_ack_status(sender_id, sequence, receiver_id, "failed", nil)
  end

  defp update_ack_status(sender_id, sequence, receiver_id, status, ack_time) do
    ack_id = "#{sender_id}:#{sequence}:#{receiver_id}"

    transactions =
      if ack_time do
        [
          """
          UPDATE acknowledgments
          SET ack_status = '#{status}',
              acknowledged_at = '#{DateTime.to_iso8601(ack_time)}'
          WHERE id = '#{ack_id}'
          """
        ]
      else
        [
          """
          UPDATE acknowledgments
          SET ack_status = '#{status}'
          WHERE id = '#{ack_id}'
          """
        ]
      end

    WhereCorro.CorroCalls.execute_corro(transactions)

    # **LOGIC CHANGE**: Enhanced PubSub message with status_time for better tracking
    Phoenix.PubSub.broadcast(
      WhereCorro.PubSub,
      "acknowledgments",
      {:ack_status_changed,
       %{
         sender_id: sender_id,
         sequence: sequence,
         receiver_id: receiver_id,
         status: status,
         status_time: ack_time || DateTime.utc_now()
       }}
    )
  end

  defp update_attempts(sender_id, sequence, receiver_id, attempts) do
    ack_id = "#{sender_id}:#{sequence}:#{receiver_id}"

    transactions = [
      """
      UPDATE acknowledgments
      SET ack_attempts = #{attempts}
      WHERE id = '#{ack_id}'
      """
    ]

    WhereCorro.CorroCalls.execute_corro(transactions)
  end
end
