defmodule WhereCorro.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Start the Telemetry supervisor
      # DON'T actually, until can figure out how Corrosion and Elixir can both do metrics
      # WhereCorroWeb.Telemetry,
      # Start the PubSub system
      {Phoenix.PubSub, name: WhereCorro.PubSub},
      # Start Finch
      {Finch, name: WhereCorro.Finch,
        pools: %{
            default: [conn_opts: [transport_opts: [inet6: true]]]
        }},
      # Start the Endpoint (http/https)
      {DynamicSupervisor, name: WhereCorro.WatchSupervisor, strategy: :one_for_one},
      {Task.Supervisor, name: WhereCorro.TaskSupervisor},
      # Start a worker by calling: WhereCorro.Worker.start_link(arg)
      # {WhereCorro.Worker, arg}
      #WhereCorro.CorroPort,
      WhereCorro.GenSandwich,
      WhereCorroWeb.Endpoint,
      WhereCorro.SandwichSender,
      WhereCorro.Discoverer,
      WhereCorro.FriendFinder
      # WhereCorro.CheckCorro
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: WhereCorro.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    WhereCorroWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
