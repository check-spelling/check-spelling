#!/bin/bash
# This CI acceptance test is based on:
# https://github.com/jsoref/spelling/tree/04648bdc63723e5cdf5cbeaff2225a462807abc8
# It is conceptually `f` which runs `w` (spelling-unknown-word-splitter)
# plus `fchurn` which uses `dn` mostly rolled together.
set -e
export spellchecker=${spellchecker:-${GITHUB_ACTION_PATH:-/app}}

if [ $(id -u) != 0 ]; then
  SUDO=sudo
fi
$SUDO $spellchecker/fast-install.pl

. "$spellchecker/common.sh"

dispatcher() {
  if [ -n "$INPUT_EVENT_ALIASES" ]; then
    GITHUB_EVENT_NAME=$(echo "$INPUT_EVENT_ALIASES" | jq -r ".$GITHUB_EVENT_NAME // \"$GITHUB_EVENT_NAME\"")
  fi
  INPUT_TASK=${INPUT_TASK:-$INPUT_CUSTOM_TASK}
  case "$INPUT_TASK" in
    comment|collapse_previous_comment)
      comment_task
    ;;
    pr_head_sha)
      pr_head_sha_task
    ;;
  esac
  case "$GITHUB_EVENT_NAME" in
    '')
      (
        echo 'check-spelling does not know what to do because GITHUB_EVENT_NAME is empty.'
        echo
        echo 'This could be because of a configuration error with event_aliases.'
        echo 'It could be because you are using act or a similar GitHub Runner shim,'
        echo 'and its configuration is incorrect.'
      ) >&2
      exit 1
      ;;
    push)
      if to_boolean "$INPUT_SUPPRESS_PUSH_FOR_OPEN_PULL_REQUEST"; then
        pull_request_json=$(mktemp_json)
        pull_request_headers=$(mktemp)
        pull_heads_query="$GITHUB_API_URL/repos/$GITHUB_REPOSITORY/pulls?head=${GITHUB_REPOSITORY%/*}:$GITHUB_REF"
        keep_headers=1 call_curl \
          "$pull_heads_query" > $pull_request_json
        mv "$response_headers" "$pull_request_headers"
        if [ -n "$(jq .documentation_url $pull_request_json 2>/dev/null)" ]; then
          (
            echo "Request for '$pull_heads_query' appears to have yielded an error, it is probably an authentication error."
            if [ -n "$ACT" ]; then
              echo '[act] If you want to use suppress_push_for_open_pull_request, you need to set GITHUB_TOKEN'
            fi
            echo "Headers:"
            cat $pull_request_headers
            echo "Response:"
            cat $pull_request_json
            echo 'Cannot determine if there is an open pull request, proceeding as if there is not.'
          ) >&2
        elif [ $(jq length $pull_request_json) -gt 0 ]; then
          (
            open_pr_number=$(jq -r '.[0].number' $pull_request_json)
            echo "Found [open PR #$open_pr_number]($GITHUB_SERVER_URL/$GITHUB_REPOSITORY/$open_pr_number) - check-spelling should run there."
            echo
            echo '::warning ::WARNING: This workflow is intentionally terminating early with a success code -- it has not checked for misspellings.'
            echo '::warning ::You should treat this workflow run as if it were SKIPPED state and instead look for a `pull_request_target` workflow for `check-spelling` in the PR.'
            if [ -n "$ACT" ]; then
              echo
              echo 'You appear to be running nektos/act, you should probably comment out:'
              echo
              echo "        suppress_push_for_open_pull_request: $INPUT_SUPPRESS_PUSH_FOR_OPEN_PULL_REQUEST"
            fi
          ) >&2
          exit 0
        fi
      fi
      if [ -z "$INPUT_TASK" ]; then
        INPUT_TASK=spelling
      fi
      ;;
    pull_request|pull_request_target)
      if [ -z "$INPUT_TASK" ]; then
        INPUT_TASK=spelling
      fi
      ;;
    schedule)
      exec "$spellchecker/check-pull-requests.sh"
      ;;
    issue_comment)
      if to_boolean "$DEBUG"; then
        set -x
      fi
      if [ -z "$INPUT_TASK" ]; then
        INPUT_TASK=update
      fi
      handle_comment
      ;;
    pull_request_review_comment)
      ( echo 'check-spelling does not currently support comments on code.

          If you are trying to ask @check-spelling-bot to update a PR,
          please quote the comment link as a top level comment instead
          of in a comment on a block of code.

          Future versions may support this feature.
          For the time being, early adopters should remove the
          `pull_request_review_comment` event from their workflow.
          workflow.' \
        | strip_lead
      ) >&2
      quit 0
      ;;
    *)
      ( echo "
          check-spelling does not currently support the GitHub $b$GITHUB_EVENT_NAME$b event.

          If you think it can, consider using:

            with:
              event_aliases: {$Q$GITHUB_EVENT_NAME$Q:${Q}supported_event_name${Q}}

          Future versions may support this feature." \
        | perl -pe 's/^ {10}//'
      ) >&2
      exit 1
      ;;
  esac
}

load_env() {
  input_variables=$(mktemp)
  echo "$INPUTS" |
    grep -v "'" |
    jq -r 'keys[] as $k | "INPUT_\($k | ascii_upcase)='$q'\(.[$k])'$q$Q |
    perl -pe 'next unless m{^([^=]*)(=.*)}; my ($k, $v) = ($1, $2); $k = qq<export $k; [ -z "\$$k" ] && $k>; $v =~ s{\$}{\\\$}g;$_="$k$v;"' > "$input_variables"
  . "$input_variables"
}

who_am_i() {
  who_am_i='query { viewer { databaseId } }'
  who_am_i_json=$(echo '{}' | jq -r --arg query "$who_am_i" '.query=$query')
  comment_author_id=$(
    call_curl \
    -H "Content-Type: application/json" \
    --data-binary "$who_am_i_json" \
    "$GITHUB_GRAPHQL_URL" |
    jq -r '.data.viewer.databaseId // empty'
  )
}

is_comment_minimized() {
  comment_is_collapsed_query="query { node(id:$Q$1$Q) { ... on IssueComment { minimizedReason } } }"
  comment_is_collapsed_json=$(echo '{}' | jq -r --arg query "$comment_is_collapsed_query" '.query=$query')
  comment_is_minimized=$(
    call_curl \
    -H "Content-Type: application/json" \
    --data-binary "$comment_is_collapsed_json" \
    "$GITHUB_GRAPHQL_URL" |
    jq -r '.data.node.minimizedReason'
  )
  [ "$comment_is_minimized" != "null" ]
}

get_previous_comment() {
  comment_search_re="$(title="$report_header" perl -e 'my $title=quotemeta($ENV{title}); $title=~ s/\\././g; print "(?:^|\n)$title";')"
  if [ -z "$comment_author_id" ]; then
    who_am_i
  fi

  # In English
  # we're composing a list
  #   but decomposing our input
  #   selecting elements
  #     if the user.login.id is our target user
  #     and it isn't the comment we just posted...
  #     and the body has our magic keyword (this requires some tuning for matrices)
  #   from that element, we only want the node_id
  # we want the last element
  #   if there's no element, we want the empty string (not 'null')
  jq_comment_query='[ .[] | select(. | (.user.id=='"${comment_author_id:-0}"') and (.node_id != "'"$posted_comment_node_id"'") and (.body | test ("'"$comment_search_re"'") ) ) | .node_id ] | .[-1] // empty'

  get_page() {
    url="$1"
    dir="$2"
    keep_headers=1 call_curl "$url" > "$pr_comments"
    # Subset of rfc8288#section-3
    link=$(perl -ne 'next unless s/^link:.*<([^>]*)>[^,]*'"$dir"'.*/$1/; print' "$response_headers" )
    if [ -n "$link" ] && [ "$dir" = "last" ]; then
      get_page "$link" "prev"
      return
    fi
    node_id=$(jq -r "$jq_comment_query" "$pr_comments")
    if [ -n "$node_id" ]; then
      if ! is_comment_minimized "$node_id"; then
        echo "$node_id"
      fi
      return
    fi
    if [ -n "$link" ]; then
      get_page "$link" "prev"
      return
    fi
  }

  pr_comments=$(mktemp_json)
  get_page "$COMMENTS_URL" "last"
  rm "$pr_comments"
}

get_comment_url_from_id() {
  id="$1"
  comment_url_from_id_query="query { node(id:$Q$id$Q) { ... on IssueComment { url } } }"
  comment_url_from_id_json=$(echo '{}' | jq -r --arg query "$comment_url_from_id_query" '.query=$query')
  call_curl \
    -H "Content-Type: application/json" \
    --data-binary "$comment_url_from_id_json" \
    "$GITHUB_GRAPHQL_URL" |
    jq -r '.data.node.url // empty'
}

