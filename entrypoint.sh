#!/bin/bash
set -e

if [ -z "$REPO_URL" ]; then
  echo "No REPO_URL set — starting idle workstation"
  exec sleep infinity
fi

echo "Cloning $REPO_URL..."
git clone "$REPO_URL" /workspace/project

cd /workspace/project
echo "Installing dependencies..."
pnpm install
echo "Starting Vite..."
cd artifacts/web
exec pnpm exec vite --config vite.workspec.config.ts
