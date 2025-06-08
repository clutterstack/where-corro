#!/bin/bash
# run_local_cluster.sh
# **LOGIC CHANGE**: New script to easily start a 3-node local cluster

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}🚀 Starting Local Corrosion Cluster${NC}"

# **LOGIC CHANGE**: Function to check if a port is ready (works without curl)
check_port_ready() {
    local host=$1
    local port=$2
    
    # Try to connect to the port using built-in tools
    if command -v nc >/dev/null 2>&1; then
        # Use netcat if available
        nc -z "$host" "$port" 2>/dev/null
    elif command -v telnet >/dev/null 2>&1; then
        # Use telnet if available
        echo "" | telnet "$host" "$port" 2>/dev/null | grep -q "Connected"
    else
        # Fallback: use /dev/tcp (bash built-in)
        exec 3<>"/dev/tcp/$host/$port" 2>/dev/null && exec 3<&- && exec 3>&-
    fi
}

# **LOGIC CHANGE**: Function to create wrapper scripts for each node
create_node_wrapper() {
    local node_name=$1
    local phoenix_port=$2
    local corro_port=$3
    
    cat > "cluster_data/$node_name/start_phoenix.sh" << 'WRAPPER_EOF'
#!/bin/bash
# Generated wrapper script for NODE_NAME

export NODE_ID="NODE_NAME"
export LOCAL_CLUSTER_MODE="true"
export CORRO_API_URL="http://127.0.0.1:CORRO_PORT/v1"
export CORRO_BUILTIN="0"
export PHX_SERVER="true"
export PORT="PHOENIX_PORT"
export FLY_VM_ID="NODE_NAME"
export FLY_REGION="local-REGION_SUFFIX"
export FLY_APP_NAME="local-cluster"
export MIX_ENV="dev"

cd "$(dirname "$0")/../.."
exec iex --name "NODE_NAME@127.0.0.1" -S mix phx.server
WRAPPER_EOF

    # **LOGIC CHANGE**: Replace placeholders with actual values
    sed -i.bak \
        -e "s/NODE_NAME/$node_name/g" \
        -e "s/PHOENIX_PORT/$phoenix_port/g" \
        -e "s/CORRO_PORT/$corro_port/g" \
        -e "s/REGION_SUFFIX/${node_name: -1}/g" \
        "cluster_data/$node_name/start_phoenix.sh"
    
    rm "cluster_data/$node_name/start_phoenix.sh.bak" 2>/dev/null || true
    chmod +x "cluster_data/$node_name/start_phoenix.sh"
}

# **LOGIC CHANGE**: Check if Corrosion binary exists
CORROSION_BIN="./corrosion/corrosion-mac"
if [ ! -f "$CORROSION_BIN" ]; then
    echo -e "${RED}❌ Corrosion binary not found at $CORROSION_BIN${NC}"
    echo -e "${YELLOW}💡 Copy your Corrosion binary to ./corrosion/corrosion${NC}"
    exit 1
fi

# **LOGIC CHANGE**: Create directories and wrapper scripts for each node
for node in node-a node-b node-c; do
    mkdir -p "cluster_data/$node"
    echo -e "${BLUE}📁 Created directory for $node${NC}"
done

echo -e "${GREEN}📄 Creating Phoenix wrapper scripts${NC}"
# **LOGIC CHANGE**: Create wrapper scripts with actual function call
create_node_wrapper "node-a" 4001 8081
create_node_wrapper "node-b" 4002 8082  
create_node_wrapper "node-c" 4003 8083

# Create Corrosion configs for each node
# Note that paths inside config.toml are relative to 
# the location of config.toml

cat > cluster_data/node-a/config.toml << EOF
[db]
path = "./corrosion.db"
schema_paths = ["../../corrosion/schemas"]

[gossip]
addr = "127.0.0.1:8787"
bootstrap = []
plaintext = true

[api]
addr = "127.0.0.1:8081"

[admin]
path = "./admin.sock"
EOF

cat > cluster_data/node-b/config.toml << EOF
[db]
path = "./corrosion.db"
schema_paths = ["../../corrosion/schemas"]

[gossip]
addr = "127.0.0.1:8788"
bootstrap = ["127.0.0.1:8787"]
plaintext = true

