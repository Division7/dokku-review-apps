#!/usr/bin/env bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

if [ -z "$SSH_ORIGINAL_COMMAND" ]; then
  echo "no command specified"
  exit 1
fi

set -f
set -- $SSH_ORIGINAL_COMMAND
set +f

set -euo pipefail

export SSH_ORIGINAL_COMMAND=""

if [ "$1" == "deploy" ]; then
  if [[ $# -ne 4 ]]; then
    echo "got $# arguments, expected 4"
    exit 1
  fi
  exec "$SCRIPT_DIR/deploy_postgres_app.sh" "$2" "$3" "$4"
  exit 0
fi

if [ "$1" == "teardown" ]; then
  if [[ $# -ne 2 ]]; then
    echo "got $# arguments, expected 2"
    exit 1
  fi
  exec "$SCRIPT_DIR/teardown_app.sh" "$2"
  exit 0
fi
