#!/bin/bash
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
    :
  }
  end_group() {
    :
  }
fi

now() {
  date +'%s%N'
}
start=$(now)
export temp='/tmp/spelling'
