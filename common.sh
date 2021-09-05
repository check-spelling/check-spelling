#!/bin/bash
if [ "$DEBUG" != defined ]; then
  GITHUB_TOKEN=${GITHUB_TOKEN:-$INPUT_GITHUB_TOKEN}
  if [ -n "$GITHUB_TOKEN" ]; then
    export AUTHORIZATION_HEADER="Authorization: token $GITHUB_TOKEN"
  else
    export AUTHORIZATION_HEADER='X-No-Authorization: Sorry About That'
  fi
  "$spellchecker/secpoll.sh"

  if [ "$RUNNER_OS" = "Windows" ]; then
    echo "::error ::Windows isn't currently supported"
    exit 5
  fi

  now() {
    date +'%s%N'
  }
  start=$(now)
  temp="${temp:-/tmp/spelling}"
  mkdir -p $temp
  export temp
  if [ -n "$DEBUG" ]; then
    set -x
    begin_group() {
      echo "::group::$1"
    }
    end_group() {
      echo '::end_group::'
    }
  else
    begin_group() {
      echo "(...$1...)"
    }
    end_group() {
      :
    }
    DEBUG=defined
  fi
fi