comment_task() {
  set_up_files

  if [ -n "$INPUT_INTERNAL_STATE_DIRECTORY" ]; then
    if [ -z "$NEW_TOKENS" ]; then
      NEW_TOKENS="$tokens_file"
    fi
    if [ -z "$STALE_TOKENS" ]; then
      STALE_TOKENS="$INPUT_INTERNAL_STATE_DIRECTORY/remove_words.txt"
    fi
    if [ -s "$INPUT_INTERNAL_STATE_DIRECTORY/followup" ]; then
      followup=$(cat "$INPUT_INTERNAL_STATE_DIRECTORY/followup")
      if [ "$followup" = "collapse_previous_comment" ]; then
        previous_comment_node_id=$(cat "$data_dir/previous_comment.txt")
        if [ -n "$previous_comment_node_id" ]; then
          collapse_comment "$previous_comment_node_id"
          quit 0
        fi
      fi
    fi
  else
    # This behavior was used internally and is not recommended.
    # I hope to remove support for it relatively soon, as I don't think anyone
    # externally picked up this flavor.
    # check-spelling/spell-check-this never suggested it.
    handle_mixed_archive() {
      if [ -n "$1" ]; then
        ls -d $(dirname "$1")/*/$(basename "$1") 2>/dev/null || echo "$1"
      fi
    }
    NEW_TOKENS=$(handle_mixed_archive "$NEW_TOKENS")
    STALE_TOKENS=$(handle_mixed_archive "$STALE_TOKENS")
    NEW_EXCLUDES=$(handle_mixed_archive "$NEW_EXCLUDES")
    SUGGESTED_DICTIONARIES=$(handle_mixed_archive "$SUGGESTED_DICTIONARIES")
  fi
  touch "$diff_output"

  if [ -f "$NEW_TOKENS" ]; then
    patch_add="$(cat "$NEW_TOKENS")"
  fi
  if [ -f "$STALE_TOKENS" ]; then
    patch_remove="$(cat "$STALE_TOKENS")"
  fi
  if [ -f "$NEW_EXCLUDES" ]; then
    cat "$NEW_EXCLUDES" > $should_exclude_file
  fi
  if [ -f "$SUGGESTED_DICTIONARIES" ]; then
    cat "$SUGGESTED_DICTIONARIES" > $extra_dictionaries_json
  fi
  fewer_misspellings_canary=$(mktemp)
  quit_without_error=1
  get_has_errors
  if [ -z "$has_errors" ] && [ -z "$patch_add" ]; then
    quit
  fi
  more_misspellings
}

get_pull_request_url() {
  jq -r '.pull_request.url // .issue.pull_request.url // empty' "$GITHUB_EVENT_PATH"
}

get_pr_sha_from_url() {
  pull_request_head_info=$(mktemp_json)
  pull_request "$1" | jq -r ".head // empty" > "$pull_request_head_info"
  jq -r ".sha // empty" "$pull_request_head_info"
}

pr_head_sha_task() {
  pull_request_url=$(get_pull_request_url)
  if [ -n "$pull_request_url" ]; then
    echo "PR_HEAD_SHA=$(get_pr_sha_from_url "$pull_request_url")" >> "$GITHUB_ENV"
  fi
  quit
}

get_workflow_path() {
  action_run=$(mktemp_json)
  if call_curl \
    "$GITHUB_API_URL/repos/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID" > "$action_run"; then
    workflow_url=$(jq -r '.workflow_url // empty' "$action_run")
    if [ -n "$workflow_url" ]; then
      workflow_json=$(mktemp_json)
      if call_curl \
        "$workflow_url" > "$workflow_json"; then
        jq -r .path "$workflow_json"
      fi
    fi
  fi
}

should_patch_head() {
  if [ ! -d "$bucket/$project" ]; then
    # if there is no directory in the merged state, then adding files into it
    # will not result in a merge conflict
    true
  else
    # if there is a directory in the merged state, then we don't want to
    # suggest changes to the directory if it doesn't exist in the branch,
    # because that would almost certainly result in merge conflicts.
    # If people want to talk to the bot, they should rebase first.
    pull_request_url=$(get_pull_request_url)
    if [ -z "$pull_request_url" ]; then
      false
    else
      pull_request_sha=$(get_pr_sha_from_url "$pull_request_url")
      git fetch origin "$pull_request_sha" >&2
      if git ls-tree "$pull_request_sha" -- "$bucket/$project" 2> /dev/null | grep -q tree; then
        return 0
      fi
      return 1
    fi
  fi
}

offer_quote_reply() {
  if [ -n "$offer_quote_reply_cached" ]; then
    return $offer_quote_reply_cached
  fi
  if to_boolean "$INPUT_EXPERIMENTAL_APPLY_CHANGES_VIA_BOT"; then
    case "$GITHUB_EVENT_NAME" in
      issue_comment)
        issue=$(mktemp_json)
        pull_request_info=$(mktemp_json)
        if [ $(are_issue_head_and_base_in_same_repo) != 'true' ] || ! should_patch_head; then
          offer_quote_reply_cached=1
        else
          offer_quote_reply_cached=0
        fi
        ;;
      pull_request|pull_request_target)
        if [ $(are_head_and_base_in_same_repo "$GITHUB_EVENT_PATH" '.pull_request') != 'true' ] || ! should_patch_head; then
          offer_quote_reply_cached=1
        else
          offer_quote_reply_cached=0
        fi
        ;;
      *)
        offer_quote_reply_cached=1
        ;;
    esac
  else
    offer_quote_reply_cached=1
  fi
  return $offer_quote_reply_cached
}

repo_is_private() {
  private=$(jq -r 'if .repository.private != null then .repository.private else "" end' "$GITHUB_EVENT_PATH")
  [ "$private" != "false" ]
}

command_v() {
  command -v "$1" >/dev/null 2>/dev/null
}

react_comment_and_die() {
  trigger_comment_url="$1"
  message="$2"
  react="$3"
  echo "::error ::$message"
  react "$trigger_comment_url" "$react" > /dev/null
  if [ -n "$COMMENTS_URL" ] && [ -z "${COMMENTS_URL##*:*}" ]; then
    PAYLOAD=$(mktemp_json)
    echo '{}' | jq --arg body "@check-spelling-bot: ${react_prefix}$message${N}See [log]($(get_action_log)) for details." '.body = $body' > $PAYLOAD

    res=0
    comment "$COMMENTS_URL" "$PAYLOAD" > /dev/null || res=$?
    if [ $res -gt 0 ]; then
      if ! to_boolean "$DEBUG"; then
        echo "::error ::Failed posting to $COMMENTS_URL"
        cat "$PAYLOAD"
      fi
      return $res
    fi

    rm $PAYLOAD
  fi
  quit 1
}

confused_comment() {
  react_comment_and_die "$1" "$2" "confused"
}

github_user_and_email() {
  user_json=$(mktemp_json)
  call_curl \
    "$GITHUB_API_URL/users/$1" > $user_json

  github_name=$(jq -r '.name // empty' $user_json)
  if [ -z "$github_name" ]; then
    github_name=$1
  fi
  github_email=$(jq -r '.email // empty' $user_json)
  rm $user_json
  if [ -z "$github_email" ]; then
    github_email="$1@users.noreply.github.com"
  fi
  COMMIT_AUTHOR="--author=$github_name <$github_email>"
}

git_commit() {
  reason="$1"
  git add -u
  git config user.email "check-spelling-bot@users.noreply.github.com"
  git config user.name "check-spelling-bot"
  git commit \
    "$COMMIT_AUTHOR" \
    --date="$created_at" \
    -m "$(echo "[check-spelling] Applying automated metadata updates

                $reason

                Signed-off-by: check-spelling-bot <check-spelling-bot@users.noreply.github.com>
                " | strip_lead)"
}

mktemp_json() {
  file=$(mktemp)
  mv "$file" "$file.json"
  echo "$file.json"
}

show_github_actions_push_disclaimer() {
  pr_number=$(jq -r '.issue.number' "$GITHUB_EVENT_PATH")
  pr_path_escaped=$(echo "$GITHUB_REPOSITORY/pull/$pr_number" | perl -pe 's{/}{\%2F}g')
  pr_query=$(echo '{
      repository(owner:"'${GITHUB_REPOSITORY%/*}'", name:"'${GITHUB_REPOSITORY#*/}'") {
        pullRequest(number:'$pr_number') {
          headRepository {
            nameWithOwner
          }
          headRefName
        }
      }
    }' |
    strip_lead_and_blanks
  )
  pr_query_json=$(echo '{}' | jq -r --arg query "$pr_query" '.query=$query')
  repository_edit_branch=$(
    call_curl \
    -H "Content-Type: application/json" \
    --data-binary "$pr_query_json" \
    "$GITHUB_GRAPHQL_URL" |
    jq -r '(.data.repository.pullRequest.headRepository.nameWithOwner + "/edit/" + .data.repository.pullRequest.headRefName)'
  )

  OUTPUT="### :hourglass: check-spelling changes applied

  As [configured](https://github.com/check-spelling/check-spelling/wiki/Feature:-Update-expect-list#github_token), the commit pushed by @check-spelling-bot to GitHub doesn't trigger GitHub workflows due to a limitation of the @github-actions system.

  <details><summary>Users with the Admin role can address this for future interactions :magic_wand:</summary>

  #### Create a deploy key and secret
  $B sh
  (
    set -e
    brand=check-spelling; repo=$q$GITHUB_REPOSITORY$q; SECRET_NAME=CHECK_SPELLING"'
    cd $(mktemp -d)
    ssh-keygen -f "./$brand" -q -N "" -C "$brand key for $repo"
    gh repo deploy-key add "./$brand.pub" -R "$repo" -w -t "$brand-talk-to-bot"
    cat "./$brand" | gh secret -R "$repo" set "$SECRET_NAME"
  )'"
  $B

  #### Configure update job in workflow to use secret

  If the $b$(get_workflow_path)$b workflow ${b}update${b} job doesn't already have the "'`checkout`/`with`/`ssh-key`, then add them:

  ``` diff
   update:
   ...
   - name: checkout
     uses: actions/checkout@v3
  +  with:
  +    ssh-key: "${{ secrets.CHECK_SPELLING }}"
  ```'"

  </details>

  <!--$n$report_header$n-->
  To trigger another validation round and hopefully a :white_check_mark:, please add a blank line, e.g. to [$expect_file]($GITHUB_SERVER_URL/$repository_edit_branch/$expect_file?pr=$pr_path_escaped) and commit the change."
  BODY=$(mktemp)
  echo "$OUTPUT" > "$BODY"
  body_to_payload "$BODY"
  COMMENTS_URL=$(jq -r '.issue.comments_url' "$GITHUB_EVENT_PATH")
  response=$(mktemp)
  comment "$COMMENTS_URL" "$PAYLOAD" > $response || res=$?
  if [ $res -eq 0 ]; then
    track_comment "$response"
  fi
}

are_head_and_base_in_same_repo() {
  jq -r '('$2'.head.repo.full_name // "head") == ('$2'.base.repo.full_name // "base")' "$1"
}

are_issue_head_and_base_in_same_repo() {
  jq -r '.issue // empty' "$GITHUB_EVENT_PATH" > "$issue"
  pull_request_url=$(jq -r '.pull_request.url // empty' "$issue")
  pull_request "$pull_request_url" > "$pull_request_info"
  are_head_and_base_in_same_repo "$pull_request_info" ''
}

