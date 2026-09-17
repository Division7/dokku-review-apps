#!/usr/bin/env bash
TEMPLATE_APP_NAME=$1
REVIEW_APP_NAME=$2
DOCKER_IMAGE=$3
if dokku apps:exists "$REVIEW_APP_NAME"; then
  dokku git:from-image "$REVIEW_APP_NAME" "$DOCKER_IMAGE" --build
  exit 0;
fi

if ! dokku apps:exists "$TEMPLATE_APP_NAME"; then
  echo "::error::ERROR: App template to create review-apps $TEMPLATE_APP_NAME does not exist"
  exit 1
fi

LINKED_DATABASES=$(dokku postgres:app-links "$TEMPLATE_APP_NAME")
DB_COUNT=$(echo "$LINKED_DATABASES" | wc -l)
CLONED_DATABASES=()

if [[ -z "$LINKED_DATABASES" ]]; then
  echo "::warning::warning: App template to create review-apps $TEMPLATE_APP_NAME does not have linked databases. Continuing..."
elif [[ "$DB_COUNT" -gt 1 ]]; then
  echo "::warning::warning: App template to create review-apps $TEMPLATE_APP_NAME has more than one linked database. Continuing..."
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

dokku apps:clone "$TEMPLATE_APP_NAME" "$REVIEW_APP_NAME" --skip-deploy
for DATABASE_NAME in $LINKED_DATABASES; do
  dokku postgres:unlink "$DATABASE_NAME" "$REVIEW_APP_NAME" --no-restart true
done

for DATABASE_NAME in "${CLONED_DATABASES[@]}"; do
  dokku postgres:link "$DATABASE_NAME" "$REVIEW_APP_NAME" --no-restart true
done

dokku git:from-image "$REVIEW_APP_NAME" "$DOCKER_IMAGE" --build

dokku letsencrypt:set "$REVIEW_APP_NAME" email djensen@ucsb.edu
dokku letsencrypt:enable "$REVIEW_APP_NAME"
