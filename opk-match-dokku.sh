#!/usr/bin/env bash

ACCOUNT_TO_LOGIN_TO="${OPKSSH_PLUGIN_U}"
SUB="${OPKSSH_PLUGIN_SUB}"
CLAIMS="${OPKSSH_PLUGIN_PAYLOAD}"
set -euo pipefail
AVAILABLE_GITHUB_ORGS="$(< /home/eci/dokku_github_orgs_list)"
SERVER_HOSTNAME="$(hostname | grep -oP 'dokku\-\K(\d+)')"
VALIDATED_GITHUB_ORGS=()
for line in $AVAILABLE_GITHUB_ORGS; do
  if ! [[ "$line" =~ ^[a-Z0-9-]*$ ]]; then
    echo "illegal organization $line listed in /home/eci/dokku_github_orgs_list" | systemd-cat -t opk-match-dokku -p warning
  else
    VALIDATED_GITHUB_ORGS+=("$line")
  fi
done

ALLOWED_GITHUB_ORGS_MATCHER="$(IFS='|'; echo "${VALIDATED_GITHUB_ORGS[*]}")"

if [ "$ACCOUNT_TO_LOGIN_TO" != "dokkudeploy" ]; then
  echo "login attempt to ${ACCOUNT_TO_LOGIN_TO}; denied" | systemd-cat -t opk-match-dokku -p info
  echo "deny"
  exit 1
fi

if ! echo "$SUB" | grep -qE "^repo:($ALLOWED_GITHUB_ORGS_MATCHER)@.*/.*@.*:job_workflow_ref:ucsb-cs156/dokku-review-apps/\.github/workflows/.*@refs/heads/main$"; then
  echo "sub $SUB not matching approved regex attempted login; denied" | systemd-cat -t opk-match-dokku -p info
  echo "deny"
  exit 1
fi

REPOSITORY_NAME="$(echo "${CLAIMS}" | base64 -d | jq -r ".repository")"
SERVER_MATCHED="$(echo -n "$REPOSITORY_NAME" | grep -oP '.*\-\K(\d+)')"

if [ -z "$SERVER_MATCHED" ]; then
  echo "Unable to match dokku server for $REPOSITORY_NAME" | systemd-cat -t opk-match-dokku -p warning
  echo "deny"
  exit 1
fi

if [ "$SERVER_HOSTNAME" != "$SERVER_MATCHED" ]; then
  echo "Server dokku-$SERVER_HOSTNAME requested rather than dokku-$SERVER_MATCHED; denied" | systemd-cat -t opk-match-dokku -p info
  echo "deny"
  exit 1
fi

echo "allow"
exit 0