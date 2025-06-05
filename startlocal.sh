#!/bin/bash

this_fly_app="where-corro"
# For local development, we still need to set this even though we won't use it
fly_corrosion_app="where-corro"  # This is only used when Corrosion isn't on localhost; value doesn't matter otherwise

export \
CORRO_BUILTIN="1" \
CORRO_API_URL="http://localhost:8081/v1" \
FLY_CORROSION_APP="$fly_corrosion_app" \
PHX_HOST="$this_fly_app.fly.dev" \
FLY_APP_NAME="$this_fly_app" \
FLY_MACHINE_ID="localhost" \
FLY_REGION="💻" \
FLY_PRIVATE_IP="localhost"

env | grep -i corro
echo FLY_APP_NAME=$FLY_APP_NAME
echo FLY_MACHINE_ID=$FLY_MACHINE_ID

iex -S mix phx.server