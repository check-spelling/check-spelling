set_up_ua() {
  export CHECK_SPELLING_VERSION="$(cat "$spellchecker/version")"
  curl_ua="check-spelling/$CHECK_SPELLING_VERSION; $(curl --version|perl -ne '$/=undef; <>; s/\n.*//;s{ }{/};s/ .*//;print')"
}

no_auth() {
  echo 'X-No-Authorization: Sorry About That'
}

curl_auth() {
  if [ -z "$no_curl_auth" ] && (
    [ "$1" == "$GITHUB_API_URL" ] ||
    [[ "$1" == "$GITHUB_API_URL"/* ]]
  ); then
    if [ -z "$AUTHORIZATION_HEADER" ]; then
      export AUTHORIZATION_HEADER=$(no_auth)
    fi
    echo "$AUTHORIZATION_HEADER"
  else
    no_auth
  fi
}

dump_curl_response() {
  cat "$response_body"
  rm -f "$response_body"
  if [ -z "$keep_headers" ]; then
    rm -f "$response_headers"
  fi
}

get_link() {
  link="$1" \
  perl -ne 'next
    unless s/^link:.*<([^>]*)>[^,]*$ENV{link}.*/$1/;
    print
  ' "$2"
}

call_curl() {
  curl_attempt=0
  response_headers="$(mktemp)"
  response_body="$(mktemp)"
  curl_output="$(mktemp)"
  curl_url="$1"
  shift
  until [ $curl_attempt -ge 3 ]
  do
    curl \
      "$curl_url" \
      -D "$response_headers" \
      -A "$curl_ua" \
      -s \
      -H "$(curl_auth "$curl_url")" \
      "$@" \
      -o "$response_body" \
      > "$curl_output"
    curl_exit_code=$?
    if [ ! -s "$response_body" ] && [ -s "$curl_output" ]; then
      mv "$curl_output" "$response_body"
    fi
    echo >> "$response_headers"
    response_code=$(perl -e '$_=<>; $_=0 unless s#^HTTP/[\d.]+ (\d+).*#$1#;print;' "$response_headers")
    if [ $response_code -eq 0 ]; then
      case $curl_exit_code in
      0)
        dump_curl_response
        response_code=200
        return
        ;;
      2)
        dump_curl_response
        (
          echo "call_curl got an exit code $curl_exit_code from curl for '$curl_url'"
        ) >&2
        return
        ;;
      3)
        dump_curl_response
        return
        ;;
      *)
        delay=0
        (
          echo "call_curl got an exit code $curl_exit_code from curl for '$curl_url' and will wait for ${delay}s before retrying:"
          cat "$response_headers"
        ) >&2
        ;;
      esac
    else
      case "$response_code" in
      301|302|307|308)
        curl_url="$(perl -ne 'next unless /^location:\s*(\S+)/i; print $1' "$response_headers")"
        delay=0
        ;;
      429|502|503)
        delay="$("$calculate_delay" "$response_headers")"
        ;;
      *)
        dump_curl_response
        return
        ;;
      esac
      (
        echo "call_curl received a $response_code and will wait for ${delay}s before retrying:"
        grep -E -i 'x-github-request-id|x-rate-limit-|retry-after' "$response_headers"
      ) >&2
    fi
    sleep "$delay"
    curl_attempt="$(( curl_attempt + 1 ))"
  done
}

set_up_ua
