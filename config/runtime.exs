# config/runtime.exs
# **LOGIC CHANGES** for local cluster support

import Config
require Logger

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.

if System.get_env("PHX_SERVER") do
  config :where_corro, WhereCorroWeb.Endpoint, server: true
end

Logger.info("configuring where_corro app vars in runtime.exs")

# **LOGIC CHANGE**: Check for local cluster mode first
local_cluster_mode = System.get_env("LOCAL_CLUSTER_MODE") == "true"

cond do
  # **LOGIC CHANGE**: Local cluster mode - use explicit CORRO_API_URL
  local_cluster_mode ->
    Logger.info("🏠 Configuring for local cluster mode")

    config :where_corro,
      local_cluster_mode: true,
      fly_corrosion_app: "local-cluster",
      corro_api_url: System.get_env("CORRO_API_URL"),
      corro_builtin: "0"

    # **LOGIC CHANGE**: Set up local cluster nodes config
    config :where_corro,
      local_cluster_nodes: [
        %{node_id: "node-a", port: 4001, corro_port: 8081, region: "local-1"},
        %{node_id: "node-b", port: 4002, corro_port: 8082, region: "local-2"},
        %{node_id: "node-c", port: 4003, corro_port: 8083, region: "local-3"}
      ]

  # **LOGIC CHANGE**: Builtin Corrosion (single process)
  System.get_env("CORRO_BUILTIN") == "1" ->
    Logger.info("🔧 Configuring for builtin Corrosion mode")

    config :where_corro,
      fly_corrosion_app: System.get_env("FLY_APP_NAME"),
      corro_api_url: System.get_env("CORRO_API_URL"),
      corro_builtin: "1"

  # **LOGIC CHANGE**: Separate Corrosion app (production)
  true ->
    Logger.info("☁️  Configuring for separate Corrosion app mode")

    corrosion_app = System.get_env("FLY_CORROSION_APP")

    config :where_corro,
      fly_corrosion_app: corrosion_app,
      corro_api_url: "http://top1.nearest.of.#{corrosion_app}.internal:8080/v1",
      corro_builtin: "0"
end

# **LOGIC CHANGE**: Common configuration that applies to all modes
config :where_corro,
  fly_region: System.get_env("FLY_REGION"),
  fly_vm_id: System.get_env("FLY_VM_ID"),
  fly_app_name: System.get_env("FLY_APP_NAME"),
  fly_private_ip: System.get_env("FLY_PRIVATE_IP")

if config_env() == :prod do
  Logger.info("Configuring prod env")

  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || System.get_env("FLY_APP_NAME") <> ".fly.dev"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :where_corro, WhereCorroWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base
end