[api]
addr = "127.0.0.1:8082"

[admin]
path = "./admin.sock"
EOF

cat > cluster_data/node-c/config.toml << EOF
[db]
path = "./corrosion.db"
schema_paths = ["../../corrosion/schemas"]

[gossip]
addr = "127.0.0.1:8789"
bootstrap = ["127.0.0.1:8787", "127.0.0.1:8788"]
plaintext = true

[api]
addr = "127.0.0.1:8083"

[admin]
path = "./admin.sock"
EOF

echo -e "${GREEN}📄 Created Corrosion configs${NC}"

# **LOGIC CHANGE**: Function to start a single node
start_node() {
    local node_name=$1
    local phoenix_port=$2
    local corro_port=$3
    
    echo -e "${BLUE}🌟 Starting $node_name...${NC}"
    
    # **LOGIC CHANGE**: Store current directory to avoid OLDPWD issues
    local original_dir=$(pwd)
    
    # Start Corrosion in background
    cd cluster_data/$node_name
    ../../$CORROSION_BIN agent -c config.toml > corrosion.log 2>&1 &
    local corro_pid=$!
    cd "$original_dir"
    
    # **LOGIC CHANGE**: Wait for Corrosion API to be ready
    echo -e "${YELLOW}⏳ Waiting for Corrosion API on port $corro_port...${NC}"
    local attempts=0
    while ! check_port_ready "127.0.0.1" "$corro_port"; do
        sleep 1
        attempts=$((attempts + 1))
        if [ $attempts -gt 30 ]; then
            echo -e "${RED}❌ Corrosion failed to start within 30 seconds${NC}"
            echo -e "${RED}Check cluster_data/$node_name/corrosion.log for errors${NC}"
            return 1
        fi
        echo -n "."
    done
    echo -e "\n${GREEN}✅ Corrosion API ready on port $corro_port${NC}"
    
    # **LOGIC CHANGE**: Start Phoenix using the wrapper script
    echo -e "${YELLOW}🐦 Starting Phoenix for $node_name on port $phoenix_port${NC}"
    
    # **LOGIC CHANGE**: The wrapper script is executed directly as a background process
    # It contains all the environment variables and runs: iex --name node-x@127.0.0.1 -S mix phx.server
    "./cluster_data/$node_name/start_phoenix.sh" > "cluster_data/$node_name/phoenix.log" 2>&1 &
    local phoenix_pid=$!
    
    echo "$corro_pid $phoenix_pid" > "cluster_data/$node_name/pids"
    echo -e "${GREEN}✅ $node_name started (Corrosion: $corro_pid, Phoenix: $phoenix_pid)${NC}"
}

# **LOGIC CHANGE**: Start all three nodes
start_node "node-a" 4001 8081
sleep 3
start_node "node-b" 4002 8082
sleep 3  
start_node "node-c" 4003 8083

echo -e "${GREEN}🎉 Local cluster started!${NC}"
echo -e "${BLUE}🌐 Access the nodes at:${NC}"
echo -e "  • Node A: http://localhost:4001"
echo -e "  • Node B: http://localhost:4002"  
echo -e "  • Node C: http://localhost:4003"
echo ""
echo -e "${YELLOW}📋 To stop the cluster: ./stop_local_cluster.sh${NC}"
echo -e "${YELLOW}📋 To view logs: tail -f cluster_data/*/phoenix.log${NC}"
echo ""

# **LOGIC CHANGE**: Add health check
echo -e "${BLUE}🔍 Running health checks...${NC}"
sleep 5  # Give Phoenix a moment to start

for node in "node-a:4001:8081" "node-b:4002:8082" "node-c:4003:8083"; do
    IFS=':' read -r name phoenix_port corro_port <<< "$node"
    
    # Check Corrosion API
    if check_port_ready "127.0.0.1" "$corro_port"; then
        echo -e "  ✅ $name Corrosion API (port $corro_port)"
    else
        echo -e "  ❌ $name Corrosion API (port $corro_port)"
    fi
    
    # Check Phoenix
    if check_port_ready "127.0.0.1" "$phoenix_port"; then
        echo -e "  ✅ $name Phoenix (port $phoenix_port)"
    else
        echo -e "  ❌ $name Phoenix (port $phoenix_port)"
    fi
done