defmodule WhereCorroWeb.PropagationLive do
  use Phoenix.LiveView
  require Logger
  alias WhereCorro.Propagation.MessagePropagator

  def render(assigns) do
    ~H"""
    <div class="min-h-screen overflow-hidden bg-gray-100 py-6 px-6">
      <div class="max-w-7xl mx-auto">
        <!-- Header -->
        <div class="mb-8">
          <h1 class="text-3xl font-bold text-gray-900">Corrosion Message Propagation</h1>
          <p class="mt-2 text-gray-600">
            Node: <span class="font-mono font-bold"><%= @node_id %></span>
            in <span class="font-mono font-bold"><%= @local_region %></span>
          </p>
        </div>

        <!-- Message Sending Section -->
        <div class="bg-white rounded-lg shadow p-6 mb-6">
          <h2 class="text-xl font-semibold mb-4">Send Message</h2>

          <div class="flex items-center space-x-4">
            <button
              phx-click="send_message"
              disabled={@sending}
              class={[
                "px-6 py-2 rounded font-medium transition-colors",
                if @sending do
                  "bg-gray-300 text-gray-500 cursor-not-allowed"
                else
                  "bg-blue-600 text-white hover:bg-blue-700"
                end
              ]}
            >
              <%= if @sending, do: "Sending...", else: "Send Timestamp" %>
            </button>

            <div class="text-sm text-gray-600">
              Last sent:
              <span class="font-mono">
                <%= if @last_sent_message do %>
                  Seq #<%= @last_sent_message.sequence %> at <%= format_time(@last_sent_message.timestamp) %>
                <% else %>
                  Never
                <% end %>
              </span>
            </div>
          </div>
        </div>

        <!-- Current Propagation Status -->
        <div class="bg-white rounded-lg shadow p-6 mb-6">
          <h2 class="text-xl font-semibold mb-4">
            Current Message Status
            <%= if @last_sent_message do %>
              <span class="text-sm font-normal text-gray-600">
                (Sequence #<%= @last_sent_message.sequence %>)
              </span>
            <% end %>
          </h2>

          <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            <%= for {node_id, status} <- @node_statuses do %>
              <div class={[
                "p-4 rounded-lg border-2",
                node_status_class(status.status)
              ]}>
                <div class="font-mono font-bold"><%= node_id %></div>
                <div class="text-sm mt-1">
                  Status: <span class="font-semibold"><%= format_status(status.status) %></span>
                </div>
                <%= if status.latency do %>
                  <div class="text-sm text-gray-600">
                    Latency: <%= status.latency %>ms
                  </div>
                <% end %>
              </div>
            <% end %>
          </div>

          <%= if map_size(@node_statuses) == 0 do %>
            <p class="text-gray-500 text-center py-8">No other nodes detected yet</p>
          <% end %>
        </div>

        <!-- Message History -->
        <div class="bg-white rounded-lg shadow p-6">
          <h2 class="text-xl font-semibold mb-4">Recent Messages from Other Nodes</h2>

          <div class="space-y-2">
            <%= for {node_id, msg} <- @received_messages do %>
              <div class="flex justify-between items-center p-3 bg-gray-50 rounded">
                <div>
                  <span class="font-mono font-bold"><%= node_id %></span>
                  <span class="text-sm text-gray-600 ml-2">
                    Seq #<%= msg.sequence %> - <%= msg.message %>
                  </span>
                </div>
                <div class="text-sm text-gray-500">
                  <%= format_relative_time(msg.received_at) %>
                </div>
              </div>
            <% end %>
          </div>

          <%= if map_size(@received_messages) == 0 do %>
            <p class="text-gray-500 text-center py-8">No messages received yet</p>
          <% end %>
        </div>

        <!-- Debug Info -->
        <details class="mt-6">
          <summary class="cursor-pointer text-sm text-gray-600 hover:text-gray-800">
            Debug Information
          </summary>
          <div class="mt-2 p-4 bg-gray-100 rounded font-mono text-xs">
            <div>Other regions: <%= inspect(@other_regions) %></div>
            <div>Corrosion regions: <%= inspect(@corro_regions) %></div>
            <div>Connected nodes: <%= map_size(@node_statuses) %></div>
          </div>
        </details>
      </div>
    </div>
    """
  end

  def mount(_params, _session, socket) do
    # Subscribe to PubSub topics
    node_id = Application.fetch_env!(:where_corro, :fly_vm_id)

    Phoenix.PubSub.subscribe(WhereCorro.PubSub, "propagation:#{node_id}")
    Phoenix.PubSub.subscribe(WhereCorro.PubSub, "propagation:updates")
    Phoenix.PubSub.subscribe(WhereCorro.PubSub, "acknowledgments")
    Phoenix.PubSub.subscribe(WhereCorro.PubSub, "friend_regions")
    Phoenix.PubSub.subscribe(WhereCorro.PubSub, "corro_regions")

    {:ok, assign(socket,
      node_id: node_id,
      local_region: Application.fetch_env!(:where_corro, :fly_region),
      sending: false,
      last_sent_message: nil,
      node_statuses: %{},  # node_id => %{status: :pending/:acknowledged/:failed, latency: ms}
      received_messages: %{},  # node_id => latest message
      other_regions: [],
      corro_regions: []
    )}
  end

  # Handle button click
  def handle_event("send_message", _params, socket) do
    {:noreply,
      socket
      |> assign(:sending, true)
      |> send_message()
    }
  end

  # PubSub handlers
  def handle_info({:message_sent, %{sequence: seq, timestamp: ts}}, socket) do
    # Reset node statuses for new message
    node_statuses = socket.assigns.node_statuses
    |> Enum.map(fn {node_id, _} -> {node_id, %{status: :pending, latency: nil}} end)
    |> Enum.into(%{})

    {:noreply, assign(socket,
      sending: false,
      last_sent_message: %{sequence: seq, timestamp: ts},
      node_statuses: node_statuses
    )}
  end

  def handle_info({:message_received, %{from: from_node, sequence: seq, timestamp: ts, received_at: received_at}}, socket) do
    # Update received messages
    message = %{
      sequence: seq,
      message: ts,  # timestamp is the message
      received_at: received_at
    }

    {:noreply, put_in(socket.assigns.received_messages[from_node], message)}
  end

  def handle_info({:ack_received, %{sequence: seq, from: from_node, acknowledged_at: ack_time}}, socket) do
    # Only update if this is for our current message
    if socket.assigns.last_sent_message && socket.assigns.last_sent_message.sequence == seq do
      # Calculate latency
      sent_time = socket.assigns.last_sent_message.timestamp
      {:ok, sent_dt, _} = DateTime.from_iso8601(sent_time)
      {:ok, ack_dt, _} = DateTime.from_iso8601(ack_time)
      latency = DateTime.diff(ack_dt, sent_dt, :millisecond)

      # Update node status
      updated_statuses = put_in(
        socket.assigns.node_statuses[from_node],
        %{status: :acknowledged, latency: latency}
      )

      {:noreply, assign(socket, node_statuses: updated_statuses)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:ack_status_changed, %{receiver_id: node_id, status: "failed", sequence: seq}}, socket) do
    # Only update if this is for our current message
    if socket.assigns.last_sent_message && socket.assigns.last_sent_message.sequence == seq do
      updated_statuses = put_in(
        socket.assigns.node_statuses[node_id],
        %{status: :failed, latency: nil}
      )

      {:noreply, assign(socket, node_statuses: updated_statuses)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:other_regions, regions}, socket) do
    # Initialize node statuses for all regions
    all_nodes = get_nodes_in_regions(regions)

    node_statuses = Enum.reduce(all_nodes, socket.assigns.node_statuses, fn node_id, acc ->
      Map.put_new(acc, node_id, %{status: :unknown, latency: nil})
    end)

    {:noreply, assign(socket, other_regions: regions, node_statuses: node_statuses)}
  end

  def handle_info({:corro_regions, regions}, socket) do
    {:noreply, assign(socket, corro_regions: regions)}
  end

  # Private helpers
  defp send_message(socket) do
    case MessagePropagator.send_message() do
      :ok -> socket
      {:error, reason} ->
        Logger.error("Failed to send message: #{inspect(reason)}")
        put_flash(socket, :error, "Failed to send message")
        |> assign(:sending, false)
    end
  end

  defp node_status_class(:pending), do: "border-yellow-400 bg-yellow-50"
  defp node_status_class(:acknowledged), do: "border-green-400 bg-green-50"
  defp node_status_class(:failed), do: "border-red-400 bg-red-50"
  defp node_status_class(_), do: "border-gray-300 bg-gray-50"

  defp format_status(:pending), do: "Pending"
  defp format_status(:acknowledged), do: "Acknowledged"
  defp format_status(:failed), do: "Failed"
  defp format_status(_), do: "Unknown"

  defp format_time(iso_timestamp) do
    case DateTime.from_iso8601(iso_timestamp) do
      {:ok, dt, _} -> Calendar.strftime(dt, "%H:%M:%S")
      _ -> iso_timestamp
    end
  end

  defp format_relative_time(datetime) do
    now = DateTime.utc_now()
    diff = DateTime.diff(now, datetime, :second)

    cond do
      diff < 60 -> "#{diff}s ago"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      true -> "#{div(diff, 3600)}h ago"
    end
  end

  # Placeholder - would need to implement actual node discovery
  defp get_nodes_in_regions(_regions) do
    # For now, return empty list
    # Later, this could query DNS or Corrosion for actual node IDs
    []
  end
end