handle_comment() {
  action=$(jq -r '.action // empty' "$GITHUB_EVENT_PATH")
  if [ "$action" != "created" ]; then
    quit 0
  fi

  if ! offer_quote_reply; then
    quit 0
  fi

  set_up_files

  comment=$(mktemp_json)
  jq -r '.comment // empty' "$GITHUB_EVENT_PATH" > $comment
  body=$(mktemp)
  jq -r '.body // empty' $comment > $body

  trigger=$(perl -ne 'print if /\@check-spelling-bot(?:\s+|:\s*)apply.*\Q$ENV{INPUT_REPORT_TITLE_SUFFIX}\E/' < $body)
  rm $body
  if [ -z "$trigger" ]; then
    quit 0
  fi

  trigger_comment_url=$(jq -r '.url // empty' $comment)
  sender_login=$(jq -r '.sender.login // empty' "$GITHUB_EVENT_PATH")
  issue_user_login=$(jq -r '.issue.user.login // empty' "$GITHUB_EVENT_PATH")
  pull_request_head_info=$(mktemp_json)
  jq .head "$pull_request_info" > "$pull_request_head_info"
  pull_request_sha=$(jq -r '.sha // empty' "$pull_request_head_info")
  set_comments_url "$GITHUB_EVENT_NAME" "$GITHUB_EVENT_PATH" "$pull_request_sha"
  react_prefix_base="Could not perform [request]($(comment_url_to_html_url $trigger_comment_url)).$N"
  react_prefix="$react_prefix_base"
  if [ "$sender_login" != "$issue_user_login" ]; then
    collaborators_url=$(jq -r '.repository.collaborators_url // empty' "$GITHUB_EVENT_PATH")
    collaborators_url=$(echo "$collaborators_url" | perl -pe "s<\{/collaborator\}></$sender_login/permission>")
    collaborator_permission=$(collaborator "$collaborators_url" | jq -r '.permission // empty')
    case $collaborator_permission in
      admin)
        ;;
      write)
        ;;
      *)
        confused_comment "$trigger_comment_url" "Commenter (@$sender_login) isn't author (@$issue_user_login) / collaborator."
        ;;
    esac
  fi
  number=$(jq -r '.number // empty' "$issue")
  created_at=$(jq -r '.created_at // empty' "$comment")
  issue_url=$(jq -r '.url // empty' "$issue")
  pull_request_ref=$(jq -r '.ref // empty' "$pull_request_head_info")
  if git remote get-url origin | grep -q ^https://; then
    pull_request_repo=$(jq -r '.repo.clone_url // empty' "$pull_request_head_info")
  else
    pull_request_repo=$(jq -r '.repo.ssh_url // empty' "$pull_request_head_info")
  fi
  git remote add request $pull_request_repo
  git fetch request "$pull_request_sha"
  git config advice.detachedHead false
  git reset --hard
  git checkout "$pull_request_sha"

  number_filter() {
    perl -pe 's<\{.*\}></(\\d+)>'
  }
  export pull_request_base=$(jq -r '.comment.html_url' "$GITHUB_EVENT_PATH" | perl -pe 's/\d+$/(\\d+)/')
  comments_base=$(jq -r '.repository.comments_url // empty' "$GITHUB_EVENT_PATH" | number_filter)
  export issue_comments_base=$(jq -r '.repository.issue_comment_url // empty' "$GITHUB_EVENT_PATH" | number_filter)
  export comments_url="$pull_request_base|$comments_base|$issue_comments_base"

  comment_url=$(echo "$trigger" | perl -ne '
    next unless m{((?:$ENV{comments_url}))};
    my $capture=$1;
    my $old_base=$ENV{pull_request_base};
    my $prefix=$ENV{issue_comments_base};
    $old_base=~s{\Q(\d+)\E$}{};
    $prefix=~s{\Q(\d+)\E$}{};
    $capture =~ s{$old_base}{$prefix};
    print "$capture\n";
  ' | sort -u)
  [ -n "$comment_url" ] ||
    confused_comment "$trigger_comment_url" "Did not find match for _/_$b$comments_url${b}_/_ in comment."
  [ $(echo "$comment_url" | wc -l) -gt 1 ] &&
    confused_comment "$trigger_comment_url" "Found more than one _/_$b$comments_url${b}_/_ match in comment:$n$B$n$comment_url$n$B"

  res=0
  comment "$comment_url" > $comment ||
    confused_comment "$trigger_comment_url" "Failed to retrieve $b$comment_url$b."

  bot_comment_author=$(jq -r '.user.login // empty' $comment)
  bot_comment_node_id=$(jq -r '.node_id // empty' $comment)
  bot_comment_url=$(jq -r '.issue_url // .comment.url' $comment)
  github_actions_bot="github-actions[bot]"
  [ -n "$bot_comment_author" ] ||
    confused_comment "$trigger_comment_url" "Could not retrieve author of $(comment_url_to_html_url $comment_url)."
  [ "$bot_comment_author" = "$github_actions_bot" ] ||
    confused_comment "$trigger_comment_url" "Expected @$github_actions_bot to be author of $(comment_url_to_html_url $comment_url) (found @$bot_comment_author)."
  [ "$issue_url" = "$bot_comment_url" ] ||
    confused_comment "$trigger_comment_url" "Referenced comment was for a different object: $bot_comment_url"

  comment_body=$(mktemp)
  jq -r '.body // empty' "$comment" > "$comment_body"
  rm "$comment"
  grep -q '@check-spelling-bot Report' "$comment_body" ||
    confused_comment "$trigger_comment_url" "$(comment_url_to_html_url $comment_url) does not appear to be a @check-spelling-bot report"

  minimized_info=$(mktemp_json)
  call_curl \
  -H "Content-Type: application/json" \
  --data-binary "$(echo '{}' | jq --arg query "query { node(id: $Q$bot_comment_node_id$Q) { ... on IssueComment { isMinimized minimizedReason } } }" '.query = $query')" \
  $GITHUB_GRAPHQL_URL > "$minimized_info"

  if [ $(jq '.data.node.isMinimized' "$minimized_info") == 'true' ]; then
    minimized_reason=$(jq -r '.data.node.minimizedReason | ascii_downcase // empty' "$minimized_info")
    decorated_reason=" (_${minimized_reason}_)"
    minimized_reason_suffix='.'
    previous_comment_node_id=$(get_previous_comment)
    if [ -n "$previous_comment_node_id" ]; then
      latest_comment_url=$(get_comment_url_from_id "$previous_comment_node_id")
      if [ -n "$latest_comment_url" ] && [ "$comment_url" != "$latest_comment_url" ]; then
        minimized_reason_suffix=". Did you mean to apply the most recent report ($latest_comment_url)?"
      fi
    fi
    case "$minimized_reason" in
      "")
        ;;
      "resolved")
        minimized_reason="$decorated_reason. This probably means the changes have already been applied";;
      "outdated")
        minimized_reason="$decorated_reason. This probably means the referenced comment has been obsoleted by a more recent push & review";;
      *)
        minimized_reason="$decorated_reason";;
    esac
    confused_comment "$trigger_comment_url" "The referenced report $(comment_url_to_html_url $comment_url) is hidden$minimized_reason$minimized_reason_suffix"
  fi
  capture_items() {
    perl -ne 'next unless s{^\s*my \@'$1'=qw\('$q$Q'(.*)'$Q$q'\);$}{$1}; print'
  }
  capture_item() {
    perl -ne 'next unless s{^\s*my \$'$1'="(.*)";$}{$1}; print'
  }
  skip_wrapping=1

  instructions_head=$(mktemp)
  (
    patch_add=1
    patch_remove=1
    should_exclude_patterns=1
    patch_variables $comment_body > $instructions_head
  )
  git restore -- $bucket/$project 2> /dev/null || true

  res=0
  . $instructions_head || res=$?
  if [ $res -gt 0 ]; then
    echo "instructions_head failed ($res)"
    cat $instructions_head
    confused_comment "$trigger_comment_url" "Failed to set up environment to apply changes for $(comment_url_to_html_url $comment_url)."
  fi
  rm $comment_body $instructions_head
  instructions=$(generate_instructions)

  react_prefix="${react_prefix}[Instructions]($(comment_url_to_html_url $comment_url)) "
  . $instructions || res=$?
  if [ $res -gt 0 ]; then
    echo "instructions failed ($res)"
    cat $instructions
    res=0
    confused_comment "$trigger_comment_url" "failed to apply."
  fi
  rm $instructions
  git status --u=no --porcelain | grep -q . ||
    confused_comment "$trigger_comment_url" "didn't change repository content.${N}Maybe someone already applied these changes?"
  react_prefix="$react_prefix_base"
  github_user_and_email $sender_login
  git_commit "$(echo "Update per $(comment_url_to_html_url $comment_url)
                      Accepted in $(comment_url_to_html_url $trigger_comment_url)
                    "|strip_lead)" ||
    confused_comment "$trigger_comment_url" "did not generate a commit."
  git push request "HEAD:$pull_request_ref" ||
    confused_comment "$trigger_comment_url" "generated a commit, but the $pull_request_repo rejected the commit.${N}Maybe this task lost a race with another push?"

  react "$trigger_comment_url" 'eyes' > /dev/null
  react "$comment_url" 'rocket' > /dev/null
  trigger_node=$(jq -r '.comment.node_id // empty' "$GITHUB_EVENT_PATH")
  collapse_comment $trigger_node $bot_comment_node_id

  if git remote get-url origin | grep -q ^https://; then
    show_github_actions_push_disclaimer
  fi
  echo "# end"
  quit 0
}

define_variables() {
  if [ -f "$output_variables" ]; then
    return
  fi
  . "$spellchecker/update-state.sh"
  load_env
  GITHUB_TOKEN=${GITHUB_TOKEN:-$INPUT_GITHUB_TOKEN}
  if [ -n "$GITHUB_TOKEN" ]; then
    export AUTHORIZATION_HEADER="Authorization: token $GITHUB_TOKEN"
  else
    export AUTHORIZATION_HEADER='X-No-Authorization: Sorry About That'
  fi

  export early_warnings=$(mktemp)
  if [ -n "$INPUT_INTERNAL_STATE_DIRECTORY" ]; then
    data_dir="$INPUT_INTERNAL_STATE_DIRECTORY"
    if [ -e "$data_dir/artifact.zip" ]; then
      (
        cd "$data_dir"
        unzip -q 'artifact.zip'
        rm artifact.zip
      )
    fi
  else
    data_dir=$(mktemp -d)
  fi
  bucket=${INPUT_BUCKET:-$bucket}
  project=${INPUT_PROJECT:-$project}
  if to_boolean "$junit" || to_boolean "$INPUT_QUIT_WITHOUT_ERROR"; then
    quit_without_error=1
  fi
  if [ -z "$bucket" ] && [ -z "$project" ] && [ -n "$INPUT_CONFIG" ]; then
    bucket=${INPUT_CONFIG%/*}
    project=${INPUT_CONFIG##*/}
  fi
  job_count=${INPUT_EXPERIMENTAL_PARALLEL_JOBS:-2}
  if ! [ "$job_count" -eq "$job_count" ] 2>/dev/null || [ "$job_count" -lt 2 ]; then
    job_count=1
  fi
  extra_dictionary_limit=$(echo "${INPUT_EXTRA_DICTIONARY_LIMIT}" | perl -pe 's/\D+//g')
  if [ -z "$extra_dictionary_limit" ]; then
    extra_dictionary_limit=5
  fi
  if [ -n "$INPUT_SPELL_CHECK_THIS" ] &&
    ! echo "$INPUT_SPELL_CHECK_THIS" | perl -ne 'chomp; exit 1 unless m{^[-_.a-z0-9]+/[-_.a-z0-9]+(?:|\@[-_.a-z0-9]+)$};'; then
    INPUT_SPELL_CHECK_THIS=''
    echo "$(get_workflow_path): line 0, columns 1-1, Warning - unsupported repository (unsupported-repo-notation)" >> "$early_warnings"
  fi

  dict="$spellchecker/words"
  patterns="$spellchecker/patterns.txt"
  forbidden_path="$spellchecker/forbidden.txt"
  excludes="$spellchecker/excludes.txt"
  excludes_path="$temp/excludes.txt"
  only="$spellchecker/only.txt"
  only_path="$temp/only.txt"
  dictionary_path="$temp/dictionary.txt"
  allow_path="$temp/allow.txt"
  reject_path="$temp/reject.txt"
  expect_path="$temp/expect.words.txt"
  excludelist_path="$temp/excludes.txt"
  patterns_path="$temp/patterns.txt"
  advice_path="$temp/advice.md"
  advice_path_txt="$temp/advice.txt"
  word_splitter="$spellchecker/spelling-unknown-word-splitter.pl"
  word_collator="$spellchecker/spelling-collator.pl"
  run_output="$temp/unknown.words.txt"
  run_files="$temp/reporter-input.txt"
  diff_output="$temp/output.diff"
  tokens_file="$data_dir/tokens.txt"
  action_log_ref="$data_dir/action_log_ref.txt"
  extra_dictionaries_json="$data_dir/suggested_dictionaries.json"
  output_variables=$(mktemp)
  instructions_preamble=$(mktemp)

  warnings_list=$(echo "$INPUT_WARNINGS" | perl -pe 's/[^-a-z]+/|/g;s/^\||\|$//g')

  report_header="# @check-spelling-bot Report"
  if [ -n "$INPUT_REPORT_TITLE_SUFFIX" ]; then
    report_header="$report_header $INPUT_REPORT_TITLE_SUFFIX"
  fi
  INPUT_TASK="${INPUT_TASK:-$INPUT_CUSTOM_TASK}"
}

