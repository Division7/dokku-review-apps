#!/usr/bin/env bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

if ! command -v "dokku" &> /dev/null; then
  echo "Script at $SCRIPT_DIR is running without dokku command" | systemd-cat -t dokku-cleanup -p "warning"
  exit 1;
fi

ACTIVE_MONGO_DBS="$(dokku mongo:list | tail -n +2)"

declare -A eligible_deletions
NEWLY_ELIGIBLE_DELETIONS=()

if [ -f "/cs/student/djensen/dokku-cleanup/mongo_eligible" ]; then
  while read -r app; do
    eligible_deletions["$app"]="true"
  done < "/cs/student/djensen/dokku-cleanup/mongo_eligible"
fi

for mongo in $ACTIVE_MONGO_DBS; do
  if [ -z "$(dokku mongo:links "$mongo")" ]; then
    if [[ -v eligible_deletions["$mongo"] ]]; then
      #echo "would destroy $mongo"
      dokku mongo:destroy "$mongo" --force
    else
     NEWLY_ELIGIBLE_DELETIONS+=("$mongo")
    fi
  fi
done

NEW_ELIGIBLE_FILE="$(mktemp)"

for mongo in "${NEWLY_ELIGIBLE_DELETIONS[@]}"; do
  echo "$mongo" >> "$NEW_ELIGIBLE_FILE"
done

if ! [ -d "/cs/student/djensen/dokku-cleanup/" ]; then
  mkdir "/cs/student/djensen/dokku-cleanup/"
fi

mv "$NEW_ELIGIBLE_FILE" "/cs/student/djensen/dokku-cleanup/mongo_eligible"