#!/usr/bin/env bash

APP_NAME="${1:-}"

if ! [[ "$APP_NAME" =~ ^[a-z0-9][a-z0-9.-]*$ ]]; then
  echo "App name does not match Dokku naming regex."
  exit 1;
fi

if ! dokku apps:exists "${APP_NAME}" > /dev/null 2>&1; then
  echo "App ${APP_NAME} does not exist"
  exit 1;
fi

assert_is_review_app "$APP_NAME" || exit 1;

HELD_LOCKS=()
function cleanup(){
  if [[ ${#HELD_LOCKS[@]} -eq 0 ]]; then
    return 0;
  else
    for LOCK in "${HELD_LOCKS[@]}"; do
      release_lock "$LOCK"
    done
  fi
}

#Or something
#See here for handler code block: https://www.reddit.com/r/bash/comments/1e8plnu/comment/leddyee
function sigint_handler() {
  echo "Cleaning up..."
  cleanup;
  trap - INT
  kill -INT "$$"
}
trap sigint_handler INT
acquire_lock "$APP_NAME" || { cleanup; exit 1; }
HELD_LOCKS+=("$APP_NAME");

LINKED_DATABASES="$(dokku postgres:app-links "${APP_NAME}")"

for DATABASE in $LINKED_DATABASES; do
  if [[ "$(dokku postgres:links "$DATABASE" | wc -l)" -gt 1 ]]; then
    echo "Multiple apps linked to $DATABASE; Simply unlinking."
    dokku postgres:unlink "${DATABASE}" "${APP_NAME}" --no-restart true
  else
    dokku postgres:unlink "${DATABASE}" "${APP_NAME}" --no-restart true
    dokku postgres:destroy --force "$DATABASE"
  fi
done

LINKED_MONGOS="$(dokku mongo:app-links "${APP_NAME}")"

for MONGO in $LINKED_MONGOS; do
  if [[ "$(dokku mongo:links "$MONGO" | wc -l)" -gt 1 ]]; then
    echo "Multiple apps linked to $MONGO; Simply unlinking."
    dokku mongo:unlink "${MONGO}" "${APP_NAME}" --no-restart true
  else
    dokku mongo:unlink "${MONGO}" "${APP_NAME}" --no-restart true
    dokku mongo:destroy --force "$MONGO"
  fi
done

dokku apps:destroy --force "${APP_NAME}"
echo "$APP_NAME successfully destroyed."
cleanup;