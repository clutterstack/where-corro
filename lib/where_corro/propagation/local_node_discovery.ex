defmodule WhereCorro.Propagation.LocalNodeDiscovery do
  @moduledoc """
  **LOGIC CHANGE**: New discovery module specifically for local development.
  Replaces DNS-based discovery with static configuration.
  """

  require Logger

  @doc """
  **LOGIC CHANGE**: Discover nodes from static local configuration instead of DNS.
  Returns both node_ids and their regions for the propagation map.
  """
  def discover_local_nodes do
    case Application.get_env(:where_corro, :local_cluster_mode, false) do
      true ->
        discover_from_config()

      false ->
        # **LOGIC CHANGE**: Fall back to existing discovery methods
        discover_from_corrosion_or_dns()
    end
  end

  @doc """
  **LOGIC CHANGE**: Get the HTTP endpoint for a specific node in local mode
  """
  def get_node_endpoint(node_id) do
    case Application.get_env(:where_corro, :local_cluster_mode, false) do
      true ->
        get_local_endpoint(node_id)

      false ->
        get_fly_endpoint(node_id)
    end
  end

  @doc """
  **LOGIC CHANGE**: Get all known node regions for the map visualization
  """
  def get_node_regions do
    case Application.get_env(:where_corro, :local_cluster_mode, false) do
      true ->
        local_cluster_nodes()
        |> Enum.map(fn node -> {node.node_id, node.region} end)
        |> Enum.into(%{})

      false ->
        # **LOGIC CHANGE**: Use existing discovery methods
        discover_regions_from_dns()
    end
  end

  # Private functions

  defp discover_from_config do
    local_node_id = current_node_id()

    nodes = local_cluster_nodes()
    |> Enum.reject(fn node -> node.node_id == local_node_id end)
    |> Enum.map(fn node -> {node.node_id, node.region} end)
    |> Enum.into(%{})

    Logger.info("Local cluster discovered #{map_size(nodes)} other nodes: #{inspect(Map.keys(nodes))}")
    {:ok, nodes}
  end

  defp discover_from_corrosion_or_dns do
    # **LOGIC CHANGE**: Keep existing logic but make it explicit
    case WhereCorro.Propagation.NodeDiscovery.discover_from_corrosion() do
      {:ok, corrosion_nodes} when length(corrosion_nodes) > 0 ->
        # Convert to {node_id, region} format
        regions = corrosion_nodes
        |> Enum.map(fn node_id -> {node_id, extract_region_from_node_id(node_id)} end)
        |> Enum.into(%{})
        {:ok, regions}

      _ ->
        # **LOGIC CHANGE**: Fallback to DNS with better error handling
        WhereCorro.Propagation.NodeDiscovery.discover_from_dns()
    end
  end

  defp get_local_endpoint(node_id) do
    case Enum.find(local_cluster_nodes(), fn node -> node.node_id == node_id end) do
      %{port: port} ->
        "http://localhost:#{port}"

      nil ->
        Logger.warning("**LOGIC CHANGE**: Unknown local node #{node_id}, using fallback")
        "http://localhost:4000"  # Fallback
    end
  end

  defp get_fly_endpoint(node_id) do
    # **LOGIC CHANGE**: Keep existing Fly.io logic
    app_name = Application.get_env(:where_corro, :fly_app_name, "where-corro")
    "http://#{node_id}.vm.#{app_name}.internal:8080"
  end

  defp discover_regions_from_dns do
    # **LOGIC CHANGE**: Keep existing DNS discovery logic but make it explicit
    try do
      WhereCorro.FriendFinder.check_regions()
    rescue
      e ->
        Logger.warning("DNS region discovery failed: #{inspect(e)}")
        {:ok, %{}}
    end
  end

  defp local_cluster_nodes do
    Application.get_env(:where_corro, :local_cluster_nodes, [])
  end

  defp current_node_id do
    Application.get_env(:where_corro, :fly_vm_id, "localhost")
  end

  defp extract_region_from_node_id(node_id) do
    # **LOGIC CHANGE**: For unknown nodes, try to guess from node_id pattern
    cond do
      String.contains?(node_id, "node-") ->
        # Local development node
        String.replace(node_id, "node-", "local-")

      node_id == "localhost" ->
        "💻"

      true ->
        "unknown"
    end
  end
end