sort_unique() {
  sort -u -f "$@" | perl -ne 'next unless /./; print'
}

project_file_path() {
  echo $bucket/$project/$1
}

check_pattern_file() {
  perl -i -e 'open WARNINGS, ">>", $ENV{early_warnings};
  while (<>) {
    next if /^#/;
    next unless /./;
    if (eval {qr/$_/}) {
      print;
    } else {
      $@ =~ s/(.*?)\n.*/$1/m;
      chomp $@;
      my $err = $@;
      $err =~ s{^.*? in regex; marked by <-- HERE in m/(.*) <-- HERE.*$}{$1};
      print WARNINGS "$ARGV: line $., columns $-[0]-$-[0], Warning - bad regex (bad-regex)\n$@\n";
      print "^\$\n";
    }
  }
  close WARNINGS;
  ' $1
}

check_for_newline_at_eof() {
  maybe_missing_eol="$1"
  if [ -s "$maybe_missing_eol" ] && [ $(tail -1 "$maybe_missing_eol" | wc -l) -eq 0 ]; then
    line=$(( $(cat "$maybe_missing_eol" | wc -l) + 1 ))
    start=$(tail -1 "$maybe_missing_eol" | wc -c)
    stop=$(( $start + 1 ))
    echo "$maybe_missing_eol: line $line, columns $start-$stop, Warning - no newline at eof (no-newline-at-eof)" >> "$early_warnings"
    echo >> "$maybe_missing_eol"
  fi
}

check_dictionary() {
  file="$1"
  expected_chars="a-zA-Z'"
  comment_char="#"
  perl -e '
  open WARNINGS, ">>", $ENV{early_warnings};
  my $file = $ARGV[0];
  open FILE, "<", $file;
  $/ = undef;
  my $content = <FILE>;
  close FILE;
  open FILE, ">", $file;

  my $first_end = undef;
  my $messy = 0;
  $. = 0;
  while ($content =~ s/([^\r\n\x0b\f\x85\x2028\x2029]*)(\r\n|\n|\r|\x0b|\f|\x85|\x2028|\x2029)//m) {
    ++$.;
    my ($line, $end) = ($1, $2);
    unless (defined $first_end) {
      $first_end = $end;
    } elsif ($end ne $first_end) {
      print WARNINGS "$file: line $., columns $-[0]-$+[0], Warning - entry has inconsistent line ending (unexpected-line-ending)\n";
    }
    if ($line =~ '"/^[${expected_chars}]*([^${expected_chars}]+)/"') {
      $column_range="$-[1]-$+[1]";
      unless ($line =~ '"/^${comment_char}/"') {
        print WARNINGS "$file: line $., columns $column_range, Warning - ignoring entry because it contains non alpha characters (non-alpha-in-dictionary)\n";
      }
      $line = "";
    }
    print FILE "$line\n";
  }
  close WARNINGS;
' "$file"
}

cleanup_file() {
  export maybe_bad="$1"

  result=0
  perl -e '
    use Cwd qw(abs_path);
    my $maybe_bad=abs_path($ENV{maybe_bad});
    my $workspace_path=abs_path($ENV{GITHUB_WORKSPACE});
    if ($maybe_bad !~ /^\Q$workspace_path\E/) {
      print "::error ::Configuration files must live within $workspace_path...\n";
      print "::error ::Unfortunately, file $maybe_bad appears to reside elsewhere.\n";
      exit 3;
    }
    if ($maybe_bad =~ m{/\.git/}i) {
      print "::error ::Configuration files must not live within `.git/`...\n";
      print "::error ::Unfortunately, file $maybe_bad appears to.\n";
      exit 4;
    }
  ' || result=$?
  if [ $result -gt 0 ]; then
    quit $result
  fi

  type="$2"
  case "$type" in
    patterns|excludes|only)
      check_pattern_file "$maybe_bad"
    ;;
    dictionary|expect|allow)
      check_dictionary "$maybe_bad"
    ;;
    # reject isn't checked, it allows for regular expressions
  esac
  check_for_newline_at_eof "$maybe_bad"
}

get_project_files() {
  ext=$(echo "$1" | sed -e 's/^.*\.//')
  file=$(echo "$1" | sed -e "s/\.$ext$//")
  dest=$2
  type=$file
  if [ ! -e "$dest" ] && [ -n "$bucket" ] && [ -n "$project" ]; then
    from=$(project_file_path $file.$ext)
    case "$from" in
      .*)
        append_to="$from"
        append_to_generated=""
        if [ -f "$from" ]; then
          echo "Retrieving $file from $from"
          cleanup_file "$from" "$type"
          cp "$from" $dest
          from_expanded="$from"
        else
          if [ ! -e "$from" ]; then
            from=$(echo $from | sed -e "s/\.$ext$//")
          fi
          if [ -d "$from" ]; then
            from_expanded=$(ls $from/*$ext |sort)
            append_to=$from/$(git rev-parse --revs-only HEAD || date +%Y%M%d%H%m%S).$ext
            append_to_generated=new
            touch $dest
            echo "Retrieving $file from $from_expanded"
            for item in $from_expanded; do
              if [ -s $item ]; then
                cleanup_file "$item" "$type"
                cat "$item" >> $dest
              fi
            done
            from="$from/$(basename "$from")".$ext
          else
            from_expanded="$from.$ext"
            from="$from_expanded"
          fi
        fi;;
      ssh://git@*|git@*)
        (
          echo "Retrieving $file from $from"
          cd $temp
          repo=$(echo "$bucket" | perl -pe 's#(?:ssh://|)git\@github.com[:/]([^/]*)/(.*.git)#https://github.com/$1/$2#')
          [ -d metadata ] || git clone --depth 1 $repo --single-branch --branch $project metadata
          cleanup_file "metadata/$file.txt" "$type"
          cp metadata/$file.txt $dest 2> /dev/null || touch $dest
        );;
      gs://*)
        echo "Retrieving $file from $from"
        gsutil cp -Z $from $dest >/dev/null 2>/dev/null || touch $dest
        cleanup_file "$dest" "$type"
        ;;
      *://*)
        echo "Retrieving $file from $from"
        download "$from" "$dest" || touch $dest
        cleanup_file "$dest" "$type"
        ;;
    esac
  fi
}
get_project_files_deprecated() {
  # "preferred" "deprecated" "path"
  if [ ! -s "$3" ]; then
    save_append_to="$append_to"
    get_project_files "$2" "$3"
    if [ -s "$3" ]; then
      example=$(for file in $from_expanded; do echo $file; done|head -1)
      if [ $(basename $(dirname $example)) = "$2" ]; then
        note=" directory"
      else
        note=""
      fi
      echo "::error file=$example::deprecation: please rename '$2'$note to '$1' (deprecated-feature)" >> "$early_warnings"
    else
      append_to="$save_append_to"
    fi
  fi
}

download() {
  exit_value=0
  curl -A "$curl_ua" -L -s "$1" -o "$2" -f || exit_value=$?
  if [ $exit_value = 0 ]; then
    echo "Downloaded $1 (to $2)" >&2
  else
    echo "Failed to download $1 (to $2)" >&2
  fi
  return $exit_value
}

download_or_quit_with_error() {
  exit_code=$(mktemp)
  download "$1" "$2" || (
    echo $? > $exit_code
    echo "Could not download $1 (to $2)" >&2
  )
  if [ -s $exit_code ]; then
    exit_value=$(cat $exit_code)
    rm $exit_code
    quit $exit_value
  fi
}

set_up_tools() {
  apps=""
  add_app() {
    if ! command_v $1; then
      apps="$apps $@"
    fi
  }
  add_app curl ca-certificates
  add_app git
  if [ -n "$apps" ]; then
    if command_v apt-get; then
      export DEBIAN_FRONTEND=noninteractive
      $SUDO apt-get -qq update &&
      $SUDO apt-get -qq install --no-install-recommends -y $apps >/dev/null 2>/dev/null
      echo Installed: $apps >&2
    elif command_v brew; then
      brew install $apps
    else
      echo missing $apps -- things will fail >&2
    fi
  fi
  set_up_jq
  curl_ua="check-spelling/$(cat $spellchecker/version); $(curl --version|perl -ne '$/=undef; <>; s/\n.*//;s{ }{/};s/ .*//;print')"
}

curl_auth() {
  if [ -z "$no_curl_auth" ]; then
    echo "$AUTHORIZATION_HEADER"
  else
    echo 'X-No-Authorization: Sorry About That'
  fi
}

call_curl() {
  curl_attempt=0
  response_headers=$(mktemp)
  response_body=$(mktemp)
  until [ "$curl_attempt" -ge 3 ]
  do
    response_code=$(
      curl -D "$response_headers" -w "%{http_code}" -A "$curl_ua" -s -H "$(curl_auth)" "$@" -o "$response_body"
    )
    if [ "$response_code" -ne 429 ]; then
      cat "$response_body"
      rm -f "$response_body"
      if [ -z "$keep_headers" ]; then
        rm -f "$response_headers"
      fi
      return
    fi
    delay=$(perl -e 'my $delay=5; while (<>) { next unless /^retry-after:\s*(\d+)/i; $delay=$1 || 1; }; print $delay' "$response_headers")
    (echo "call_curl received a 429 and will wait for ${delay}s:"; grep -E -i 'x-github-request-id|x-rate-limit-|retry-after' "$response_headers") >&2
    sleep "$delay"
    curl_attempt=$(($curl_attempt + 1))
  done
}

set_up_jq() {
  if ! command_v jq || jq --version | perl -ne 'exit 0 unless s/^jq-//;exit 1 if /^(?:[2-9]|1\d|1\.(?:[6-9]|1\d+))/; exit 0'; then
    jq_url=https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64
    spellchecker_bin="$spellchecker/bin"
    jq_bin="$spellchecker_bin/jq"
    mkdir -p $spellchecker_bin
    download_or_quit_with_error "$jq_url" "$jq_bin"
    chmod 0755 "$jq_bin"
    PATH=$spellchecker_bin:$PATH
  fi
}

words_to_lines() {
  cat | tr " " "\n"
}

build_dictionary_alias_pattern() {
  if [ -z "$dictionary_alias_pattern" ]; then
    dictionary_alias_pattern="$(
      echo "$INPUT_DICTIONARY_SOURCE_PREFIXES" |
      jq -r 'to_entries | map( {("s{^" +.key + ":}{" + .value +"};"): 1 } ) | .[] | keys[]' |xargs echo
    )"
  fi
}

