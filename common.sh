#!/bin/bash
if [ "$INITIALIZED" != defined ]; then
  to_boolean() {
    case "$1" in
      1|true|TRUE)
        true
      ;;
      *)
        false
      ;;
    esac
  }

  if [ "$RUNNER_OS" = "Windows" ]; then
    echo "::error ::Windows isn't currently supported"
    exit 5
  fi

  now() {
    date +'%s%N'
  }
  start=$(now)
  if to_boolean ${DEBUG:+"$DEBUG"} ||
    [ "$GH_ACTION_REF" = prerelease ] &&
    [ "$GITHUB_RUN_ATTEMPT" != 1 ]; then
    set -x
  fi
  begin_group() {
    echo "::group::$1"
  }
  end_group() {
    echo '::endgroup::'
  }
  INITIALIZED=defined
fi
