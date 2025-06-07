defmodule WhereCorro.Propagation.Acknowledgment do
  require Logger

  @initial_backoff 100
  @max_backoff 30_000
  @max_attempts 10

  def send_ack(sender_node_id, sequence, receiver_node_id) do
    # Record that we need to send this ack
    ack_id = "#{sender_node_id}:#{sequence}:#{receiver_node_id}"

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
      fn -> send_with_retry(sender_node_id, sequence, receiver_node_id, 1) end
    )
  end

  defp send_with_retry(sender_node_id, sequence, receiver_node_id, attempt) do
    case call_ack_api(sender_node_id, sequence, receiver_node_id) do
      :ok ->
        mark_success(sender_node_id, sequence, receiver_node_id)

      :error when attempt < @max_attempts ->
        update_attempts(sender_node_id, sequence, receiver_node_id, attempt)
        backoff = min(@initial_backoff * :math.pow(2, attempt), @max_backoff)
        Process.sleep(round(backoff))
        send_with_retry(sender_node_id, sequence, receiver_node_id, attempt + 1)

      :error ->
        mark_failed(sender_node_id, sequence, receiver_node_id)
    end
  end

  defp call_ack_api(sender_node_id, sequence, receiver_node_id) do
    # For local development or cross-app communication
    base_url = "http://#{sender_node_id}.vm.#{app_name()}.internal:8080"

    url = "#{base_url}/api/acknowledgment"

    body =
      Jason.encode!(%{
        sequence: sequence,
        receiver_id: receiver_node_id,
        acknowledged_at: DateTime.utc_now() |> DateTime.to_iso8601()
      })

    case Finch.build(:post, url, [{"content-type", "application/json"}], body)
         |> Finch.request(WhereCorro.Finch) do
      {:ok, %{status: status}} when status in 200..299 ->
        Logger.info("Successfully sent ack to #{sender_node_id} for message #{sequence}")
        :ok

      error ->
        Logger.warning("Failed to send ack: #{inspect(error)}")
        :error
    end
  end

  defp app_name do
    Application.get_env(:where_corro, :fly_app_name, "where-corro")
  end

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

    # Notify LiveView of status change
    Phoenix.PubSub.broadcast(
      WhereCorro.PubSub,
      "acknowledgments",
      {:ack_status_changed,
       %{
         sender_id: sender_id,
         sequence: sequence,
         receiver_id: receiver_id,
         status: status
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