get_extra_dictionaries() {
  extra_dictionaries="$(echo "$1" | words_to_lines)"
  extra_dictionaries_canary=$(mktemp)
  extra_dictionaries_dir=$(mktemp -d)
  response_headers=$(mktemp)
  if [ -n "$extra_dictionaries" ]; then
    for extra_dictionary in $extra_dictionaries; do
    (
      url=$(echo "$extra_dictionary" | perl -pe "$dictionary_alias_pattern")
      if [ "$url" = "${url#https://raw.githubusercontent.com/*}" ]; then
        no_curl_auth=1
      fi
      dest=$(basename "$url")
      keep_headers=1 call_curl $url > "$extra_dictionaries_dir/$dest"
      if [ -z "$response_code" ] || [ "$response_code" -ge 400 ] 2> /dev/null; then
        (
          echo "::error ::Failed to retrieve $extra_dictionary -- $url"
          cat "$response_headers"
        ) >&2
        rm -f "$extra_dictionaries_canary"
      fi
    )
    done
  fi
  rm -f "$response_headers"
  if [ -e "$extra_dictionaries_canary" ]; then
    rm "$extra_dictionaries_canary"
    echo "$extra_dictionaries_dir"
  else
    echo 'fail'
  fi
}

set_up_reporter() {
  echo "::add-matcher::$spellchecker/reporter.json"
  if to_boolean "$DEBUG"; then
    echo 'env:'
    env|sort
  fi
  if [ -z "$GITHUB_EVENT_PATH" ] || [ ! -s "$GITHUB_EVENT_PATH" ]; then
    GITHUB_EVENT_PATH=/dev/null
  fi
  if to_boolean "$DEBUG"; then
    echo 'GITHUB_EVENT_PATH:'
    cat $GITHUB_EVENT_PATH
  fi
}

