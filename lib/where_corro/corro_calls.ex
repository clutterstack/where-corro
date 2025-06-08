defmodule WhereCorro.CorroCalls do
  require Logger

  @doc """
  Make a request to the Corrosion API

  ## Examples
      iex> WhereCorro.CorroCalls.corro_request("queries", "SELECT foo FROM tests")
      {:ok, %{columns: ["foo"], rows: [["bar"]]}}

      iex> WhereCorro.CorroCalls.execute_corro(["INSERT INTO tests VALUES (1, 'test')"])
      {:ok, 1}
  """
  def corro_request(path, statement) do
    # **LOGIC CHANGE**: Only do DNS lookup in production mode AND with valid app name
    corro_builtin = Application.fetch_env!(:where_corro, :corro_builtin)

    if corro_builtin != "1" do
      # Production mode - get instance info, but safely
      try do
        fly_corrosion_app = Application.fetch_env!(:where_corro, :fly_corrosion_app)

        # Only attempt DNS lookup if we have a valid app name
        if fly_corrosion_app && String.trim(fly_corrosion_app) != "" do
          WhereCorro.FlyDnsReq.get_corro_instance()
        else
          Logger.warning("No valid FLY_CORROSION_APP set, skipping DNS lookup")
        end
      rescue
        e ->
          Logger.warning("DNS lookup failed safely: #{inspect(e)}")
          # Continue anyway - the base_url should still work
      end
    end

    base_url = Application.fetch_env!(:where_corro, :corro_api_url)

    # **LOGIC CHANGE**: Force Req to return raw body by disabling auto-JSON parsing
    case Req.post("#{base_url}/#{path}",
           json: statement,
           connect_options: [transport_opts: [inet6: true]],
           retry: :transient,
           max_retries: 3,
           # **NEW**: Prevent automatic JSON decoding
           decode_body: false
         ) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        parse_corrosion_response(body, path)

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.error("Corrosion HTTP error #{status}: #{inspect(body)}")
        {:error, {:http_error, status, body}}

      {:error, %Req.TransportError{reason: reason}} ->
        Logger.error("Network error connecting to Corrosion: #{inspect(reason)}")
        {:error, :network_error}

      {:error, reason} ->
        Logger.error("Unexpected error from Corrosion: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def execute_corro(transactions) do
    corro_request("transactions", transactions)
  end

  def query_corro(statement) do
    corro_request("queries", statement)
  end

  # Parse the response body from Corrosion API.

  defp parse_corrosion_response(body, endpoint_type) do
    try do
      # Split by newlines and decode each JSON object, just like the old version
      bodylist =
        body
        |> String.split("\n", trim: true)
        |> Enum.map(&Jason.decode!/1)

      Logger.debug("Parsed Corrosion response: #{inspect(bodylist)}")

      case bodylist do
        # Error responses
        [%{"results" => [%{"error" => error_msg}]}] ->
          Logger.warning("Corrosion returned error in results: #{error_msg}")
          {:error, error_msg}

        [%{"error" => error_msg}] ->
          Logger.warning("Corrosion returned error: #{error_msg}")
          {:error, error_msg}

        # Transaction responses - matches old pattern exactly
        [
          %{
            "results" => [%{"rows_affected" => rows_affected, "time" => _time1}],
            "time" => _time2
          }
        ] ->
          Logger.debug("Transaction affected #{rows_affected} rows")
          {:ok, rows_affected}

        # **LOGIC CHANGE**: Handle multiple transaction results
        [%{"results" => results, "time" => _total_time}] when is_list(results) ->
          total_rows_affected =
            results
            |> Enum.map(fn
              %{"rows_affected" => count} -> count
              _ -> 0
            end)
            |> Enum.sum()

          Logger.debug("Transaction(s) affected #{total_rows_affected} rows")
          {:ok, total_rows_affected}

        # Query responses - columns followed by rows and eoq
        [%{"columns" => columns} | rest] ->
          rows =
            rest
            |> Enum.filter(fn item -> Map.has_key?(item, "row") end)
            |> Enum.map(fn %{"row" => [_row_id, values]} -> values end)

          {:ok, %{columns: columns, rows: rows}}

        # Empty response
        [] ->
          Logger.warning("Empty response from Corrosion")
          {:error, :empty_response}

        # Unexpected format
        other ->
          Logger.warning("Unexpected response format: #{inspect(other)}")
          {:error, {:unexpected_format, other}}
      end
    rescue
      e in Jason.DecodeError ->
        Logger.error("Failed to decode JSON from Corrosion: #{inspect(e)}")
        Logger.error("Raw body was: #{inspect(body)}")
        {:error, :json_decode_error}

      exception ->
        Logger.error("Exception parsing Corrosion response: #{inspect(exception)}")
        Logger.error("Raw body was: #{inspect(body)}")
        {:error, {:parse_exception, exception}}
    end
  end

  def start_watch(statement) do
    DynamicSupervisor.start_child(WhereCorro.WatchSupervisor, {WhereCorro.CorroWatch, statement})
  end
end
