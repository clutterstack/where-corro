#!/bin/bash
# Generated wrapper script for node-b

export NODE_ID="node-b"
export LOCAL_CLUSTER_MODE="true"
export CORRO_API_URL="http://127.0.0.1:8082/v1"
export CORRO_BUILTIN="0"
export PHX_SERVER="true"
export PORT="4002"
export FLY_VM_ID="node-b"
export FLY_REGION="local-b"
export FLY_APP_NAME="local-cluster"
export MIX_ENV="dev"

cd "$(dirname "$0")/../.."
exec iex --name "node-b@127.0.0.1" -S mix phx.server
