#!/bin/bash
# Generated wrapper script for node-c

export NODE_ID="node-c"
export LOCAL_CLUSTER_MODE="true"
export CORRO_API_URL="http://127.0.0.1:8083/v1"
export CORRO_BUILTIN="0"
export PHX_SERVER="true"
export PORT="4003"
export FLY_VM_ID="node-c"
export FLY_REGION="local-c"
export FLY_APP_NAME="local-cluster"
export MIX_ENV="dev"

cd "$(dirname "$0")/../.."
exec iex --name "node-c@127.0.0.1" -S mix phx.server
