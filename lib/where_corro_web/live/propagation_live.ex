defmodule WhereCorroWeb.PropagationLive do
  use Phoenix.LiveView
  require Logger
  alias WhereCorro.Propagation.MessagePropagator
  alias WhereCorroWeb.Components.PropagationMap

  def render(assigns) do
    ~H"""
    <div class="min-h-screen overflow-hidden bg-gray-100 py-6 px-6">
      <div class="max-w-7xl mx-auto">
        <!-- Header -->
        <div class="mb-8">
          <h1 class="text-3xl font-bold text-gray-900">Corrosion Message Propagation</h1>
          <p class="mt-2 text-gray-600">
            Node: <span class="font-mono font-bold">{@node_id}</span>
            in <span class="font-mono font-bold">{@local_region}</span>
          </p>
        </div>

    <!-- Propagation Map -->
        <div class="bg-white rounded-lg shadow p-6 mb-6">
          <h2 class="text-xl font-semibold mb-4">Propagation Visualization</h2>
          <div class="h-96">
            <PropagationMap.propagation_map
              node_statuses={@node_statuses}
              local_node_id={@node_id}
              node_regions={@node_regions}
            />
          </div>
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
              {if @sending, do: "Sending...", else: "Send Timestamp"}
            </button>

            <div class="text-sm text-gray-600">
              Last sent:
              <span class="font-mono">
                <%= if @last_sent_message do %>
                  Seq #{@last_sent_message.sequence} at {format_time(@last_sent_message.timestamp)}
                <% else %>
                  Never
                <% end %>
              </span>
            </div>
          </div>
        </div>

    <!-- Current Propagation Status Grid -->
        <div class="bg-white rounded-lg shadow p-6 mb-6">
          <h2 class="text-xl font-semibold mb-4">
            Node Status Details
            <%= if @last_sent_message do %>
              <span class="text-sm font-normal text-gray-600">
                (Sequence #{@last_sent_message.sequence})
              </span>
            <% end %>
          </h2>

          <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            <%= for {node_id, status} <- @node_statuses do %>
              <div class={[
  "p-4 rounded-lg border-2",
  node_status_class(status.status)
]}>
  <div class="font-mono font-bold">{node_id}</div>
  <div class="text-sm text-gray-600">
    Region: {Map.get(@node_regions, node_id, "unknown")}
  </div>
  <div class="text-sm mt-1">
    Status: <span class="font-semibold">{format_status(status.status)}</span>
  </div>
  <%= if timing_info = format_node_timing(status) do %>
    <div class="text-sm text-gray-600">
      {timing_info}
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

          <div class="space-y-2 max-h-64 overflow-y-auto">
            <%= for {node_id, msg} <- @received_messages |> Enum.sort_by(fn {_, m} -> m.received_at end, {:desc, DateTime}) |> Enum.take(10) do %>
              <div class="flex justify-between items-center p-3 bg-gray-50 rounded">
                <div>
                  <span class="font-mono font-bold">{node_id}</span>
                  <span class="text-xs text-gray-500 ml-1">
                    ({Map.get(@node_regions, node_id, "?")})
                  </span>
                  <span class="text-sm text-gray-600 ml-2">
                    Seq #{msg.sequence} - {msg.message}
                  </span>
                </div>
                <div class="text-sm text-gray-500">
                  {format_relative_time(msg.received_at)}
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
          <div class="mt-2 p-4 bg-gray-100 rounded font-mono text-xs overflow-x-auto">
            <div>Node ID: {@node_id}</div>
            <div>Local Region: {@local_region}</div>
            <div>Other regions: {inspect(@other_regions)}</div>
            <div>Corrosion regions: {inspect(@corro_regions)}</div>
            <div>Connected nodes: {map_size(@node_statuses)}</div>
            <div>Node regions: {inspect(@node_regions)}</div>
            <div>Discovered nodes: {inspect(@discovered_nodes)}</div>
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

    # Initialize with self in node_regions
    node_regions = %{node_id => Application.fetch_env!(:where_corro, :fly_region)}

    # **LOGIC CHANGE**: Query Corrosion for existing nodes immediately
    discovered_nodes = discover_existing_nodes()

    initial_node_statuses =
      discovered_nodes
      |> Enum.reject(fn {discovered_node_id, _} -> discovered_node_id == node_id end)
      |> Enum.map(fn {discovered_node_id, region} ->
        {discovered_node_id, %{status: :unknown, latency: nil}}
      end)
      |> Enum.into(%{})

    updated_regions = discovered_nodes |> Enum.into(node_regions)

    {:ok,
     assign(socket,
       node_id: node_id,
       local_region: Application.fetch_env!(:where_corro, :fly_region),
       sending: false,
       last_sent_message: nil,
       node_statuses: initial_node_statuses,
       received_messages: %{},
       node_regions: updated_regions,
       other_regions: [],
       corro_regions: [],
       # **NEW**: Track discovered nodes for debugging
       discovered_nodes: discovered_nodes
     )}
  end

  # Handle button click
  def handle_event("send_message", _params, socket) do
    {:noreply,
     socket
     |> assign(:sending, true)
     |> send_message()}
  end

  # PubSub handlers
  def handle_info({:message_sent, %{sequence: seq, timestamp: ts}}, socket) do
    # **LOGIC CHANGE**: Reset node statuses for new message and mark as pending
    node_statuses =
      socket.assigns.node_statuses
      |> Enum.map(fn {node_id, _} -> {node_id, %{status: :pending, latency: nil}} end)
      |> Enum.into(%{})

    {:noreply,
     assign(socket,
       sending: false,
       last_sent_message: %{sequence: seq, timestamp: ts},
       node_statuses: node_statuses
     )}
  end

  def handle_info(
        {:message_received,
         %{from: from_node, sequence: seq, timestamp: ts, received_at: received_at}},
        socket
      ) do
    # **LOGIC CHANGE**: Update received messages and try to add node to regions
    message = %{
      sequence: seq,
      # timestamp is the message
      message: ts,
      received_at: received_at
    }

    updated_regions = maybe_add_node_region(socket.assigns.node_regions, from_node)

    updated_statuses =
      Map.put_new(socket.assigns.node_statuses, from_node, %{status: :unknown, latency: nil})

    {:noreply,
     socket
     |> put_in([:assigns, :received_messages, from_node], message)
     |> assign(:node_regions, updated_regions)
     |> assign(:node_statuses, updated_statuses)}
  end

  def handle_info(
        {:ack_received, %{sequence: seq, from: from_node, acknowledged_at: ack_time}},
        socket
      ) do
    # Only update if this is for our current message
    if socket.assigns.last_sent_message && socket.assigns.last_sent_message.sequence == seq do
      # Calculate latency
      sent_time = socket.assigns.last_sent_message.timestamp
      {:ok, sent_dt, _} = DateTime.from_iso8601(sent_time)
      {:ok, ack_dt, _} = DateTime.from_iso8601(ack_time)
      latency = DateTime.diff(ack_dt, sent_dt, :millisecond)

      # Update node status
      updated_statuses =
        put_in(
          socket.assigns.node_statuses[from_node],
          %{status: :acknowledged, latency: latency}
        )

      {:noreply, assign(socket, node_statuses: updated_statuses)}
    else
      {:noreply, socket}
    end
  end

def handle_info(
      {:ack_status_changed, %{receiver_id: node_id, status: status, sequence: seq, status_time: status_time}},
      socket
    ) do
  # Only update if this is for our current message
  if socket.assigns.last_sent_message && socket.assigns.last_sent_message.sequence == seq do
    case status do
      "success" ->
        # Calculate latency for successful acks
        sent_time = socket.assigns.last_sent_message.timestamp
        {:ok, sent_dt, _} = DateTime.from_iso8601(sent_time)
        {:ok, ack_dt, _} = DateTime.from_iso8601(DateTime.to_iso8601(status_time))
        latency = DateTime.diff(ack_dt, sent_dt, :millisecond)

        updated_statuses =
          put_in(
            socket.assigns.node_statuses[node_id],
            %{status: :acknowledged, latency: latency}
          )

        {:noreply, assign(socket, node_statuses: updated_statuses)}

      "failed" ->
        # **LOGIC CHANGE**: For failed acks, calculate "time to failure" instead of latency
        sent_time = socket.assigns.last_sent_message.timestamp
        {:ok, sent_dt, _} = DateTime.from_iso8601(sent_time)
        {:ok, fail_dt, _} = DateTime.from_iso8601(DateTime.to_iso8601(status_time))
        time_to_failure = DateTime.diff(fail_dt, sent_dt, :millisecond)

        updated_statuses =
          put_in(
            socket.assigns.node_statuses[node_id],
            %{status: :failed, latency: nil, time_to_failure: time_to_failure}
          )

        {:noreply, assign(socket, node_statuses: updated_statuses)}

      _ ->
        {:noreply, socket}
    end
  else
    {:noreply, socket}
  end
end



  # Add this to the existing PropagationLive - just the key changes:

  def handle_info({:other_regions, regions}, socket) do
    # **LOGIC CHANGE**: Merge with discovered nodes from Corrosion
    additional_nodes = discover_nodes_in_regions(regions)
    all_discovered = Map.merge(socket.assigns.discovered_nodes, additional_nodes)

    {node_statuses, node_regions} = Enum.reduce(all_discovered, {socket.assigns.node_statuses, socket.assigns.node_regions},
      fn {node_id, region}, {statuses, regions} ->
        # Skip our own node
        if node_id != socket.assigns.node_id do
          statuses = Map.put_new(statuses, node_id, %{status: :unknown, latency: nil})
          regions = Map.put(regions, node_id, region)
          {statuses, regions}
        else
          {statuses, regions}
        end
      end
    )

    # **LOGIC CHANGE**: Update metrics collector with known nodes
    known_node_ids = Map.keys(node_statuses)
    WhereCorro.Propagation.MetricsCollector.update_known_nodes(known_node_ids)

    {:noreply, assign(socket,
      other_regions: regions,
      node_statuses: node_statuses,
      node_regions: node_regions,
      discovered_nodes: all_discovered
    )}
  end

  def handle_info({:corro_regions, regions}, socket) do
    {:noreply, assign(socket, corro_regions: regions)}
  end


  # **LOGIC CHANGE**: Update the node status display function
defp format_node_timing(status) do
  case status do
    %{status: :acknowledged, latency: latency} when is_number(latency) ->
      "RTT: #{latency}ms"

    %{status: :failed, time_to_failure: ttf} when is_number(ttf) ->
      "Failed after #{ttf}ms"

    %{status: :pending} ->
      "Waiting..."

    _ ->
      nil  # **LOGIC CHANGE**: Return nil instead of empty string for cleaner template logic
  end
end
  # Discover existing nodes from Corrosion
  # **LOGIC CHANGE**: Also update when we discover nodes from Corrosion
  defp discover_existing_nodes do
    case WhereCorro.CorroCalls.query_corro("SELECT DISTINCT node_id FROM node_messages WHERE node_id != ''") do
      {:ok, %{rows: rows}} ->
        discovered = rows
        |> List.flatten()
        |> Enum.map(fn node_id ->
          # Try to get region from app name pattern or use unknown
          region = extract_region_from_node_id(node_id)
          {node_id, region}
        end)
        |> Enum.into(%{})

        # **LOGIC CHANGE**: Update metrics collector immediately with discovered nodes
        discovered
        |> Map.keys()
        |> Enum.reject(&(&1 == Application.fetch_env!(:where_corro, :fly_vm_id)))
        |> WhereCorro.Propagation.MetricsCollector.update_known_nodes()

        discovered

      {:error, reason} ->
        Logger.warning("Failed to query existing nodes: #{inspect(reason)}")
        %{}
    end
  end

  # **NEW**: Extract region from node ID (Fly.io machine IDs don't contain region, so this is a fallback)
  defp extract_region_from_node_id(node_id) do
    # For local development
    if node_id == "localhost", do: "💻", else: "unknown"
  end

  # Private helpers
  defp send_message(socket) do
    case MessagePropagator.send_message() do
      :ok ->
        socket

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

  # Node discovery helpers
  defp discover_nodes_in_regions(regions) do
    # This is a placeholder implementation
    # In production, you'd query DNS or Corrosion for actual nodes
    # For now, let's simulate some nodes
    app_name = Application.get_env(:where_corro, :fly_app_name, "where-corro")

    # Query DNS for instances
    case get_instances_from_dns(app_name) do
      {:ok, instances} ->
        # Filter by regions and create node_id => region map
        instances
        |> Enum.filter(fn {_, region} -> region in regions end)
        |> Enum.into(%{})

      {:error, _} ->
        # Fallback: empty map
        %{}
    end
  end

  defp get_instances_from_dns(app_name) do

    dns_name = "vms.#{app_name}.internal"

    :inet_res.getbyname(String.to_charlist(dns_name), :txt) |> dbg

    case :inet_res.getbyname(String.to_charlist(dns_name), :txt) do
      {:ok, {:hostent, _, _, :txt, _, [records]}} ->
        instances =
          records
          |> List.to_string()
          |> String.split(";")
          |> Enum.map(&parse_instance_record/1)
          |> Enum.reject(&is_nil/1)
          |> Enum.into(%{}) |> inspect() |> Logger.info()

        {:ok, instances}

      {:error, reason} ->
        Logger.warning("Failed to resolve DNS for #{dns_name}: #{inspect(reason)}")
        {:error, reason}
    end
  rescue
    e ->
      Logger.warning("DNS resolution error: #{inspect(e)}")
      {:error, e}
  end

  defp parse_instance_record(record) do
    # Parse "app=name,region=abc,instance=xyz" format
    parts =
      record
      |> String.split(",")
      |> Enum.map(&String.split(&1, "="))
      |> Enum.filter(&(length(&1) == 2))
      |> Enum.map(fn [k, v] -> {k, v} end)
      |> Enum.into(%{})

    case parts do
      %{"instance" => instance_id, "region" => region} ->
        {instance_id, region}

      _ ->
        nil
    end
  end

  defp maybe_add_node_region(node_regions, node_id) do
    # If we don't know this node's region yet, try to discover it
    if Map.has_key?(node_regions, node_id) do
      node_regions
    else
      # This is a simplified approach - in production you'd want
      # to query the node directly or use DNS discovery
      Map.put(node_regions, node_id, "unknown")
    end
  end
end
