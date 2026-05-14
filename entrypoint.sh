#!/bin/bash
set -e

if [ -z "$REPO_URL" ]; then
  echo "No REPO_URL set — starting idle workstation"
  exec sleep infinity
fi

echo "Cloning $REPO_URL..."
git clone "$REPO_URL" /workspace/project

cd /workspace/project
echo "Running aspire restore..."
aspire restore
echo "Running aspire run..."
exec env \
  WORKSPEC=true \
  ASPNETCORE_URLS="http://localhost:17300" \
  ASPIRE_DASHBOARD_OTLP_HTTP_ENDPOINT_URL="http://localhost:18901" \
  ASPIRE_ALLOW_UNSECURED_TRANSPORT="true" \
  aspire run
