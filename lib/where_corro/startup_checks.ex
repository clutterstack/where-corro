defmodule WhereCorro.StartupChecks do
  require Logger


  def do_corro_checks() do
    with {:ok, []} <- check_corro_url(),
         {:ok, []} <- check_corro_app()
    do
      {:ok, []}
    else
      _ -> {:error, {check_corro_url(), check_corro_app()}}
    end
  end

  @doc """
    Make sure there's a base url set for corrosion
  """
  def check_corro_url() do
    corro_baseurl = Application.fetch_env!(:where_corro, :corro_baseurl)
    IO.inspect(corro_baseurl, label: "corro_baseurl env")
    cond do
      corro_baseurl -> {:ok, []}
      true -> {:error, "Looks like CORRO_BASEURL isn't set"}
    end
  end

  @doc """
    If we're not using Corrosion on the same node (VM or physical host not in a VM),
    make sure there's a Corrosion Fly.io app specified
    for corrosion
  """
  def check_corro_app() do
    corro_builtin = Application.fetch_env!(:where_corro, :corro_builtin)

    if corro_builtin != "1" do
      Logger.info("I'm inside check_corro_app")
      corro_app = Application.fetch_env!(:where_corro, :fly_corrosion_app)
      cond do
        corro_app -> {:ok, []}
        true -> {:error, "Looks like FLY_CORROSION_APP isn't set"}
      end
    else
      # Builtin mode - no separate app needed
      {:ok, []}
    end
  end

end