set_up_files() {
  if [ ! -d "$bucket/$project/" ] && [ -n "$INPUT_SPELL_CHECK_THIS" ]; then
    spell_check_this_repo=$(mktemp -d)
    spelling_config=.github/actions/spelling/
    spell_check_this_repo_name=${INPUT_SPELL_CHECK_THIS%%@*}
    if [ "$spell_check_this_repo_name" != "$INPUT_SPELL_CHECK_THIS" ]; then
      spell_check_this_repo_branch=${INPUT_SPELL_CHECK_THIS##*@}
      if [ -n "$spell_check_this_repo_branch" ]; then
        spell_check_this_repo_branch="--branch $spell_check_this_repo_branch"
      fi
    fi
    if git clone --depth 1 "https://github.com/$spell_check_this_repo_name" $spell_check_this_repo_branch "$spell_check_this_repo" > /dev/null 2> /dev/null; then
      mkdir -p "$spelling_config"
      cp -R "$spell_check_this_repo/$spelling_config"/* "$bucket/$project/"
      spell_check_this_repo_url=$(cd "$spell_check_this_repo"; git remote get-url origin)
      (
        echo "mkdir -p $spelling_config"
        echo 'cp -R $('
        echo 'cd $(mktemp -d)'
        echo "git clone --depth 1 --no-tags $spell_check_this_repo_url $spell_check_this_repo_branch . > /dev/null 2> /dev/null"
        echo "cd $spelling_config; pwd"
        echo ')/*' "$bucket/$project/"
        echo "git add '$bucket/$project/'"
      ) > "$instructions_preamble"
    fi
  fi
  get_project_files word_expectations.words $expect_path
  get_project_files expect.txt $expect_path
  get_project_files_deprecated word_expectations.words whitelist.txt $expect_path
  expect_files=$from_expanded
  expect_file=$from
  touch $expect_path
  new_expect_file=$append_to
  new_expect_file_new=$append_to_generated
  get_project_files file_ignore.patterns $excludelist_path
  get_project_files excludes.txt $excludelist_path
  excludes_files=$from_expanded
  excludes_file=$from
  if [ -s "$excludes_path" ]; then
    cp "$excludes_path" "$excludes"
  fi
  should_exclude_file=$data_dir/should_exclude.txt
  counter_summary_file=$data_dir/counter_summary.json
  if [ "$INPUT_TASK" = 'spelling' ]; then
    get_project_files dictionary.words $dictionary_path
    get_project_files dictionary.txt $dictionary_path
    if [ -s "$dictionary_path" ]; then
      cp "$dictionary_path" "$dict"
    fi
    if [ ! -s "$dict" ]; then
      DICTIONARY_VERSION=${DICTIONARY_VERSION:-$INPUT_DICTIONARY_VERSION}
      DICTIONARY_URL=${DICTIONARY_URL:-$INPUT_DICTIONARY_URL}
      DICTIONARY_URL="$(perl -e 'my $url = q<'"$DICTIONARY_URL"'>; $url =~ s{\$DICTIONARY_VERSION}{'"$DICTIONARY_VERSION"'}g; print $url;')"
      if [ -z "$DICTIONARY_URL" ] && [ -n "$ACT" ]; then
        (
          echo "This workflow appears to be running under nektos/act"
          echo "Unfortunately, this run has hit: https://github.com/nektos/act/issues/655"
          echo
          echo "In order to run locally, please use:"
          echo
          echo "      with:"
          echo "        dictionary_url: fill_this_in"
          if [ -z "$INPUT_CONFIG" ]; then
            echo "        config: fill_this_in"
          fi
          if [ -z "$INPUT_DICTIONARY_SOURCE_PREFIXES" ]; then
            echo "        dictionary_source_prefixes: fill_this_in"
          fi
          if [ -z "$INPUT_DICTIONARY_VERSION" ]; then
            echo "        dictionary_version: fill_this_in"
          fi
          echo
          echo "You can use the defaults from https://github.com/check-spelling/check-spelling/blob/HEAD/action.yml"
          echo "Note: you may need to omit backslashes for the dictionary_url."
        ) >&2
        exit 1
      fi
      eval download_or_quit_with_error "$DICTIONARY_URL" "$dict"
    fi
    if [ -n "$INPUT_EXTRA_DICTIONARIES" ]; then
      begin_group 'Extra dictionaries'
      build_dictionary_alias_pattern
      extra_dictionaries_dir=$(get_extra_dictionaries "$INPUT_EXTRA_DICTIONARIES")
      if [ -n "$extra_dictionaries_dir" ]; then
        if [ "$extra_dictionaries_dir" = fail ]; then
          quit 4
        fi
        (
          cd "$extra_dictionaries_dir"
          # Items that aren't proper should be moved to patterns instead
          perl -ne "next unless /^[A-Za-z$q]+$/; print" * | sort -u >> "$dict"
        )
        rm -rf "$extra_dictionaries_dir"
      fi
      end_group
    fi
    if [ -n "$INPUT_CHECK_EXTRA_DICTIONARIES" ]; then
      begin_group 'Check extra dictionaries'
      build_dictionary_alias_pattern
      check_extra_dictionaries="$(
        echo "$INPUT_EXTRA_DICTIONARIES $INPUT_EXTRA_DICTIONARIES $INPUT_CHECK_EXTRA_DICTIONARIES" |
        words_to_lines |
        sort |
        uniq -u
      )"
      if [ -n "$check_extra_dictionaries" ]; then
        export check_extra_dictionaries_dir=$(get_extra_dictionaries "$check_extra_dictionaries")
        if [ "$check_extra_dictionaries_dir" = 'fail' ]; then
          check_extra_dictionaries_dir=
        fi
      fi
      end_group
    fi
    get_project_files dictionary_additions.words $allow_path
    get_project_files allow.txt $allow_path
    if [ -s "$allow_path" ]; then
      cat "$allow_path" >> "$dict"
    fi
    get_project_files dictionary_removals.patterns $reject_path
    get_project_files reject.txt $reject_path
    if [ -s "$reject_path" ]; then
      dictionary_temp=$(mktemp)
      if grep_v_string '^('$(echo $(cat "$reject_path")|tr " " '|')')$' < "$dict" > $dictionary_temp; then
        cat $dictionary_temp > "$dict"
      fi
    fi
    get_project_files file_exclusive.patterns $only_path
    get_project_files only.txt $only_path
    if [ -s "$only_path" ]; then
      cp "$only_path" "$only"
    fi
    get_project_files line_forbidden.patterns $forbidden_path
  fi
  extra_dictionaries_cover_entries=$(mktemp)
  get_project_files line_masks.patterns $patterns_path
  get_project_files patterns.txt $patterns_path
  if [ -s "$patterns_path" ]; then
    cp "$patterns_path" "$patterns"
  fi
  get_project_files advice.md $advice_path
  if [ ! -s "$advice_path" ]; then
    get_project_files_deprecated advice.md advice.txt $advice_path_txt
  fi

  if [ -n "$debug" ]; then
    echo "Clean up from previous run"
  fi
  rm -f "$run_output"
}

welcome() {
  echo "Checking spelling..."
  if to_boolean "$DEBUG"; then
    begin_group 'Excluded paths'
    if [ -e "$excludes" ]; then
      echo 'Excluded paths:'
      cat "$excludes"
    else
      echo 'No excluded paths file'
    fi
    end_group
    begin_group 'Only paths restriction'
    if [ -e "$only" ]; then
      echo 'Only paths restriction:'
      cat "$only"
    else
      echo 'No only paths restriction file'
    fi
    end_group
  fi
  if [ -n "$INPUT_EXPERIMENTAL_PATH" ]; then
    cd "$INPUT_EXPERIMENTAL_PATH"
  fi
}

run_spell_check() {
  echo "::set-output name=internal_state_directory::$data_dir" >> $output_variables

  begin_group 'Spell check files'
  file_list=$(mktemp)
  (
    if to_boolean "$INPUT_ONLY_CHECK_CHANGED_FILES"; then
      COMPARE=$(jq -r '.compare // empty' "$GITHUB_EVENT_PATH" 2>/dev/null)
      if [ -n "$COMPARE" ]; then
        BEFORE=$(echo "$COMPARE" | perl -ne 'if (m{/compare/(.*)\.\.\.}) { print $1; } elsif (m{/commit/([0-9a-f]+)$}) { print "$1^"; };')
        BEFORE=$(call_curl \
          "$GITHUB_API_URL/repos/$GITHUB_REPOSITORY/commits/$BEFORE" | jq -r '.sha // empty')
      elif [ -n "$GITHUB_BASE_REF" ]; then
        BEFORE=$GITHUB_BASE_REF
      fi
    fi
    if [ -n "$BEFORE" ]; then
      echo "Only checking files changed from $BEFORE" >&2
      git fetch origin $BEFORE >/dev/null 2>/dev/null
      git diff -z --name-only FETCH_HEAD..HEAD
    else
      INPUT_ONLY_CHECK_CHANGED_FILES=
      git 'ls-files' -z 2> /dev/null
    fi
  ) |\
    "$spellchecker/exclude.pl" > "$file_list"
  if to_boolean "$INPUT_CHECK_FILE_NAMES"; then
    check_file_names="$spellchecker/paths-of-checked-files.txt"
    cat "$file_list" | tr "\0" "\n" > "$check_file_names"
    echo "$check_file_names" | tr "\n" "\0" >> "$file_list"
  fi
  count=$(perl -e '$/="\0"; $count=0; while (<>) {s/\R//; $count++ if /./;}; print $count;' $file_list)
  echo "Checking $count files"
  end_group
  queue_size=$(($count / $job_count / 4))
  if [ $queue_size -lt 4 ]; then
    queue_size=$(($count / $job_count))
    if [ $queue_size -lt 1 ]; then
      queue_size=1
    fi
  fi

  begin_group 'Spell check'
  warning_output=$(mktemp -d)/warnings.txt
  more_warnings=$(mktemp)
  cat $file_list |\
  env -i SHELL="$SHELL" PATH="$PATH" LC_ALL="C" HOME="$HOME" xargs -0 -n$queue_size "-P$job_count" "$word_splitter" |\
  expect="$expect_path" warning_output="$warning_output" more_warnings="$more_warnings" should_exclude_file="$should_exclude_file" counter_summary="$counter_summary_file" unknown_word_limit="$INPUT_UNKNOWN_WORD_LIMIT" "$word_collator" |\
  perl -p -n -e 's/ \(.*//' > "$run_output"
  word_splitter_status="${PIPESTATUS[2]} ${PIPESTATUS[3]}"
  cat "$more_warnings" >> "$warning_output"
  rm "$more_warnings"
  WARNINGS_LIST="$warnings_list" perl -pi -e 'next if /\((?:$ENV{WARNINGS_LIST})\)$/; s{(^(?:.+):[\s]line\s(?:\d+),[\s]columns\s(?:\d+)-(?:\d+),)\sWarning(\s-\s.+\s\(.*\))}{$1 Error$2}' "$warning_output"
  cat "$warning_output"
  echo "::set-output name=warnings::$warning_output" >> $output_variables
  end_group
  if [ "$word_splitter_status" != '0 0' ]; then
    echo "$word_splitter failed ($word_splitter_status)"
    quit 2
  fi
  rm $file_list
}

printDetails() {
  echo ''
  echo 'If you are ok with the output of this run, you will need to'
}

relative_note() {
  if [ -n "$bucket" ] && [ -n "$project" ]; then
    from=$(project_file_path $file)
    case "$from" in
      .*)
        ;;
      ssh://git@*|git@*|gs://|*://*)
        echo '(They can be run anywhere with permissions to update the bucket.)';;
    esac
  fi
}
to_retrieve_expect() {
  expect_file=expect.txt
  case "$bucket" in
    '')
      echo '# no bucket defined -- you can specify one per the README.md using the file defined below:';;
    ssh://git@*|git@*)
      echo "git clone --depth 1 $bucket --single-branch --branch $project metadata; cp metadata/expect.txt .";;
    gs://*)
      echo gsutil cp -Z $(project_file_path expect.txt) expect.txt;;
    *://*)
      echo curl -L -s "$(project_file_path expect.txt)" -o expect.txt;;
  esac
}
to_publish_expect() {
  case "$bucket" in
    '')
      echo "# no bucket defined -- copy $1 to a bucket and configure it per the README.md";;
    ssh://git@*|git@*)
      echo "cp $1 metadata/expect.txt; (cd metadata; git commit expect.txt -m 'Updating expect'; git push)";;
    gs://*)
      echo gsutil cp -Z $1 $(project_file_path expect.txt);;
    *://*)
      echo "# command to publish $1 is not known. URL: $(project_file_path expect.txt)";;
    *)
      if [ "$2" = new ]; then
        cmd="git add $bucket/$project || echo '... you want to ensure $1 is added to your repository...'"
        case $(realpath --relative-base="$bucket" "$1") in
          /*)
            cmd="cp $1 $(project_file_path expect.txt); $cmd";;
        esac
        echo "$cmd"
      fi
      ;;
  esac
}

remove_items() {
  if to_boolean "$INPUT_ONLY_CHECK_CHANGED_FILES"; then
    echo "<!-- Because only_check_changed_files is active, checking for obsolete items cannot be performed-->"
  else
    if [ -z "$patch_remove" ]; then
      patch_remove=$(perl -ne 'next unless s/^-([^-])/$1/; s/\n/ /; print' "$diff_output")
    fi
    if [ -n "$patch_remove" ]; then
      echo "
        <details><summary>Previously acknowledged words that are now absent
        </summary>$patch_remove</details>
      " | strip_lead_and_blanks
      remove_words=$data_dir/remove_words.txt
      echo "$patch_remove" > $remove_words
      echo "::set-output name=stale_words::$remove_words" >> $output_variables
    else
      rm "$fewer_misspellings_canary"
    fi
  fi
}

get_action_log_overview() {
  echo "$GITHUB_SERVER_URL/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID"
}

get_has_errors() {
  if jq -r 'keys | .[]' "$counter_summary_file" | grep -E -v "$warnings_list" | grep -q .; then
    has_errors=1
  fi
}

get_action_log() {
  if [ -z "$action_log" ]; then
    if [ -s "$action_log_ref" ]; then
      action_log="$(cat $action_log_ref)"
    else
      action_log=$(get_action_log_overview)

      run_info=$(mktemp)
      if call_curl "$GITHUB_API_URL/repos/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID" > "$run_info" 2>/dev/null; then
        jobs_url=$(jq -r '.jobs_url // empty' "$run_info")
        if [ -n "$jobs_url" ]; then
          jobs_info=$(mktemp)
          if call_curl "$jobs_url" > "$jobs_info" 2>/dev/null; then
            job=$(mktemp)
            jq -r '.jobs[] | select(.status=="in_progress" and .runner_name=="'"$RUNNER_NAME"'" and .run_attempt=='"${GITHUB_RUN_ATTEMPT:-1}"')' "$jobs_info" > "$job" 2>/dev/null
            job_log=$(jq -r .html_url "$job")
            if [ -n "$job_log" ]; then
              step_info=$(mktemp)
              jq -r '.steps[] | select(.status=="pending") // empty' "$job" > "$step_info" 2>/dev/null
              if [ ! -s "$step_info" ]; then
                jq -r '.steps[] | select(.status=="queued" and .name=="check-spelling")' "$job" > "$step_info" 2>/dev/null
              fi
              step_number=$(jq -s -r .[0].number "$step_info")
              action_log="$job_log#step:$step_number:1"
            fi
          fi
        fi

      fi
      echo "$action_log" > "$action_log_ref"
    fi
  fi
  echo "$action_log"
}

spelling_warning() {
  OUTPUT="### :red_circle: $1
"
  spelling_body "$2" "$3" "$4"
  post_commit_comment
}
spelling_info() {
  if [ -z "$2" ]; then
    out="$1"
  else
    out="$1

$2"
  fi
  spelling_body "$out" "" "$3"
  if [ -n "$VERBOSE" ]; then
    OUTPUT="#$report_header

$OUTPUT"
    post_commit_comment
  else
    echo "$OUTPUT"
  fi
}
spelling_body() {
  message="$1"
  extra="$2"
  err="$3"
  case "$GITHUB_EVENT_NAME" in
    pull_request|pull_request_target)
      details_note="See the [:open_file_folder: files]($(jq -r .pull_request.number "$GITHUB_EVENT_PATH")/files/) view or the [:scroll:action log]($(get_action_log)) for details.";;
    push)
      details_note="See the [:scroll:action log]($(get_action_log)) for details.";;
    *)
      details_note=$(echo '<!-- If you can see this, please [file a bug](https://github.com/check-spelling/check-spelling/issues/new)
        referencing this comment url, as the code does not expect this to happen. -->' | strip_lead);;
  esac
  if [ -z "$err" ] && [ -e "$fewer_misspellings_canary" ]; then
    output_remove_items="$N$(remove_items)"
  fi
    if [ -n "$err" ] && [ -e "$fewer_misspellings_canary" ]; then
      cleanup_text=" (and remove the previously acknowledged and now absent words)"
    fi
    if [ "$GITHUB_EVENT_NAME" = "pull_request_target" ] || [ "$GITHUB_EVENT_NAME" = "pull_request" ]; then
      if [ -z "$GITHUB_HEAD_REF" ]; then
        GITHUB_HEAD_REF=$(jq -r '.pull_request.head.ref // empty' $GITHUB_EVENT_PATH)
      fi
    fi
    if [ -n "$GITHUB_HEAD_REF" ]; then
      remote_url_ssh=$(jq -r '.pull_request.head.repo.ssh_url // empty' $GITHUB_EVENT_PATH)
      remote_url_https=$(jq -r '.pull_request.head.repo.clone_url // empty' $GITHUB_EVENT_PATH)
      if should_patch_head; then
        remote_ref="$GITHUB_HEAD_REF"
      else
        remote_ref="$GITHUB_BASE_REF"
      fi
    else
      remote_url_ssh=$(jq -r '.repository.ssh_url // empty' $GITHUB_EVENT_PATH)
      remote_url_https=$(jq -r '.repository.clone_url // empty' $GITHUB_EVENT_PATH)
      remote_ref=$GITHUB_REF
    fi
    if [ -z "$remote_url_ssh" ]; then
      remote_url_ssh=$(git remote get-url --push origin 2>/dev/null || true)
    fi
    if [ -z "$remote_url_https" ]; then
      remote_url_https=$(echo "$remote_url_ssh" | perl -pe 's{(?:git\@|^)github\.com:}{https://github.com/}')
    fi
    if [ -z "$remote_ref" ]; then
      remote_ref=$(perl -pe 's{^ref: }{}' .git/HEAD)
    fi
    remote_ref=${remote_ref#refs/heads/}
    if [ -s "$extra_dictionaries_cover_entries" ]; then
      expected_item_count=$(wc -l $expect_path|sed -e 's/ .*//')
      if [ $expected_item_count -gt 0 ]; then
        expect_details="This includes both **expected items** ($expected_item_count) from $expect_files and **unrecognized words** ($unknown_count)
        "
      fi

      extra_dictionaries_cover_entries_limited=$(mktemp)
      head -$extra_dictionary_limit "$extra_dictionaries_cover_entries" > "$extra_dictionaries_cover_entries_limited"
      workflow_path=$(get_workflow_path)
      if [ -n "$workflow_path" ]; then
        workflow_path_hint=" (in $b$(get_workflow_path)$b)"
      fi
      output_dictionaries="$(echo "
        <details><summary>Available dictionaries could cover words not in the dictionary</summary>

        $expect_details
        $(cat "$extra_dictionaries_cover_entries_limited")

        Consider adding them using$workflow_path_hint:
        $B yml
              with:
                extra_dictionaries:$n$(
          cat "$extra_dictionaries_cover_entries_limited" |
          perl -pe 's/\s.*//;s/^/                  /;s{\[(.*)\]\(.*}{$1}'
        )
        $B
        To stop checking additional dictionaries, add:
        $B yml
              with:
                check_extra_dictionaries: ''
        $B

        </details>
        " | perl -pe 's/^ {8}//')"
    fi
    if [ -s "$should_exclude_file" ]; then
      calculate_exclude_patterns
      echo "::set-output name=skipped_files::$should_exclude_file" >> $output_variables
      output_excludes="$(echo "
        <details><summary>Some files were automatically ignored</summary>

        These sample patterns would exclude them:
        $B
        $should_exclude_patterns
        $B"| strip_lead)"
      if [ $(wc -l "$should_exclude_file" |perl -pe 's/(\d+)\s+.*/$1/') -gt 10 ]; then
        output_excludes_large="$(echo "
          "'You should consider excluding directory paths (e.g. `(?:^|/)vendor/`), filenames (e.g. `(?:^|/)yarn\.lock$`), or file extensions (e.g. `\.gz$`)
          '| strip_lead)"
      fi
      output_excludes_suffix="$(echo "

        You should consider adding them to:
        $B$n" | strip_lead

        )$n$(echo "$excludes_files" |
        xargs -n1 echo)$n$B$(echo '

        File matching is via Perl regular expressions.

        To check these files, more of their words need to be in the dictionary than not. You can use `patterns.txt` to exclude portions, add items to the dictionary (e.g. by adding them to `allow.txt`), or fix typos.
        </details>
      ' | strip_lead)"
    fi
    if [ -s "$counter_summary_file" ]; then
      get_has_errors
      if [ -n "$has_errors" ]; then
        event_title='Errors'
        event_icon=':x:'
      else
        event_title='Warnings'
        event_icon=':information_source:'
      fi
      warnings_details="$(echo "
        [$event_icon ${event_title}](https://github.com/check-spelling/check-spelling/wiki/Event-descriptions) | Count
        -|-
        $(jq -r 'to_entries[] | "[:information_source: \(.key)](https://github.com/check-spelling/check-spelling/wiki/Event-descriptions#\(.key)) | \(.value)"' "$counter_summary_file" | WARNINGS_LIST="$warnings_list" perl -pe 'next if /$ENV{WARNINGS_LIST}/; s/information_source/x/')

        See [$event_icon Event descriptions](https://github.com/check-spelling/check-spelling/wiki/Event-descriptions) for more information.
        " | strip_lead)"
      if [ -n "$has_errors" ] && [ -z "$message" ]; then
        message="$warnings_details"
      else
        output_warnings="$(echo "
        <details><summary>$event_title ($(grep -c ':' "$counter_summary_file"))</summary>

        $details_note

        $warnings_details
        </details>
        " | strip_lead)"
      fi
    fi
    if [ -n "$err" ]; then
      output_accept_script="$(echo "
        <details><summary>To accept :heavy_check_mark: these unrecognized words as correct$cleanup_text,
        run the following commands</summary>

        ... in a clone of the [$remote_url_ssh]($remote_url_https) repository
        on the $b$remote_ref$b branch ([:information_source: how do I use this?](
        https://github.com/check-spelling/check-spelling/wiki/Accepting-Suggestions)):
        "$(relative_note)"

        $B sh
        $err
        $B
        </details>
        " | strip_lead)"
      if [ -s "$advice_path" ]; then
        output_advice="$N"`cat "$advice_path"`"$n"
      fi
    fi
    if offer_quote_reply; then
      output_quote_reply_placeholder="$n<!--QUOTE_REPLY-->$n"
    fi
    OUTPUT=$(echo "$n$report_header$n$OUTPUT$details_note$N$message$extra$output_remove_items$output_excludes$output_excludes_large$output_excludes_suffix$output_accept_script$output_quote_reply_placeholder$output_dictionaries$output_warnings$output_advice
      " | perl -pe 's/^\s+$/\n/;'| uniq)
}

quit() {
  echo "::remove-matcher owner=check-spelling::"
  status="$1"
  if ([ -z "$status" ] || [ "$status" -eq 0 ]) && [ -n "$has_errors" ]; then
    status=1
  fi
  case "$status" in
    0) followup='';;
    1) followup='comment';;
    2) followup='debug';;
    3) followup='collapse_previous_comment';;
  esac
  echo "::set-output name=result_code::$status"
  echo "::set-output name=followup::$followup"
  echo "$followup" > "$data_dir/followup"
  echo "result_code=$status" >> "$GITHUB_ENV"
  cat $output_variables
  if ls "$data_dir" | grep -q .; then
    artifact=$(mktemp)
    (
      cd "$data_dir"
      zip -q "$artifact.zip" *
      rm *
      mv "$artifact.zip" 'artifact.zip'
    )
  fi
  if to_boolean "$quit_without_error"; then
    exit
  fi
  exit $status
}

body_to_payload() {
  BODY="$1"
  PAYLOAD=$(mktemp)
  echo '{}' | jq --rawfile body "$BODY" '.body = $body' > $PAYLOAD
  if to_boolean "$DEBUG"; then
    cat $PAYLOAD >&2
  fi
}

collaborator() {
  collaborator_url="$1"
  call_curl -L \
    -H "Accept: application/vnd.github.v3+json" \
    "$collaborator_url" 2> /dev/null
}

pull_request() {
  pull_request_url="$1"
  call_curl -L -S \
    -H "Content-Type: application/json" \
    "$pull_request_url"
}

react() {
  url="$1"
  reaction="$2"
  call_curl -L -S \
    -X POST \
    -H "Accept: application/vnd.github.squirrel-girl-preview+json" \
    "$url"/reactions \
    -d '{"content":"'"$reaction"'"}'
}

unlock_pr() {
  pr_locked="$(jq -r .pull_request.locked "$GITHUB_EVENT_PATH")"
  if to_boolean "$pr_locked"; then
    locked_pull_url="$(jq -r .pull_request._links.issue.href "$GITHUB_EVENT_PATH")"/lock
    call_curl -L -S \
      -X DELETE \
      -H "Accept: application/vnd.github.v3+json" \
      "$locked_pull_url"
  fi
}

lock_pr() {
  if to_boolean "$pr_locked"; then
    lock_reason="$(jq -r '.pull_request.active_lock_reason // ""' "$GITHUB_EVENT_PATH")"
    if [ -n "$lock_reason" ]; then
      lock_method=-d
      lock_data='{"lock_reason":"'"$lock_reason"'"}'
    else
      lock_method=-H
      lock_data='Content-Length: 0'
    fi
    call_curl -L -S \
      -X PUT \
      -H "Accept: application/vnd.github.v3+json" \
      "$lock_method" "$lock_data" \
      "$locked_pull_url"
  fi
}

comment() {
  comments_url="$1"
  payload="$2"
  if [ -n "$payload" ]; then
    payload="--data @$payload"
    method="$3"
    if [ -n "$method" ]; then
      method="-X $method"
    fi
  fi
  call_curl -L -S \
    $method \
    -H "Content-Type: application/json" \
    -H 'Accept: application/vnd.github.comfort-fade-preview+json' \
    $payload \
    "$comments_url"
}

track_comment() {
  HTML_COMMENT_URL=$(jq -r '.html_url // empty' $response)
  echo "Comment posted to ${HTML_COMMENT_URL:-$COMMENT_URL}"
  comment_author_id="$(jq -r '.user.id // empty' "$response")"
  posted_comment_node_id="$(jq -r '.node_id // empty' "$response")"
}

comment_url_to_html_url() {
  comment "$1" | jq -r ".html_url // $Q$1$Q"
}

set_comments_url() {
  event="$1"
  file="$2"
  sha="$3"
  case "$event" in
    issue_comment)
      COMMENTS_URL=$(jq -r '.issue.comments_url // empty' "$file");;
    pull_request|pull_request_target|pull_request_review_comment)
      COMMENTS_URL=$(jq -r '.pull_request.comments_url // empty' "$file");;
    push|commit_comment)
      COMMENTS_URL=$(jq -r '.repository.commits_url // empty' "$file" | perl -pe 's#\{/sha}#/'$sha'/comments#');;
  esac
}

