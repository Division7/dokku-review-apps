#!/usr/bin/env bash
TEMPLATE_APP_NAME="${1:-}"
REVIEW_APP_NAME="${2:-}"
DOCKER_IMAGE="${3:-}"

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
  dokku git:from-image "$REVIEW_APP_NAME" "$DOCKER_IMAGE" --build
  exit 0;
fi

if ! dokku apps:exists "$TEMPLATE_APP_NAME"; then
  echo "::error::App template to create review-apps $TEMPLATE_APP_NAME does not exist"
  exit 1
fi

#TODO: Add .locks to prevent a concurrent run from screwing with the stuff being changed
#TODO: Write a sigint handler to clean up .locks in case this is somehow being run manually
#Or something
#See here for handler code block: https://www.reddit.com/r/bash/comments/1e8plnu/comment/leddyee
function sigint_handler() {
  printf '\nCTRL+C pressed, clean up things before exiting...\n'
  # reset SIGINT handler to SIG_DFL, then resend signal to self
  trap - INT
  kill -INT "$$"
}
trap sigint_handler INT
LINKED_DATABASES=$(dokku postgres:app-links "$TEMPLATE_APP_NAME")
DB_COUNT=$(echo "$LINKED_DATABASES" | wc -l)
CLONED_DATABASES=()

if [[ -z "$LINKED_DATABASES" ]]; then
  echo "::warning::App template to create review-apps $TEMPLATE_APP_NAME does not have linked databases. Continuing..."
elif [[ "$DB_COUNT" -gt 1 ]]; then
  echo "::warning::App template to create review-apps $TEMPLATE_APP_NAME has more than one linked database. Continuing..."
  DB_COUNTER=1
  for DATABASE_NAME in $LINKED_DATABASES; do
    dokku postgres:clone "$DATABASE_NAME" "${REVIEW_APP_NAME}-db-${DB_COUNTER}"
    CLONED_DATABASES+=("${REVIEW_APP_NAME}-db-${DB_COUNTER}")
    DB_COUNTER=$((DB_COUNTER+1))
  done
else
  for DATABASE_NAME in $LINKED_DATABASES; do
    echo cloning "$DATABASE_NAME"
    dokku postgres:clone "$DATABASE_NAME" "${REVIEW_APP_NAME}-db"
    CLONED_DATABASES+=("${REVIEW_APP_NAME}-db")
  done
fi

LINKED_MONGOS=$(dokku mongo:app-links "$TEMPLATE_APP_NAME")
MONGO_COUNT=$(echo "$LINKED_MONGOS" | wc -l)
CLONED_MONGOS=()

if [[ "$MONGO_COUNT" -gt 1 ]]; then
  echo "::warning::App template to create review-apps $TEMPLATE_APP_NAME has more than one linked mongo db. Continuing..."
  MONGO_COUNTER=1
  for MONGO_NAME in $LINKED_MONGOS; do
    dokku mongo:clone "$MONGO_NAME" "${REVIEW_APP_NAME}-mongo-${MONGO_NAME}"
    CLONED_MONGOS+=("${REVIEW_APP_NAME}-mongo-${MONGO_COUNTER}")
    MONGO_COUNTER=$((MONGO_COUNTER+1))
  done
else
  for MONGO_NAME in $LINKED_MONGOS; do
    echo cloning "$MONGO_NAME"
    dokku mongo:clone "$MONGO_NAME" "${REVIEW_APP_NAME}-mongo"
    CLONED_MONGOS+=("${REVIEW_APP_NAME}-mongo")
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
