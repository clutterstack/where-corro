defmodule WhereCorro.Propagation.NodeDiscovery do
  @moduledoc """
  **LOGIC CHANGE**: Simplified node discovery that primarily uses Corrosion data
  with DNS as fallback only. Removes complex mixing of discovery methods.
  """

  require Logger

  @doc """
  Discover active nodes from Corrosion database.
  This is our primary discovery method.
  """
  def discover_from_corrosion do
    case WhereCorro.CorroCalls.query_corro(
      "SELECT DISTINCT node_id FROM node_messages WHERE node_id != '' ORDER BY timestamp DESC"
    ) do
      {:ok, %{rows: rows}} ->
        nodes = rows |> List.flatten() |> Enum.reject(&(&1 == local_node_id()))
        Logger.debug("Discovered #{length(nodes)} nodes from Corrosion: #{inspect(nodes)}")
        {:ok, nodes}

      {:error, reason} ->
        Logger.warning("Failed to query nodes from Corrosion: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  **LOGIC CHANGE**: DNS discovery as fallback only, with better error handling
  """
  def discover_from_dns do
    app_name = Application.fetch_env!(:where_corro, :fly_app_name)

    if is_local_development?(app_name) do
      Logger.debug("Local development mode - skipping DNS discovery")
      {:ok, []}
    else
      safe_dns_lookup(app_name)
    end
  end

  @doc """
  Combined discovery: Corrosion first, DNS as fallback
  """
  def discover_all_nodes do
    case discover_from_corrosion() do
      {:ok, nodes} when length(nodes) > 0 ->
        # **LOGIC CHANGE**: If we have nodes from Corrosion, use those
        {:ok, nodes}

      {:ok, []} ->
        # **LOGIC CHANGE**: No nodes in Corrosion yet, try DNS
        Logger.info("No nodes found in Corrosion, trying DNS discovery")
        discover_from_dns()

      {:error, _reason} ->
        # **LOGIC CHANGE**: Corrosion failed, try DNS as fallback
        Logger.info("Corrosion discovery failed, trying DNS fallback")
        discover_from_dns()
    end
  end

  # Private helpers

  defp local_node_id do
    Application.fetch_env!(:where_corro, :fly_vm_id)
  end

  defp is_local_development?(app_name) do
    local_node_id() == "localhost" or
    !app_name or
    String.trim(app_name) == ""
  end

  defp safe_dns_lookup(app_name) do
    try do
      hostname = "regions.#{app_name}.internal" |> String.to_charlist()

      case :inet_res.getbyname(hostname, :txt) do
        {:ok, {_, _, _, _, _, region_list}} ->
          # **LOGIC CHANGE**: Parse regions but don't try to map to specific instances
          # Just return placeholder node IDs for now
          regions = region_list
          |> List.first()
          |> List.to_string()
          |> String.split(",")

          # Create placeholder node IDs based on regions
          nodes = regions
          |> Enum.reject(&(&1 == Application.fetch_env!(:where_corro, :fly_region)))
          |> Enum.map(&("node-#{&1}"))

          Logger.debug("DNS discovered regions #{inspect(regions)}, created placeholder nodes: #{inspect(nodes)}")
          {:ok, nodes}

        {:error, reason} ->
          Logger.warning("DNS lookup failed: #{inspect(reason)}")
          {:ok, []} # **LOGIC CHANGE**: Return empty list instead of error
      end
    rescue
      e ->
        Logger.warning("DNS lookup exception: #{inspect(e)}")
        {:ok, []} # **LOGIC CHANGE**: Return empty list instead of error
    end
  end
end