file_size() {
  perl -e '@x=stat(shift);print $x[7]' "$1"
}

trim_commit_comment() {
  stripped=$(mktemp)
  (perl -p -i.raw -e '$/=undef; s{'"$2"'}{$1'"$3"'_Truncated, please see the log or artifact if available._\n}s; my $capture=$2; my $overview=q<'"$(get_action_log_overview)"'>; s{\n(See the) (\[action log\])}{\n$1 [overview]($overview) or $2}s unless m{\Q$overview\E}; print STDERR "$capture\n"' "$BODY") 2> "$stripped"
  body_to_payload "$BODY"
  previous_payload_size="$payload_size"
  payload_size=$(file_size "$PAYLOAD")
  if [ "$payload_size" -lt "$previous_payload_size" ]; then
    echo "::warning ::Comment payload ($previous_payload_size) is likely to exceed GitHub size limit ($github_comment_size_limit) -- trimming: $1 (=>$payload_size)"
    cat "$stripped"
    rm "$stripped"
  elif ! diff -q "$BODY.raw" "$BODY" > /dev/null; then
    echo "Trimming $1 did not reduce the payload size ($previous_payload_size => $payload_size)"
    cp "$BODY.raw" "$BODY"
    payload_size="$previous_payload_size"
  fi
}

minimize_comment_body() {
  if [ $payload_size -le $github_comment_size_limit ]; then
    return 0
  fi
  trim_commit_comment 'Script' '(<details><summary>)To accept these unrecognized.*?</summary>().*?(?=</details>\n)' 'Script unavailable</summary>\n\n'
  if [ $payload_size -le $github_comment_size_limit ]; then
    return 0
  fi
  trim_commit_comment 'Stale words' '(<details><summary>Previously acknowledged words that are now absent.*?</summary>)(.*?)(?=</details>)' '\n\n'
  if [ $payload_size -le $github_comment_size_limit ]; then
    return 0
  fi
  trim_commit_comment 'Available dictionaries' '(<details><summary>Available dictionaries.*?</summary>\n*)(.*?)(?=</details>)' ''
  if [ $payload_size -le $github_comment_size_limit ]; then
    return 0
  fi
  trim_commit_comment 'Unrecognized words' '(<details><summary>Unrecognized words.*?</summary>\n*)\`\`\`(.*?)\`\`\`'
  if [ $payload_size -le $github_comment_size_limit ]; then
    return 0
  fi
  trim_commit_comment 'Files' '(<details><summary>Some files were automatically ignored</summary>)\n.*?\`\`\`(.*?)\`\`\`.*?(?=</details>)' '\n\n'
  if [ $payload_size -le $github_comment_size_limit ]; then
    return 0
  fi
  trim_commit_comment '' '(\nSee the [^\n]*\n)(.*)$' '\n\n'
  if [ $payload_size -le $github_comment_size_limit ]; then
    return 0
  fi
  cat "$BODY"
  body_to_payload "$BODY"
  echo "::warning ::Truncated comment payload ($payload_size) is likely to exceed GitHub size limit ($github_comment_size_limit)"
}

