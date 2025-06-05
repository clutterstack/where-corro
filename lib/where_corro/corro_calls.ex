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
    # Only do DNS lookup in production mode
    corro_builtin = Application.fetch_env!(:where_corro, :corro_builtin)

    if corro_builtin != "1" do
      # Production mode - get instance info
      WhereCorro.FlyDnsReq.get_corro_instance()
    end

    base_url = Application.fetch_env!(:where_corro, :corro_api_url)

    case Req.post("#{base_url}/#{path}",
      json: statement,
      connect_options: [transport_opts: [inet6: true]],
      retry: :transient,
      max_retries: 3
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

  @doc """
  Parse the response body from Corrosion API.

  Corrosion returns NDJSON (newline-delimited JSON) for some responses,
  so we need to handle multiple JSON objects separated by newlines.
  """
  defp parse_corrosion_response(body, endpoint_type) do
    try do
      parsed_lines = body
      |> String.split("\n", trim: true)
      |> Enum.map(&Jason.decode!/1)

      Logger.debug("Parsed Corrosion response: #{inspect(parsed_lines)}")

      case parsed_lines do
        # Error responses
        [%{"error" => error_msg}] ->
          Logger.warning("Corrosion returned error: #{error_msg}")
          {:error, error_msg}

        [%{"results" => [%{"error" => error_msg}]}] ->
          Logger.warning("Corrosion returned error in results: #{error_msg}")
          {:error, error_msg}

        # Transaction responses
        [%{"results" => results, "time" => _total_time}] ->
          process_transaction_results(results)

        # Query responses (columns, rows, eoq)
        [%{"columns" => columns} | rest] ->
          process_query_results(columns, rest)

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
        {:error, :json_decode_error}

      exception ->
        Logger.error("Exception parsing Corrosion response: #{inspect(exception)}")
        {:error, {:parse_exception, exception}}
    end
  end

  defp process_transaction_results(results) when is_list(results) do
    total_rows_affected = results
    |> Enum.map(fn
      %{"rows_affected" => count} -> count
      _ -> 0
    end)
    |> Enum.sum()

    Logger.debug("Transaction(s) affected #{total_rows_affected} rows")
    {:ok, total_rows_affected}
  end

  defp process_query_results(columns, rest) do
    # Extract rows from the response, filtering out eoq markers
    rows = rest
    |> Enum.filter(fn item -> Map.has_key?(item, "row") end)
    |> Enum.map(fn %{"row" => [_row_id, values]} -> values end)

    {:ok, %{columns: columns, rows: rows}}
  end

  def start_watch(statement) do
    DynamicSupervisor.start_child(WhereCorro.WatchSupervisor, {WhereCorro.CorroWatch, statement})
  end
end
