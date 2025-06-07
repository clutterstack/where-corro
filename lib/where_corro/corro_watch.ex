defmodule WhereCorro.CorroWatch do
  @moduledoc """
  Watch/subscribe to changes in the results of a given query.

  This module gets started as a child of the dynamic supervisor
  WhereCorro.WatchSupervisor. The idea is that you might want to
  start more than one copy of this for separate watch queries.
  """

  use GenServer
  require Logger

  def start_link({name, statement}) do
    GenServer.start_link(WhereCorro.CorroWatch, {name, statement})
  end

  def init({name, statement}) do
    Process.send(self(), {:start_watcher, name, statement}, [])
    {:ok, %{name: name, statement: statement, watch_id: nil}}
  end

  def handle_info({:start_watcher, name, statement}, state) do
    case start_streaming_watch(name, statement) do
      {:ok, watch_id} ->
        Logger.info("Started watch '#{name}' with ID: #{watch_id}")
        {:noreply, %{state | watch_id: watch_id}}

      {:error, reason} ->
        Logger.error("Failed to start watch '#{name}': #{inspect(reason)}")
        # Retry after a delay
        Process.send_after(self(), {:start_watcher, name, statement}, 5_000)
        {:noreply, state}
    end
  end

  defp start_streaming_watch(watch_name, statement) do
    base_url = Application.fetch_env!(:where_corro, :corro_api_url)
    url = "#{base_url}/subscriptions"

    parent_pid = self()

    # Fixed: Proper streaming function that returns {:cont, acc} or {:halt, acc}
    stream_fun = fn
      {:data, data}, acc ->
        # Send the data to our GenServer to process
        send(parent_pid, {:stream_data, data})
        {:cont, acc}

      {:status, status}, acc ->
        send(parent_pid, {:stream_status, status})
        {:cont, acc}

      {:headers, headers}, acc ->
        send(parent_pid, {:stream_headers, headers})
        {:cont, acc}

      other, acc ->
        Logger.debug("Unhandled stream event: #{inspect(other)}")
        {:cont, acc}
    end

    case Req.post(url,
           json: statement,
           connect_options: [transport_opts: [inet6: true]],
           into: stream_fun,
           receive_timeout: :infinity
         ) do
      {:ok, %Req.Response{status: 200, headers: headers}} ->
        case List.keyfind(headers, "corro-query-id", 0) do
          {"corro-query-id", watch_id} ->
            Logger.info("Started streaming watch '#{watch_name}' with ID: #{watch_id}")
            {:ok, watch_id}

          nil ->
            Logger.error("No corro-query-id header in response")
            {:error, :no_watch_id}
        end

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.error("HTTP error #{status} starting watch: #{inspect(body)}")
        {:error, {:http_error, status}}

      {:error, reason} ->
        Logger.error("Failed to start streaming watch: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Handle streaming data chunks
  def handle_info({:stream_data, data}, state) do
    if state.watch_id do
      process_streaming_data(state.name, data, state.watch_id)
    end

    {:noreply, state}
  end

  # Handle stream headers (to extract watch_id)
  def handle_info({:stream_headers, headers}, state) do
    case List.keyfind(headers, "corro-query-id", 0) do
      {"corro-query-id", watch_id} ->
        Logger.debug("Got watch ID from headers: #{watch_id}")
        {:noreply, %{state | watch_id: watch_id}}

      nil ->
        {:noreply, state}
    end
  end

  # Handle stream status
  def handle_info({:stream_status, status}, state) do
    Logger.debug("Stream status: #{status}")
    {:noreply, state}
  end

  # Handle stream completion - this might not be called with Req streaming
  def handle_info({:req_response, :done}, state) do
    Logger.info("Watch stream completed for '#{state.name}'")
    # Restart the watch after a delay
    Process.send_after(self(), {:start_watcher, state.name, state.statement}, 1_000)
    {:noreply, %{state | watch_id: nil}}
  end

  # Handle stream errors
  def handle_info({:stream_error, error}, state) do
    Logger.error("Stream error for watch '#{state.name}': #{inspect(error)}")
    # Restart the watch after a delay
    Process.send_after(self(), {:start_watcher, state.name, state.statement}, 5_000)
    {:noreply, %{state | watch_id: nil}}
  end

  defp process_streaming_data(watch_name, data, watch_id) do
    # Split by newlines and process each JSON object
    data
    |> String.split("\n", trim: true)
    |> Enum.each(fn line ->
      case Jason.decode(line) do
        {:ok, json_data} ->
          enhanced_data = Map.put(json_data, "watch_id", watch_id)
          handle_watch_event(watch_name, enhanced_data)

        {:error, reason} ->
          Logger.warning(
            "Failed to decode JSON line in stream: #{line}, error: #{inspect(reason)}"
          )
      end
    end)
  end

  defp handle_watch_event(watch_name, data) do
    case data do
      %{"eoq" => _time} ->
        Logger.debug("End of query for watch '#{watch_name}'")

      %{"columns" => columns} ->
        Logger.debug("Got column names for watch '#{watch_name}': #{inspect(columns)}")

      %{"row" => [_row_id | values]} ->
        Logger.debug("Got row data for watch '#{watch_name}': #{inspect(values)}")
        Phoenix.PubSub.broadcast(WhereCorro.PubSub, "from_corro", {watch_name, values})

      %{"change" => [change_type, _row_id, values, _change_id]} ->
        Logger.debug("Got #{change_type} change for watch '#{watch_name}': #{inspect(values)}")
        Phoenix.PubSub.broadcast(WhereCorro.PubSub, "from_corro", {watch_name, values})

      %{"error" => error_msg} ->
        Logger.error("Error in watch '#{watch_name}': #{error_msg}")

      other ->
        Logger.debug("Unhandled watch event for '#{watch_name}': #{inspect(other)}")
    end
  end
end