post_commit_comment() {
  if [ -n "$OUTPUT" ]; then
    if to_boolean "$INPUT_POST_COMMENT"; then
      echo "Preparing a comment for $GITHUB_EVENT_NAME"
      set_comments_url "$GITHUB_EVENT_NAME" "$GITHUB_EVENT_PATH" "$GITHUB_SHA"
      if [ -n "$COMMENTS_URL" ] && [ -z "${COMMENTS_URL##*:*}" ]; then
        BODY=$(mktemp)
        echo "$OUTPUT" > "$BODY"
        body_to_payload "$BODY"
        payload_size=$(file_size "$PAYLOAD")
        github_comment_size_limit=65000
        minimize_comment_body
        response=$(mktemp_json)

        res=0
        unlock_pr
        keep_headers=1 comment "$COMMENTS_URL" "$PAYLOAD" > "$response"
        if [ -z "$response_code" ] || [ "$response_code" -ge 400 ] 2> /dev/null; then
          if ! to_boolean "$DEBUG"; then
            echo "::error ::Failed posting to $COMMENTS_URL"
            cat "$PAYLOAD"
            echo " -- response -- "
            echo "Response code: $response_code"
            echo "Headers:"
            cat "$response_headers"
            rm -f "$response_headers"
            echo "Body:"
            cat "$response"
            echo " //// "
          fi
          no_patch=1
        else
          if to_boolean "$DEBUG"; then
            cat "$response"
          fi
          COMMENT_URL=$(jq -r '.url // empty' "$response")
          if [ -z "$COMMENT_URL" ]; then
            echo "Could not find comment url in:"
            cat "$response"
            no_patch=1
          else
            perl -p -i.orig -e 's<COMMENT_URL><'"$COMMENT_URL"'>' "$BODY"
            if diff -q "$BODY.orig" "$BODY" > /dev/null; then
              no_patch=1
            fi
            rm "$BODY.orig"
          fi
          if [ -n "$COMMENT_URL" ]; then
            if offer_quote_reply; then
              quote_reply_insertion=$(mktemp)
              (
                if [ -n "$INPUT_REPORT_TITLE_SUFFIX" ]; then
                  apply_changes_suffix=" $INPUT_REPORT_TITLE_SUFFIX"
                fi
                echo
                echo "To have the bot do this for you, reply quoting the following line:"
                echo "@check-spelling-bot apply [changes]($(comment_url_to_html_url $COMMENT_URL))$apply_changes_suffix."
              )> "$quote_reply_insertion"
              perl -e '$/=undef; my ($insertion, $body) = @ARGV; open INSERTION, "<", $insertion; my $text = <INSERTION>; close INSERTION; open BODY, "<", $body; my $content=<BODY>; close BODY; $content =~ s/<!--QUOTE_REPLY-->/$text/; open BODY, ">", $body; print BODY $content; close BODY;' "$quote_reply_insertion" "$BODY"
              no_patch=
            fi
            if [ -z "$no_patch" ]; then
              body_to_payload $BODY
              comment "$COMMENT_URL" "$PAYLOAD" "PATCH" > $response || res=$?
              if [ $res -gt 0 ]; then
                if ! to_boolean "$DEBUG"; then
                  echo "Failed to patch $COMMENT_URL"
                fi
              fi
              if to_boolean "$DEBUG"; then
                cat $response
              fi
            fi
            rm -f $BODY 2>/dev/null
            track_comment "$response"
          else
            cat "$BODY"
          fi
          lock_pr
        fi
      else
        echo "$OUTPUT"
      fi
    else
      echo "$OUTPUT"
    fi
  fi
}

strip_lines() {
  tr "\n" " "
}

minimize_comment_call() {
  comment_node="$1"
  echo "
      minimizeComment(
      input:
      {
        subjectId: ${Q}$comment_node${Q},
        classifier: ${reason:-RESOLVED}
      }
    ){
      minimizedComment {
        isMinimized
      }
    }
" | strip_lead | strip_lines
}

collapse_comment_mutation() {
  comment_node="$1"
  query_head="mutation {"
  query_tail="}"
  query_body=""
  i=0
  while [ -n "$1" ]; do
    query_body="$query_body q$i: "$(minimize_comment_call "$1")
    i="$((i+1))"
    shift
  done
  query="$query_head$query_body$query_tail"
  echo '{}' | jq --arg query "$query" '.query = $query'
}

collapse_comment() {
  call_curl \
  -H "Content-Type: application/json" \
  --data-binary "$(collapse_comment_mutation "$@")" \
  $GITHUB_GRAPHQL_URL
}

should_collapse_previous_and_not_comment() {
  if [ -z "$COMMENTS_URL" ]; then
    set_comments_url "$GITHUB_EVENT_NAME" "$GITHUB_EVENT_PATH" "$GITHUB_SHA"
  fi
  previous_comment_node_id=$(get_previous_comment)
  if [ -n "$previous_comment_node_id" ]; then
    echo "::set-output name=previous_comment::$previous_comment_node_id"
    echo "$previous_comment_node_id" > "$data_dir/previous_comment.txt"
    quit_without_error=1
    quit 3
  fi
}

exit_if_no_unknown_words() {
  if [ -s "$counter_summary_file" ]; then
    get_has_errors
  fi
  if [ -z "$has_errors" ] && [ ! -s "$run_output" ]; then
    should_collapse_previous_and_not_comment
    quit 0
  fi
}

grep_v_spellchecker() {
  grep_v_string "$spellchecker"
}

grep_v_string() {
  perl -ne "next if m{$1}; print"
}

compare_new_output() {
  begin_group 'Compare expect with new output'
    sorted_expect="$temp/expect.sorted.txt"
    (sed -e 's/#.*//' "$expect_path" | sort_unique) > "$sorted_expect"
    expect_path="$sorted_expect"

    diff -w -U0 "$expect_path" "$run_output" |
      grep_v_spellchecker > "$diff_output"
  end_group
}

generate_curl_instructions() {
  has_instructions_canary=$(mktemp)
  calculate_exclude_patterns
  instructions=$(mktemp)
  (
    echo 'update_files() {'
    (
      skip_wrapping=1
      if [ -n "$patch_remove" ]; then
        patch_remove='$patch_remove'
      fi
      if [ -n "$patch_add" ]; then
        patch_add='$patch_add'
      fi
      if [ -n "$should_exclude_patterns" ]; then
        should_exclude_patterns='$should_exclude_patterns'
      fi
      generated=$(generate_instructions)
      if [ -s "$generated" ]; then
        cat "$generated"
      else
        rm "$has_instructions_canary"
      fi
      rm "$generated"
    )
    echo '}'
  ) >> "$instructions"
  if [ -e "$has_instructions_canary" ]; then
    echo '
      comment_json=$(mktemp)
      curl -L -s -S \
        -H "Content-Type: application/json" \
        "COMMENT_URL" > "$comment_json"
      comment_body=$(mktemp)
      jq -r ".body // empty" "$comment_json" | tr -d "\\r" > $comment_body
      rm $comment_json
      '"$(patch_variables $Q'$comment_body'$Q)"'
      update_files
      rm $comment_body
      git add -u
      ' | sed -e 's/^    //' >> "$instructions"
    echo "$instructions"
    rm "$has_instructions_canary"
  else
    rm "$instructions"
  fi
}

skip_curl() {
  [ -n "$SKIP_CURL" ] || repo_is_private
}

set_patch_remove_add() {
  patch_remove=$(perl -ne 'next unless s/^-([^-])/$1/; s/\n/ /; print' "$diff_output")
  begin_group 'New output'
    patch_add=$(perl -ne 'next unless s/^\+([^+])/$1/; s/\n/ /; print' "$diff_output")

    if [ -z "$patch_add" ]; then
      begin_group 'No misspellings'
      title="No new words with misspellings found"
        spelling_info "$title" "There are currently $(wc -l $expect_path|sed -e 's/ .*//') expected items." ""
      end_group
      should_collapse_previous_and_not_comment
      quit 0
    fi
  end_group
}

make_instructions() {
  if skip_curl; then
    instructions=$(generate_instructions)
    if [ -n "$patch_add" ]; then
      to_publish_expect "$new_expect_file" $new_expect_file_new >> $instructions
    fi
  else
    instructions=$(generate_curl_instructions)
  fi
  if [ -n "$instructions" ]; then
    cat $instructions
    rm $instructions
  fi
}

fewer_misspellings() {
  begin_group 'Fewer misspellings'
  title='There are now fewer misspellings than before'
  SKIP_CURL=1
  if [ -n "$INPUT_EXPERIMENTAL_COMMIT_NOTE" ]; then
    skip_push_and_pop=1

    instructions_head=$(mktemp)
    (
      patch_add=1
      patch_remove=1
      should_exclude_patterns=1
      patch_variables $comment_body > $instructions_head
    )
    . $instructions_head
    rm $instructions_head
    instructions=$(generate_instructions)

    . $instructions &&
    git_commit "$INPUT_EXPERIMENTAL_COMMIT_NOTE" &&
    git push origin ${GITHUB_HEAD_REF:-$GITHUB_REF}
    spelling_info "$title" "" "Applied"
  else
    instructions=$(
      make_instructions
    )
    spelling_info "$title" "" "$instructions"
  fi
  end_group
  should_collapse_previous_and_not_comment
  quit
}
more_misspellings() {
  if [ -s "$extra_dictionaries_json" ]; then
    build_dictionary_alias_pattern
    jq -r '.[]|keys[] as $k | "\($k)<\($k)> (\(.[$k][1])) covers \(.[$k][0]) of them"' $extra_dictionaries_json | perl -pe "$dictionary_alias_pattern"'s{^([^<]*)<([^>]*)>}{[$2]($1)};' > "$extra_dictionaries_cover_entries"
  elif [ -z "$INPUT_TASK" ] || [ "$INPUT_TASK" = 'spelling' ]; then
    if [ ! -s "$extra_dictionaries_json" ]; then
      if [ -n "$check_extra_dictionaries_dir" ]; then
        begin_group 'Check for extra dictionaries'
        (
          cd "$check_extra_dictionaries_dir";
          aliases="$dictionary_alias_pattern" extra_dictionaries="$check_extra_dictionaries" $spellchecker/dictionary-coverage.pl "$run_output" |
          sort -nr |
          perl -pe 's/^\d+ //' > "$extra_dictionaries_cover_entries"
        )
        end_group
      fi
    fi
  fi
  if [ -s "$extra_dictionaries_cover_entries" ]; then
    perl -pe 's/^.*?\[(\S+)\]\([^)]*\) \((\d+)\).* covers (\d+).*/{"$1":[$3, $2]}/' < "$extra_dictionaries_cover_entries" |
    jq -s '.' > $extra_dictionaries_json
    echo "::set-output name=suggested_dictionaries::$extra_dictionaries_json" >> $output_variables
  fi

  instructions=$(
    make_instructions
  )
  (echo "$patch_add" | tr " " "\n" | grep . || true) > "$tokens_file"
  unknown_count=$(cat "$tokens_file" | wc -l | strip_lead)
  title='Please review'
  begin_group "Unrecognized ($unknown_count)"
  echo "::set-output name=unknown_words::$tokens_file" >> $output_variables
  if [ "$unknown_count" -eq 0 ]; then
    unknown_word_body=''
  else
    unrecognized_words_title="Unrecognized words ($unknown_count)"
    if [ "$unknown_count" -gt 10 ]; then
      unknown_word_body="$n<details><summary>$unrecognized_words_title</summary>

$B
$(cat "$tokens_file")
$B
</details>"
    else
      unknown_word_body="$n#### $unrecognized_words_title$N$(cat "$tokens_file")"
    fi
  fi
  spelling_warning "$title" "$unknown_word_body" "$N$(remove_items)$n" "$instructions"
  end_group
  echo "$title"
  if [ -n "$comment_author_id" ]; then
    previous_comment_node_id=$(get_previous_comment)
    if [ -n "$previous_comment_node_id" ]; then
      reason=OUTDATED collapse_comment "$previous_comment_node_id" > /dev/null
    fi
  fi

  quit 1
}

set_up_reporter
set_up_tools
define_variables
dispatcher
set_up_files
welcome
run_spell_check
exit_if_no_unknown_words
compare_new_output
fewer_misspellings_canary=$(mktemp)
set_patch_remove_add
if [ -z "$patch_add" ]; then
  fewer_misspellings
fi
more_misspellings
cat $output_variables
