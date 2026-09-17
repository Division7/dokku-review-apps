#!/usr/bin/env bash

ACCOUNT_TO_LOGIN_TO="${OPKSSH_PLUGIN_U}"
SUB="${OPKSSH_PLUGIN_SUB}"
CLAIMS="${OPKSSH_PLUGIN_PAYLOAD}"
set -euo pipefail
SERVER_HOSTNAME="$(hostname | grep -oP 'dokku\-\K(\d+)')"
if [ "$ACCOUNT_TO_LOGIN_TO" != "dokkudeploy" ]; then
  echo "deny"
  exit 1
fi

if ! echo "$SUB" | grep -qE 'repo:ucsb-cs156-f26@.*/.*@.*:job_workflow_ref:ucsb-cs156/dokku-review-apps/\.github/workflows/.*@refs/heads/main'; then
  echo "deny"
  exit 1
fi

SERVER_MATCHED="$(echo "${CLAIMS}" | base64 -d | jq -r ".repository" | grep -oP '.*\-\K(\d+)')"

if [ "$SERVER_HOSTNAME" != "$SERVER_MATCHED" ]; then
  echo "deny"
  exit 1
fi

echo "allow"
exit 0