defmodule WhereCorroWeb.PageController do
  use WhereCorroWeb, :controller
  require Logger

  def sandwich(conn, _params) do
    inspect(WhereCorro.GenSandwich.get_sandwich()) |> Logger.info()
    with sandwich <- WhereCorro.GenSandwich.get_sandwich() do

      render(conn, :sandwich, sandwich: sandwich)
    else
      _ -> render(conn, :sandwich, sandwich: "default")
    end
  end

end
