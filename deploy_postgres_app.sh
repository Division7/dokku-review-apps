#!/usr/bin/env bash
TEMPLATE_APP_NAME="${1:?TEMPLATE_APP_NAME is required}"
REVIEW_APP_NAME="${2:?REVIEW_APP_NAME is required}"
DOCKER_IMAGE="${3:?DOCKER_IMAGE is required}"

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

source "$SCRIPT_DIR/dokku_review_apps_util.sh"

#See old CVE fix:
# https://github.com/dokku/dokku/pull/8590/changes#diff-91e36959c988951c6ce56b86ce7634c08541925a5e55f83e937024af33d4ed88R926
if ! [[ "$TEMPLATE_APP_NAME" =~ ^[a-z0-9][a-z0-9.-]*$ ]]; then
  echo "Template app name does not match Dokku naming regex."
  exit 1;
fi

if ! [[ "$REVIEW_APP_NAME" =~ ^[a-z0-9][a-z0-9.-]*$ ]]; then
  echo "Review app name does not match Dokku naming regex."
  exit 1;
fi

if dokku apps:exists "$REVIEW_APP_NAME"; then
  assert_is_review_app "$REVIEW_APP_NAME" || exit 1;
  dokku git:from-image "$REVIEW_APP_NAME" "$DOCKER_IMAGE" --build
  exit 0;
fi

if ! dokku apps:exists "$TEMPLATE_APP_NAME"; then
  echo "::error::App template to create review-apps $TEMPLATE_APP_NAME does not exist"
  exit 1
fi

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


#TODO: Add .locks to prevent a concurrent run from screwing with the stuff being changed
#TODO: Write a sigint handler to clean up .locks in case this is somehow being run manually
#Or something
#See here for handler code block: https://www.reddit.com/r/bash/comments/1e8plnu/comment/leddyee
function sigint_handler() {
  echo "Cleaning up..."
  cleanup;
  trap - INT
  kill -INT "$$"
}
trap sigint_handler INT
acquire_lock "$REVIEW_APP_NAME" || { cleanup; exit 1; }
HELD_LOCKS+=("$REVIEW_APP_NAME");
LINKED_DATABASES=$(dokku postgres:app-links "$TEMPLATE_APP_NAME")
DB_COUNT=$(echo "$LINKED_DATABASES" | wc -l)
CLONED_DATABASES=()

if [[ -z "$LINKED_DATABASES" ]]; then
  echo "::warning::App template to create review-apps $TEMPLATE_APP_NAME does not have linked databases. Continuing..."
elif [[ "$DB_COUNT" -gt 1 ]]; then
  echo "::warning::App template to create review-apps $TEMPLATE_APP_NAME has more than one linked database. Continuing..."
  DB_COUNTER=1
  for DATABASE_NAME in $LINKED_DATABASES; do
    CLONED_DB_NAME="${REVIEW_APP_NAME}-db-${DB_COUNTER}"
    acquire_lock "$CLONED_DB_NAME" || { cleanup; exit 1; }
    HELD_LOCKS+=("$CLONED_DB_NAME")
    dokku postgres:clone "$DATABASE_NAME" "$CLONED_DB_NAME"
    CLONED_DATABASES+=("$CLONED_DB_NAME")
    DB_COUNTER=$((DB_COUNTER+1))
  done
else
  for DATABASE_NAME in $LINKED_DATABASES; do
    echo cloning "$DATABASE_NAME"
    CLONED_DB_NAME="${REVIEW_APP_NAME}-db"
    acquire_lock "$CLONED_DB_NAME" || { cleanup; exit 1; }
    HELD_LOCKS+=("$CLONED_DB_NAME")
    dokku postgres:clone "$DATABASE_NAME" "$CLONED_DB_NAME"
    CLONED_DATABASES+=("$CLONED_DB_NAME")
  done
fi

LINKED_MONGOS=$(dokku mongo:app-links "$TEMPLATE_APP_NAME")
MONGO_COUNT=$(echo "$LINKED_MONGOS" | wc -l)
CLONED_MONGOS=()

if [[ "$MONGO_COUNT" -gt 1 ]]; then
  echo "::warning::App template to create review-apps $TEMPLATE_APP_NAME has more than one linked mongo db. Continuing..."
  MONGO_COUNTER=1
  for MONGO_NAME in $LINKED_MONGOS; do
    CLONED_MONGO_NAME="${REVIEW_APP_NAME}-mongo-${MONGO_NAME}"
    acquire_lock "$CLONED_MONGO_NAME" || { cleanup; exit 1; }
    HELD_LOCKS+=("$CLONED_MONGO_NAME")
    dokku mongo:clone "$MONGO_NAME" "$CLONED_MONGO_NAME"
    CLONED_MONGOS+=("$CLONED_MONGO_NAME")
    MONGO_COUNTER=$((MONGO_COUNTER+1))
  done
else
  for MONGO_NAME in $LINKED_MONGOS; do
    echo cloning "$MONGO_NAME"
    CLONED_MONGO_NAME="${REVIEW_APP_NAME}-mongo"
    acquire_lock "$CLONED_MONGO_NAME" || { cleanup; exit 1; }
    HELD_LOCKS+=("$CLONED_MONGO_NAME")
    dokku mongo:clone "$MONGO_NAME" "$CLONED_MONGO_NAME"
    CLONED_MONGOS+=("$CLONED_MONGO_NAME")
  done
fi


dokku apps:clone "$TEMPLATE_APP_NAME" "$REVIEW_APP_NAME" --skip-deploy
for DATABASE_NAME in $LINKED_DATABASES; do
  dokku postgres:unlink "$DATABASE_NAME" "$REVIEW_APP_NAME" --no-restart true
done

for DATABASE_NAME in "${CLONED_DATABASES[@]}"; do
  dokku postgres:link "$DATABASE_NAME" "$REVIEW_APP_NAME" --no-restart true
done

for MONGO_NAME in "${CLONED_MONGOS[@]}"; do
  dokku mongo:link "$MONGO_NAME" "$REVIEW_APP_NAME" --no-restart true
done

dokku config:set "$REVIEW_APP_NAME" REVIEW_MODE=true

dokku git:from-image "$REVIEW_APP_NAME" "$DOCKER_IMAGE" --build

dokku letsencrypt:set "$REVIEW_APP_NAME" email djensen@ucsb.edu
dokku letsencrypt:enable "$REVIEW_APP_NAME"

cleanup