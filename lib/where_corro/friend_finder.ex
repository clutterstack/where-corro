defmodule WhereCorro.FriendFinder do
  use GenServer
  require Logger

  def start_link(_opts \\ []) do
    GenServer.start_link(WhereCorro.FriendFinder, [])
  end

  def broadcast_regions do
    Process.send_after(self(), :broadcast_regions, 10000)
  end

  def init(_opts) do
    broadcast_regions()
    {:ok, []}
  end

  def handle_info(:broadcast_regions, state) do
    case check_regions() do
      {:ok, other_regions} ->
        #IO.inspect(IEx.Info.info(other_regions))
        Phoenix.PubSub.broadcast(WhereCorro.PubSub, "friend_regions", {:other_regions, other_regions})
        unless Application.fetch_env!(:where_corro, :corro_builtin) == "1" do
          ##Logger.info("Checking corrosion regions")
            case check_corrosion_regions() do
              {:ok, corro_regions} ->
                Phoenix.PubSub.broadcast(WhereCorro.PubSub, "corro_regions", {:corro_regions, corro_regions})
                Phoenix.PubSub.broadcast(WhereCorro.PubSub, "nearest_corrosion", {:nearest_corrosion, WhereCorro.FlyDnsReq.get_corro_instance()})
              {:error, reason} ->
                Logger.warning("Failed to check corrosion regions: #{inspect(reason)}")
            end
        end
        broadcast_regions()
      {:error, reason} ->
        Logger.info("Friend finder received an error from check_regions: #{reason}")
        broadcast_regions()
    end
    {:noreply, state}
  end

  def check_regions() do
    home_region = Application.fetch_env!(:where_corro, :fly_region)
    this_app = Application.fetch_env!(:where_corro, :fly_app_name)

    # **LOGIC CHANGE**: Validate app name before DNS lookup
    if !this_app || String.trim(this_app) == "" do
      Logger.warning("Invalid FLY_APP_NAME: #{inspect(this_app)}, skipping DNS lookup")
      {:ok, []}  # Return empty list for local development
    else
      Logger.debug("FLY_APP_NAME is #{this_app}")
      Logger.debug("fly_region is #{home_region}")

      app_regions_resolver = ":inet_res.getbyname('regions.#{this_app}.internal', :txt)"

      try do
        case Code.eval_string(app_regions_resolver) do
          {{:ok,  {_, _, _, _, _, region_list}},[]} ->
            other_regions = List.first(region_list)
            |> List.to_string()
            |> String.split(",")
            |> IO.inspect(label: "app regions")
            |> Enum.reject(& match?(^home_region, &1))
            #|> IO.inspect(label: "other regions")
            {:ok, other_regions}
          # {:ok} -> {:ok, []}
          {{:error, :nxdomain},[]} -> {:error, :nxdomain}
        end
      rescue
        e ->
          Logger.warning("DNS lookup failed for app regions: #{inspect(e)}")
          {:ok, []}  # Return empty list instead of crashing
      end
    end
  end

  def check_corrosion_regions() do
    corro_app = Application.fetch_env!(:where_corro, :fly_corrosion_app)

    # **LOGIC CHANGE**: Validate corrosion app name before DNS lookup
    if !corro_app || String.trim(corro_app) == "" do
      Logger.warning("Invalid FLY_CORROSION_APP: #{inspect(corro_app)}, skipping DNS lookup")
      {:ok, []}  # Return empty list for local development
    else
      corro_regions_resolver = ":inet_res.getbyname('regions.#{corro_app}.internal', :txt)"
      # Logger.info corro_regions_resolver

      try do
        with {{:ok,  {_, _, _, _, _, region_list}}, []} <- Code.eval_string(corro_regions_resolver) do
          #{{:ok, {:hostent, 'regions.ctestcorro.internal', [], :txt, 1, [['mad,yyz']]}}, []}
          regions = List.first(region_list)
          |> List.to_string()
          |> String.split(",")
          #|> IO.inspect(label: "corro regions")
          {:ok, regions}
        end
      rescue
        e ->
          Logger.warning("DNS lookup failed for corrosion regions: #{inspect(e)}")
          {:ok, []}  # Return empty list instead of crashing
      end
    end
  end
end
