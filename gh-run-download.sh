. "$spellchecker/call-curl.sh"

if [ -n "$GH_TOKEN" ]; then
  export AUTHORIZATION_HEADER="Authorization: token $GH_TOKEN"
fi

is_number() {
  [ "$1" -eq "$1" ] 2>/dev/null
}

get_comment_artifact_flavor() {
  keep_headers=1 call_curl "$GITHUB_API_URL/repositories/$GITHUB_REPOSITORY_ID/actions/runs/$RUN_ID/artifacts?name=$1&per_page=1" > "$comment_artifact_json"
  total_count=$(jq '.total_count // empty' "$comment_artifact_json")
  if [ -n "$total_count" ] && [ $total_count -gt 1 ]; then
    link=$(get_link last "$response_headers")
    call_curl "$link" > "$comment_artifact_json.2"
    id_1=$(jq -r '.artifacts[0].id // empty' "$comment_artifact_json")
    id_2=$(jq -r '.artifacts[0].id // empty' "$comment_artifact_json.2")
    if  is_number "$id_1" &&
        is_number "$id_2" &&
        [ $id_2 -gt $id_1 ]; then
      mv "$comment_artifact_json.2" "$comment_artifact_json"
    fi
  fi
}

get_artifact_url() {
  jq -r '.artifacts[0].archive_download_url // empty' "$comment_artifact_json"
}

get_comment_artifact_url() {
  comment_artifact_json=$(mktemp)
  comment=check-spelling-comment
  if [ -n "$suffix" ]; then
    get_comment_artifact_flavor "$comment-$suffix"
    artifact_url=$(get_artifact_url)
    if [ -n "$artifact_url" ]; then
      return
    fi
  fi
  get_comment_artifact_flavor "$comment"
  artifact_url=$(get_artifact_url)
}

get_comment_artifact() {
  get_comment_artifact_url
  if [ -n "$artifact_url" ]; then
    artifact_zip=$(mktemp)
    errors=$(mktemp)
    call_curl "$artifact_url" > "$artifact_zip" 2> "$errors"
    if [ $curl_exit_code = 0 ]; then
      artifact_dir=$(mktemp -d)
      unzip -q "$artifact_zip" -d "$artifact_dir" && rm "$artifact_zip"
      archive=$(find "$artifact_dir" -maxdepth 1 -mindepth 1 -type f -print0 |perl -ne 's/\0.*//;print; last')
      if [ -f "$archive" ]; then
        mv "$archive" artifact.zip
      fi
    else
      cat "$errors"
    fi
  fi
}

if [ "$GITHUB_RUN_ATTEMPT" != 1 ]; then
  set -x
fi

get_comment_artifact
