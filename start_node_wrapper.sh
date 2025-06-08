#!/bin/bash
# start_node_wrapper.sh
# **LOGIC CHANGE**: Create individual wrapper scripts to ensure environment is set correctly

create_node_wrapper() {
    local node_name=$1
    local phoenix_port=$2
    local corro_port=$3
    
    cat > "cluster_data/$node_name/start_phoenix.sh" << EOF
#!/bin/bash
# Generated wrapper script for $node_name

# **LOGIC CHANGE**: Set environment variables in the script itself
export NODE_ID="$node_name"
export LOCAL_CLUSTER_MODE="true"
export CORRO_API_URL="http://127.0.0.1:${corro_port}/v1"
export CORRO_BUILTIN="0"
export PHX_SERVER="true"
export PORT="$phoenix_port"
export FLY_VM_ID="$node_name"
export FLY_REGION="local-${node_name: -1}"
export FLY_APP_NAME="local-cluster"
export MIX_ENV="dev"

# **LOGIC CHANGE**: Change to project root before starting
cd "\$(dirname "\$0")/../.."

# **LOGIC CHANGE**: Start Phoenix with proper node name
exec iex --name "$node_name@127.0.0.1" -S mix phx.server
EOF

    chmod +x "cluster_data/$node_name/start_phoenix.sh"
}