import Config
require Logger

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/where_corro start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :where_corro, WhereCorroWeb.Endpoint, server: true
end

Logger.info("configuring where_corro app vars in runtime.exs")

if System.get_env("CORRO_BUILTIN") == "1" do
  config :where_corro,
    fly_corrosion_app: System.get_env("FLY_APP_NAME"),
    corro_api_url: System.get_env("CORRO_API_URL")
else
  config :where_corro,
    fly_corrosion_app: System.get_env("FLY_CORROSION_APP"),
    corro_api_url: "http://top1.nearest.of.#{System.get_env("FLY_CORROSION_APP")}.internal:8080"
end

config :where_corro,
  corro_builtin: System.get_env("CORRO_BUILTIN"),
  fly_region: System.get_env("FLY_REGION"),
  fly_vm_id: System.get_env("FLY_MACHINE_ID"),
  fly_app_name: System.get_env("FLY_APP_NAME"),
  fly_private_ip: System.get_env("FLY_PRIVATE_IP")

if config_env() == :prod do
  Logger.info("Configuring prod env")
  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
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
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/plug_cowboy/Plug.Cowboy.html
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base
end
