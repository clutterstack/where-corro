# config/local_cluster.exs
# Configuration for running a local multi-node cluster

import Config

# Override the runtime config for local clustering
config :where_corro,
  # **LOGIC CHANGE**: Use static local configuration instead of env vars
  local_cluster_mode: true,
  local_cluster_nodes: [
    %{node_id: "node-a", port: 4001, corro_port: 8081, region: "local-1"},
    %{node_id: "node-b", port: 4002, corro_port: 8082, region: "local-2"},
    %{node_id: "node-c", port: 4003, corro_port: 8083, region: "local-3"}
  ]

# **LOGIC CHANGE**: Override discovery to use local nodes instead of DNS
config :where_corro, :discovery_mode, :local_static
