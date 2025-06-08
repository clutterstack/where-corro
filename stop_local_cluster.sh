#!/bin/bash
# stop_local_cluster.sh
# **LOGIC CHANGE**: Script to cleanly stop all cluster nodes

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}🛑 Stopping Local Corrosion Cluster${NC}"

# **LOGIC CHANGE**: Stop each node by reading saved PIDs
for node in node-a node-b node-c; do
    pid_file="cluster_data/$node/pids"
    
    if [ -f "$pid_file" ]; then
        pids=$(cat "$pid_file")
        echo -e "${GREEN}🔄 Stopping $node (PIDs: $pids)${NC}"
        
        for pid in $pids; do
            if kill -0 "$pid" 2>/dev/null; then
                kill "$pid"
                echo "  Killed process $pid"
            else
                echo "  Process $pid already stopped"
            fi
        done
        
        rm "$pid_file"
    else
        echo -e "${RED}⚠️  No PID file found for $node${NC}"
    fi
done

# **LOGIC CHANGE**: Clean up any remaining processes
echo -e "${GREEN}🧹 Cleaning up any remaining processes...${NC}"
pkill -f "corrosion agent" || true
pkill -f "mix phx.server" || true

echo -e "${GREEN}✅ Local cluster stopped${NC}"