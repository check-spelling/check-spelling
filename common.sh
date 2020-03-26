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
    echo "(...$1...)"
  }
  end_group() {
    :
  }
fi

now() {
  date +'%s%N'
}
start=$(now)
temp="${temp:-/tmp/spelling}"
export temp
