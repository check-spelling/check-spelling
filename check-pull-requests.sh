#!/bin/bash

if [ $(uname) = "Linux" ]; then
  date_to_epoch() {
    date -u -d "$1" +'%s'
  }
else
  date_to_epoch() {
    date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$1" +'%s'
  }
fi
one_hour=$(( 60 * 60 ))
strip_quotes() {
  tr '"' ' '
}
now() {
  date +'%s'
}
start=$(now)

pulls=/tmp/spelling/pulls.json
escaped=/tmp/spelling/escaped.b64
pull=/tmp/spelling/pull.json
fake_event=/tmp/spelling/fake_event.json

if [ -e "$pulls" ]; then
  echo using cached $pulls
else
  curl -s -s -H "Authorization: token $GITHUB_TOKEN" --header "Content-Type: application/json" -H "Accept: application/vnd.github.shadow-cat-preview+json" https://api.github.com/repos/check-spelling/examples-testing/pulls > $pulls
fi
cat "$pulls" | jq -c '.[]'|jq -c -r '{
 head_repo : .head.repo.full_name,
 base_repo: .base.repo.full_name,
 head_sha: .head.sha,
 base_sha: .base.sha,
 merge_commit_sha: .merge_commit_sha,
 updated_at: .updated_at,
 commits_url: .commits_url,
 comments_url: .comments_url
 } | @base64' > "$escaped"

for a in $(cat "$escaped"); do
  echo "$a" | base64 --decode | jq -r . > $pull
  updated_at=$(cat $pull | jq -r .updated_at)
  age=$(( $start - $(date_to_epoch $updated_at) ))
  if [ $age -gt $one_hour ]; then
    continue
  fi
  head_repo=$(cat $pull | jq -r .head_repo)
  base_repo=$(cat $pull | jq -r .base_repo)
  if [ "$head_repo" = "$base_repo" ]; then
    continue
  fi
  head_sha=$(cat $pull | jq -r .head_sha)
  base_sha=$(cat $pull | jq -r .base_sha)
  merge_commit_sha=$(cat $pull | jq -r .merge_commit_sha)
  comments_url=$(cat $pull | jq -r .comments_url)
  commits_url=$(cat $pull | jq -r .commits_url)
  echo "do work for $head_repo -> $base_repo: $head_sha as $merge_commit_sha"
  export GITHUB_SHA="$head_sha"
  export GITHUB_EVENT_NAME=pull_request
  echo '{}' | jq \
    --arg head_sha "$head_sha" \
    --arg base_sha "$base_sha" \
    --arg comments_url "$comments_url" \
    --arg commits_url "$commits_url" \
    -r '{pull_request: {base: {sha: $base_sha}, head: {sha: $head_sha}, comments_url: $comments_url, commits_url: $commits_url }}' \
    > "$fake_event"
  export GITHUB_EVENT_PATH="$fake_event"
  git fetch origin $merge_commit_sha
  git checkout $merge_commit_sha
  "$spellchecker/unknown-words.sh" || true
done
