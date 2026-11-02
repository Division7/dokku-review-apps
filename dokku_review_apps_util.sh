#!/usr/bin/env bash

function acquire_lock(){
  LOCK_NAME="${1}"

  if ! [[ "$LOCK_NAME" =~ ^[a-z0-9][a-z0-9._-]*$ ]]; then
    echo "$LOCK_NAME not allowable as a dokku app"
    return 1
  fi

  if [ ! -d "/var/lock/review-apps" ]; then
    mkdir /var/lock/review-apps
    chmod -R 744 /var/lock/review-apps
  fi

  (set -o noclobber; { true > "/var/lock/review-apps/$LOCK_NAME.lock"; } &> /dev/null)
}

function release_lock(){
  LOCK_NAME="${1}"
  if ! [[ "$LOCK_NAME" =~ ^[a-z0-9][a-z0-9._-]*$ ]]; then
    echo "$LOCK_NAME not allowable as a dokku app"
    return 1
  fi

  if [ ! -d "/var/lock/review-apps" ]; then
    echo "ERROR: /var/lock/review-apps does not exist"
    return 1
  fi


  rm -f "/var/lock/review-apps/$LOCK_NAME.lock"
}

function assert_is_review_app(){
  APP_NAME="${1}"
  REVIEW_CONFIG_VALUE="$(dokku config:get "${APP_NAME}" REVIEW_MODE))"
  if [ -z "${REVIEW_CONFIG_VALUE}" ] || [ "${REVIEW_CONFIG_VALUE}" != "true" ]; then
    echo "App ${APP_NAME} does not have REVIEW_MODE=true; Will not update non-review app.";
    return 1;
  fi
  return 0;
}
