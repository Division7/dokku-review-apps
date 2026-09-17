#!/usr/bin/env bash

set -euo pipefail

if [ "$1" == "deploy" ]; then
  if [[ $# -ne 5 ]]; then
    echo "got $# arguments, expected 5"
    exit 1
  fi
  ssh dokkudeploy@"dokku-${5}.cs.ucsb.edu" "./handle_deploy_actions_dokku.sh deploy" "${2}" "${3}" "${4}"
  exit 0
fi

if [ "$1" == "teardown" ]; then
  if [[ $# -ne 3 ]]; then
    echo "got $# arguments, expected 3"
    exit 1
  fi
  ssh dokkudeploy@"dokku-${3}.cs.ucsb.edu" "./handle_deploy_actions_dokku.sh teardown" "${2}"
  exit 0
fi
