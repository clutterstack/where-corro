defmodule WhereCorroWeb.Components.PropagationMap do
  use Phoenix.Component
  require Logger

  # Import the city data from where_machines
  # You'll need to copy this module or create a shared library
  import WhereMachines.CityData

  @bbox {0, 0, 800, 391}
  @minx 0
  @miny 10
  @w 800
  @h 320

  attr :minx, :integer, default: @minx
  attr :miny, :integer, default: @miny
  attr :maxx, :integer, default: @minx + @w
  attr :maxy, :integer, default: @miny + @h
  attr :viewbox, :string, default: "#{@minx} #{@miny} #{@w} #{@h}"
  attr :node_statuses, :map, required: true
  attr :local_node_id, :string, required: true
  attr :node_regions, :map, default: %{}  # node_id => region mapping

  def propagation_map(assigns) do
    ~H"""
    <svg viewBox={@viewbox} stroke-linecap="round" stroke-linejoin="round" xmlns="http://www.w3.org/2000/svg" class="w-full h-full">
      <defs>
        <!-- Gradient for pending nodes -->
        <radialGradient id="pendingGradient" cx="50%" cy="50%" r="50%">
          <stop offset="0%" stop-color="#fbbf24" stop-opacity="0.8"/>
          <stop offset="100%" stop-color="#fbbf24" stop-opacity="0.2"/>
        </radialGradient>

        <!-- Gradient for acknowledged nodes -->
        <radialGradient id="ackGradient" cx="50%" cy="50%" r="50%">
          <stop offset="0%" stop-color="#34d399" stop-opacity="0.8"/>
          <stop offset="100%" stop-color="#34d399" stop-opacity="0.2"/>
        </radialGradient>

        <!-- Gradient for failed nodes -->
        <radialGradient id="failedGradient" cx="50%" cy="50%" r="50%">
          <stop offset="0%" stop-color="#f87171" stop-opacity="0.8"/>
          <stop offset="100%" stop-color="#f87171" stop-opacity="0.2"/>
        </radialGradient>

        <!-- Gradient for local node -->
        <radialGradient id="localGradient" cx="50%" cy="50%" r="50%">
          <stop offset="0%" stop-color="#60a5fa" stop-opacity="1"/>
          <stop offset="100%" stop-color="#60a5fa" stop-opacity="0.3"/>
        </radialGradient>
      </defs>

      <style>
        .propagation-line {
          stroke-dasharray: 5 5;
          animation: dash 1s linear infinite;
        }
        @keyframes dash {
          to { stroke-dashoffset: -10; }
        }
        .latency-label {
          font-size: 12px;
          fill: #6b7280;
          font-family: monospace;
        }
      </style>

      <!-- Background -->
      <rect width="100%" height="100%" fill="#f9fafb" />

      <!-- Grid lines for reference -->
      <g stroke="#e5e7eb" stroke-width="0.5" opacity="0.5">
        <%= for x <- 0..8 do %>
          <line x1={"#{x * 100}"} y1="0" x2={"#{x * 100}"} y2={@h} />
        <% end %>
        <%= for y <- 0..3 do %>
          <line x1="0" y1={"#{y * 100}"} x2={@w} y2={"#{y * 100}"} />
        <% end %>
      </g>

      <!-- Draw connections from local node to all other nodes -->
      <%= if local_coords = get_node_coordinates(@local_node_id, @node_regions, @bbox) do %>
        <%= for {node_id, status} <- @node_statuses do %>
          <%= if node_coords = get_node_coordinates(node_id, @node_regions, @bbox) do %>
            <g>
              <!-- Connection line -->
              <line
                x1={elem(local_coords, 0)}
                y1={elem(local_coords, 1)}
                x2={elem(node_coords, 0)}
                y2={elem(node_coords, 1)}
                stroke={connection_color(status.status)}
                stroke-width="2"
                opacity="0.6"
                class={if status.status == :pending, do: "propagation-line", else: ""}
              />

              <!-- Latency label -->
              <%= if status.latency do %>
                <text
                  x={(elem(local_coords, 0) + elem(node_coords, 0)) / 2}
                  y={(elem(local_coords, 1) + elem(node_coords, 1)) / 2 - 5}
                  text-anchor="middle"
                  class="latency-label"
                >
                  <%= status.latency %>ms
                </text>
              <% end %>
            </g>
          <% end %>
        <% end %>
      <% end %>

      <!-- Draw all nodes -->
      <%= for {node_id, status} <- Map.put(@node_statuses, @local_node_id, %{status: :local}) do %>
        <%= if coords = get_node_coordinates(node_id, @node_regions, @bbox) do %>
          <g transform={"translate(#{elem(coords, 0)}, #{elem(coords, 1)})"}>
            <!-- Node circle with status-based gradient -->
            <circle
              r="12"
              fill={node_gradient_fill(status.status)}
              stroke={node_stroke_color(status.status)}
              stroke-width="2"
            >
              <%= if status.status == :pending do %>
                <animate attributeName="r" values="12;15;12" dur="2s" repeatCount="indefinite" />
              <% end %>
            </circle>

            <!-- Node label -->
            <text
              y="-18"
              text-anchor="middle"
              font-size="14"
              font-weight="bold"
              fill="#374151"
            >
              <%= node_id %>
            </text>

            <!-- Region label -->
            <text
              y="25"
              text-anchor="middle"
              font-size="12"
              fill="#6b7280"
            >
              <%= Map.get(@node_regions, node_id, "?") %>
            </text>
          </g>
        <% end %>
      <% end %>

      <!-- Legend -->
      <g transform="translate(10, 10)">
        <rect x="0" y="0" width="150" height="120" fill="white" stroke="#e5e7eb" rx="5" opacity="0.9" />

        <text x="10" y="20" font-size="14" font-weight="bold" fill="#374151">Status</text>

        <g transform="translate(10, 35)">
          <circle cx="10" cy="0" r="6" fill="url(#localGradient)" />
          <text x="25" y="4" font-size="12" fill="#374151">Local Node</text>
        </g>

        <g transform="translate(10, 55)">
          <circle cx="10" cy="0" r="6" fill="url(#pendingGradient)" />
          <text x="25" y="4" font-size="12" fill="#374151">Pending</text>
        </g>

        <g transform="translate(10, 75)">
          <circle cx="10" cy="0" r="6" fill="url(#ackGradient)" />
          <text x="25" y="4" font-size="12" fill="#374151">Acknowledged</text>
        </g>

        <g transform="translate(10, 95)">
          <circle cx="10" cy="0" r="6" fill="url(#failedGradient)" />
          <text x="25" y="4" font-size="12" fill="#374151">Failed</text>
        </g>
      </g>
    </svg>
    """
  end

  # Helper functions
  defp get_node_coordinates(node_id, node_regions, bbox) do
    # For now, use the region mapping if available
    # Later, you might want to use actual node positions
    if region = Map.get(node_regions, node_id) do
      city_to_svg(region, bbox)
    else
      # Fallback: distribute nodes in a circle if no region info
      # This is temporary until you have proper node discovery
      hash = :erlang.phash2(node_id, 360)
      angle = hash * :math.pi() / 180
      radius = 150
      x = 400 + radius * :math.cos(angle)
      y = 195 + radius * :math.sin(angle)
      {x, y}
    end
  end

  defp city_to_svg(city, bbox) when is_binary(city) do
    try do
      city_atom = String.to_existing_atom(city)
      {long, lat} = cities()[city_atom]
      wgs84_to_svg({long, lat}, bbox)
    rescue
      _ -> nil
    end
  end

  defp wgs84_to_svg({long, lat}, {x_min, y_min, x_max, y_max}) do
    svg_width = x_max - x_min
    svg_height = y_max - y_min

    bounds = %{min_long: -180, max_long: 180, min_lat: -90, max_lat: 90}

    x_percent = (long - bounds.min_long) / (bounds.max_long - bounds.min_long)
    y_percent = 1 - (lat - bounds.min_lat) / (bounds.max_lat - bounds.min_lat)

    x = x_percent * svg_width
    y = y_percent * svg_height

    {x, y}
  end

  defp node_gradient_fill(:local), do: "url(#localGradient)"
  defp node_gradient_fill(:pending), do: "url(#pendingGradient)"
  defp node_gradient_fill(:acknowledged), do: "url(#ackGradient)"
  defp node_gradient_fill(:failed), do: "url(#failedGradient)"
  defp node_gradient_fill(_), do: "#e5e7eb"

  defp node_stroke_color(:local), do: "#3b82f6"
  defp node_stroke_color(:pending), do: "#f59e0b"
  defp node_stroke_color(:acknowledged), do: "#10b981"
  defp node_stroke_color(:failed), do: "#ef4444"
  defp node_stroke_color(_), do: "#9ca3af"

  defp connection_color(:pending), do: "#fbbf24"
  defp connection_color(:acknowledged), do: "#34d399"
  defp connection_color(:failed), do: "#f87171"
  defp connection_color(_), do: "#e5e7eb"
end
