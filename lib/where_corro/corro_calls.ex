defmodule WhereCorro.CorroCalls do
  require Logger

  # e.g. WhereCorro.CorroCalls.corro_request("query","SELECT foo FROM TESTS")
  def corro_request(path, statement) do
    # Only do DNS lookup in production mode
    corro_builtin = Application.fetch_env!(:where_corro, :corro_builtin)

    if corro_builtin != "1" do
      # Production mode - get instance info
      WhereCorro.FlyDnsReq.get_corro_instance()
    end

    corro_db_url = "#{Application.fetch_env!(:where_corro, :corro_baseurl)}/v1/"

    with {:ok, %Finch.Response{status: status_code, body: body, headers: headers}} <-
           Finch.build(:post, "#{corro_db_url}#{path}", [{"content-type", "application/json"}], Jason.encode!(statement))
           |> Finch.request(WhereCorro.Finch) do
      extract_results(%{status: status_code, body: body, headers: headers})
    else
      {:ok, response} ->
        IO.inspect(response, label: "Got an unexpected response in query_corro")
      {:error, resp} ->
        {:error, resp}
      another_response ->
        inspect(another_response) |> IO.inspect(label: "corro_request: response has an unexpected format")
    end
  end

  def execute_corro(transactions) do
    corro_request("transactions", transactions)
  end

  def query_corro(statement) do
    corro_request("queries", statement)
  end

  @doc """
  This function gets a map from corro_request/2 with status
  """
  defp extract_results(response=%{status: status_code, body: body, headers: headers}) do
    # Sometimes the body is a string that makes a single JSON thing you can decode.
    # Sometimes it's more than one, separated by \n.
    # Split it just in case, decode the pieces, and send things on
    # to an appropriate function for processing
    bodylist = body |> String.split("\n", trim: true)
    # |> IO.inspect(label: "Before splitting body string")
    |> Enum.map(fn x -> Jason.decode!(x, []) end)
    IO.inspect(bodylist, label: "Split and decoded body")
    case bodylist do
      [%{"results" => [%{"error" => errormsg}]}] -> Logger.info("error in extract_results: #{errormsg}")
        {:error, errormsg}
        # I'm not sure if we still get a "results" list ever anymore
      [%{"error" => errormsg}] ->  Logger.info("error in extract_results: #{errormsg}")
        {:error, errormsg}
      [%{"columns" => col_list}, %{} | tail] -> Logger.info("looks like a queries endpoint response")
        process_query_results(%{status: status_code, bodylist: bodylist, headers: headers})

      # The following is what we expect from a transaction.
      [%{"results" => [%{"rows_affected" => _rows_affected, "time" => _time1}], "time" => _time2}] ->
        # Logger.info("extract_results got transaction results")
        process_transaction_results(%{status: status_code, bodylist: bodylist, headers: headers})
      [%{}, %{} | the_rest] -> Logger.info("there was more than one map in there but I didn't plan for this response")
        {:unexpected_response, bodylist}
      _ -> Logger.info("extract_results extracted an unexpected body")

    end

    # with {:ok, %{"results" => [resultsmap],"time" => _time}} <- Jason.decode(body) do
    #   # inspect(resultsmap) |> IO.inspect(label: "*** in corrosion calls. resultsmap")
    #   {:ok, resultsmap}
    # end
  end

  def process_query_results(%{status: status_code, bodylist: bodylist, headers: headers}) do
    # with [%{"columns" => col_list} | tail] <- bodylist do


    #   IO.inspect(middle, label: "middle list items in process_query results")
    # end
  end

  def process_transaction_results(%{status: status_code, bodylist: bodylist, headers: headers}) do
    with [%{"results" => [%{"rows_affected" => rows_affected, "time" => _time1}], "time" => _time2}] <- bodylist do
      Logger.info("transaction affected #{rows_affected} rows")
      {:ok, rows_affected}
    end
  end

  def start_watch(statement) do
    DynamicSupervisor.start_child(WhereCorro.WatchSupervisor, {WhereCorro.CorroWatch,statement})
  end

end
