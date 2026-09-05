#!/bin/bash
set -e

if [ -z "$REPO_URL" ]; then
  echo "No REPO_URL set — starting idle workstation"
  exec sleep infinity
fi

# Start workspace-agent in background before anything else.
# Serves gRPC on port 3001. File RPCs return NOT_FOUND until the clone
# completes — the platform should wait for GitStatus to succeed before
# issuing file or task calls.
WORKSPACE_ROOT=/workspace/project \
WORKSPACE_AGENT_PORT=3001 \
node /app/agent/dist/index.mjs &

# Volume at /workspace persists across machine restarts.
# Only clone + install on first boot; subsequent boots resume in place.
# git fetch is not run on resume — the platform drives sync via GitFetch RPC.
if [ -d "/workspace/project/.git" ]; then
  echo "Resuming workspace at /workspace/project"
else
  # GITHUB_TOKEN is injected at machine creation time by the WorkSpec platform
  # (GitHub App installation token). Used only for the initial clone.
  if [ -n "$GITHUB_TOKEN" ]; then
    CLONE_URL="${REPO_URL/https:\/\/github.com\//https:\/\/x-access-token:${GITHUB_TOKEN}@github.com\/}"
  else
    CLONE_URL="$REPO_URL"
  fi

  echo "Cloning $REPO_URL..."
  git clone "$CLONE_URL" /workspace/project
  cd /workspace/project
  echo "Installing dependencies..."
  pnpm install
fi

cd /workspace/project
echo "Starting Vite..."
cd artifacts/web
exec pnpm exec vite --config vite.workspec.config.ts
