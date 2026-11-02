#!/usr/bin/env bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

if ! command -v "dokku" &> /dev/null; then
  echo "Script at $SCRIPT_DIR is running without dokku command" # | systemd-cat -t dokku-cleanup -p "warning"
  exit 1;
fi

ACTIVE_POSTGRES_DBS="$(dokku postgres:list | tail -n +2)"

declare -A eligible_deletions
NEWLY_ELIGIBLE_DELETIONS=()

if [ -f "/cs/student/djensen/dokku-cleanup/postgres_eligible" ]; then
  while read -r app; do
    eligible_deletions["$app"]="true"
  done < "/cs/student/djensen/dokku-cleanup/postgres_eligible"
fi

for db in $ACTIVE_POSTGRES_DBS; do
  if [ -z "$(dokku postgres:links "$db")" ]; then
    if [[ -v eligible_deletions["$db"] ]]; then
      #echo "would destroy $db"
      dokku postgres:destroy "$db" --force
    else
     NEWLY_ELIGIBLE_DELETIONS+=("$db")
    fi
  fi
done

NEW_ELIGIBLE_FILE="$(mktemp)"

for db in "${NEWLY_ELIGIBLE_DELETIONS[@]}"; do
  echo "$db" >> "$NEW_ELIGIBLE_FILE"
done

if ! [ -d "/cs/student/djensen/dokku-cleanup/" ]; then
  mkdir "/cs/student/djensen/dokku-cleanup/"
fi

mv "$NEW_ELIGIBLE_FILE" "/cs/student/djensen/dokku-cleanup/postgres_eligible"