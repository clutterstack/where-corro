#!/bin/bash
# Generated wrapper script for node-a

export NODE_ID="node-a"
export LOCAL_CLUSTER_MODE="true"
export CORRO_API_URL="http://127.0.0.1:8081/v1"
export CORRO_BUILTIN="0"
export PHX_SERVER="true"
export PORT="4001"
export FLY_VM_ID="node-a"
export FLY_REGION="local-a"
export FLY_APP_NAME="local-cluster"
export MIX_ENV="dev"

cd "$(dirname "$0")/../.."
exec iex --name "node-a@127.0.0.1" -S mix phx.server
