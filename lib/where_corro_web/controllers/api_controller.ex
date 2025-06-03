defmodule WhereCorroWeb.APIController do
  use WhereCorroWeb, :controller

  def show(conn, _params) do
    inspect(WhereCorro.GenSandwich.get_sandwich()) |> IO.puts()
    with sandwich <- WhereCorro.GenSandwich.get_sandwich() do
      json(conn, %{status: "good", sandwich: sandwich})
    else
      _ -> json(conn, %{status: "bad", sandwich: "none"})
    end
  end

end
