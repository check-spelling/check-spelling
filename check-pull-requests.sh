#!/bin/bash

. "$spellchecker/common.sh"
if [ $(uname) = "Linux" ]; then
  date_to_epoch() {
    date -u -d "$1" +'%s'
  }
else
  date_to_epoch() {
    date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$1" +'%s'
  }
fi
timeframe=${timeframe:-60}
time_limit=$(( $timeframe * 60 ))
strip_quotes() {
  tr '"' ' '
}

begin_group 'Retrieving open pull requests'
pulls=$temp/pulls.json
escaped=$temp/escaped.b64
pull=$temp/pull.json
fake_event=$temp/fake_event.json
tree_config="$bucket/$project/"
stored_config=$temp/config/
headers=$temp/headers

if [ -e "$pulls" ]; then
  echo using cached $pulls
else
  curl -s -s -H "Authorization: token $GITHUB_TOKEN" --header "Content-Type: application/json" -H "Accept: application/vnd.github.shadow-cat-preview+json" https://api.github.com/repos/$GITHUB_REPOSITORY/pulls > $pulls
fi

cat "$pulls" | jq -c '.[]'|jq -c -r '{
 head_repo: .head.repo.full_name,
 base_repo: .base.repo.full_name,
 head_ref: .head.ref,
 head_sha: .head.sha,
 base_sha: .base.sha,
 clone_url: .head.repo.clone_url,
 merge_commit_sha: .merge_commit_sha,
 created_at: .created_at,
 issue_url: .issue_url,
 commits_url: .commits_url,
 comments_url: .comments_url
 } | @base64' > "$escaped"
if [ -s "$escaped" ]; then
  if [ -d "$tree_config" ]; then
    mkdir -p "$stored_config"
    rsync -a "$tree_config" "$stored_config"
  fi
fi
end_group

get_created_from_events() {
  rm -f "$headers"
  created_at=$(curl -s -S \
    -H "Authorization: token $GITHUB_TOKEN" \
    --header "Content-Type: application/json" \
    -D "$headers" \
    "$1" |
    jq -M -r '[ .[]|select (.event=="head_ref_force_pushed") ][-1].created_at')
  if [ "$created_at" = "null" ]; then
    created_time=0
  else
    created_time=$(date_to_epoch $created_at)
  fi
  if [ -e "$headers" ]; then
    next_url=$(perl -ne 'next unless s/^Link: //;s/,\s+/\n/g; print "$1" if /<(.*)>; rel="last"/' $headers)
    rm -f "$headers"
    if [ -n "$next_url" ]; then
      other_time=$(get_created_from_events "$next_url")
      if [ "$created_time" -lt "$other_time" ]; then
        created_time=$other_time
      fi
    fi
  fi
  echo "$created_time"
}

for a in $(cat "$escaped"); do
  echo "$a" | base64 --decode | jq -r . > $pull
  url=$(cat $pull | jq -r .commits_url | perl -pne 's{://api.github.com/repos/(.*/pull)s}{://github.com/$1}')
  issue_url=$(cat $pull | jq -r .issue_url)
  begin_group "Considering $url"
  created_at=$(get_created_from_events "${issue_url}/events")
  if [ "$created_at" -eq 0 ]; then
    created_at=$(date_to_epoch $(cat $pull | jq -r .created_at))
  fi
  age=$(( $start / 1000000000 - $created_at ))
  if [ $age -gt $time_limit ]; then
    end_group
    continue
  fi
  head_repo=$(cat $pull | jq -r .head_repo)
  base_repo=$(cat $pull | jq -r .base_repo)
  if [ "$head_repo" = "$base_repo" ]; then
    end_group
    continue
  fi
  head_sha=$(cat $pull | jq -r .head_sha)
  base_sha=$(cat $pull | jq -r .base_sha)
  merge_commit_sha=$(cat $pull | jq -r .merge_commit_sha)
  comments_url=$(cat $pull | jq -r .comments_url)
  commits_url=$(cat $pull | jq -r .commits_url)
  clone_url=$(cat $pull | jq -r .clone_url)
  clone_url=$(echo "$clone_url" | sed -e 's/https/http/')
  head_ref=$(cat $pull | jq -r .head_ref)
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
  git remote rm pr 2>/dev/null || true
  git remote add pr $clone_url
  cat .git/config
  git fetch pr $head_ref
  git checkout $head_sha
  git remote rm pr 2>/dev/null || true
  end_group
  (
    temp=$(mktemp -d)
    if [ -d "$stored_config" ] && [ ! -d "$tree_config" ]; then
      mkdir -p "$tree_config"
      rsync -a "$stored_config" "$tree_config"
      cleanup_tree_config=1
    fi
    "$spellchecker/unknown-words.sh" || true
    rm -rf "$temp"
    if [ -n "$cleanup_tree_config" ]; then
      rm -rf "$tree_config"
    fi
  )
done
