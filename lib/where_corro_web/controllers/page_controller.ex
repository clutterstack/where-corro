defmodule WhereCorroWeb.PageController do
  use WhereCorroWeb, :controller
  require Logger

  def sandwich(conn, _params) do
    render(conn, :sandwich, sandwich: "default")
  end
end
