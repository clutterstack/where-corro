defmodule WhereCorroWeb.APIController do
  use WhereCorroWeb, :controller
  require Logger
  alias WhereCorro.Propagation.MetricsCollector

  # Keep existing sandwich endpoint for now
  def show(conn, _params) do
    inspect(WhereCorro.GenSandwich.get_sandwich()) |> Logger.info()
    sandwich = WhereCorro.GenSandwich.get_sandwich()

    if is_binary(sandwich) do
      json(conn, %{status: "good", sandwich: sandwich})
    else
      json(conn, %{status: "bad", sandwich: "none"})
    end
  end

  # Add new acknowledgment endpoint
  def acknowledge(conn, %{
        "sequence" => sequence,
        "receiver_id" => receiver_id,
        "acknowledged_at" => ack_time
      }) do
    sender_id = Application.fetch_env!(:where_corro, :fly_vm_id)

    Logger.info("Received ack from #{receiver_id} for message #{sequence}")

    # Update our local acknowledgment record
    ack_id = "#{sender_id}:#{sequence}:#{receiver_id}"

    transactions = [
      """
      INSERT OR REPLACE INTO acknowledgments
        (id, sender_id, sequence, receiver_id, received_at, acknowledged_at, ack_status)
      VALUES
        ('#{ack_id}', '#{sender_id}', #{sequence}, '#{receiver_id}',
         '#{ack_time}', '#{ack_time}', 'success')
      """
    ]

    case WhereCorro.CorroCalls.execute_corro(transactions) do
      {:ok, _} ->
        # Update metrics
        MetricsCollector.record_acknowledgment(sender_id, sequence, receiver_id)

        # Broadcast to LiveView
        Phoenix.PubSub.broadcast(
          WhereCorro.PubSub,
          "propagation:#{sender_id}",
          {:ack_received,
           %{
             sequence: sequence,
             from: receiver_id,
             acknowledged_at: ack_time
           }}
        )

        conn
        |> put_status(:ok)
        |> json(%{status: "acknowledged"})

      {:error, reason} ->
        Logger.error("Failed to record acknowledgment: #{inspect(reason)}")

        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Failed to record acknowledgment"})
    end
  end
end
