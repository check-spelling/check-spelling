#!/bin/bash
# This CI acceptance test is based on:
# https://github.com/jsoref/spelling/tree/04648bdc63723e5cdf5cbeaff2225a462807abc8
# It is conceptually `f` which runs `w` (spelling-unknown-word-splitter)
# plus `fchurn` which uses `dn` mostly rolled together.
set -e
export spellchecker="${spellchecker:-$THIS_ACTION_PATH}"

basic_setup() {
  if [ "$(id -u)" != 0 ]; then
    SUDO=sudo
  fi
  $SUDO "$spellchecker/fast-install.pl"

  . "$spellchecker/common.sh"
}

dispatcher() {
  if [ -n "$INPUT_EVENT_ALIASES" ]; then
    GITHUB_EVENT_NAME="$(echo "$INPUT_EVENT_ALIASES" | jq -r ".$GITHUB_EVENT_NAME // $Q$GITHUB_EVENT_NAME$Q")"
  fi
  INPUT_TASK="${INPUT_TASK:-"$INPUT_CUSTOM_TASK"}"
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
        echo 'It could be because you are using `act` or a similar GitHub Runner shim,'
        echo 'and its configuration is incorrect.'
      ) >&2
      github_step_summary_likely_fatal \
        'GITHUB_EVENT_NAME is empty' \
        'Please see the log for more information.' \
        'Is `event_aliases` misconfigured? Are you using `act` or a similar shim?'
      exit 1
      ;;
    push)
      if to_boolean "$INPUT_SUPPRESS_PUSH_FOR_OPEN_PULL_REQUEST" && ! echo "$GITHUB_REPOSITORY" | grep -q '^..*/..*$'; then
        (
          echo '$GITHUB_REPOSITORY '"($GITHUB_REPOSITORY) does not appear to be an OWNER/REPOSITORY"
          if [ -n "$ACT" ]; then
            echo '[act] `git remote -v origin` is probably misconfigured'
          fi
          echo 'Cannot determine if there is an open pull request, proceeding as if there is not.'
        ) >&2
      elif to_boolean "$INPUT_SUPPRESS_PUSH_FOR_OPEN_PULL_REQUEST"; then
        pull_request_json="$(mktemp_json)"
        pull_request_headers="$(mktemp)"
        pull_heads_query="$GITHUB_API_URL/repos/$GITHUB_REPOSITORY/pulls?head=${GITHUB_REPOSITORY%/*}:$GITHUB_REF"
        keep_headers=1 call_curl \
          "$pull_heads_query" > "$pull_request_json"
        mv "$response_headers" "$pull_request_headers"
        if [ -n "$(jq .documentation_url "$pull_request_json" 2>/dev/null)" ]; then
          (
            echo "Request for '$pull_heads_query' appears to have yielded an error, it is probably an authentication error."
            if [ -n "$ACT" ]; then
              echo '[act] If you want to use suppress_push_for_open_pull_request, you need to set GITHUB_TOKEN'
            fi
            echo "Headers:"
            cat "$pull_request_headers"
            echo "Response:"
            cat "$pull_request_json"
            echo 'Cannot determine if there is an open pull request, proceeding as if there is not.'
          ) >&2
        elif [ "$(jq length "$pull_request_json")" -gt 0 ]; then
          (
            open_pr_number="$(jq -r '.[0].number' "$pull_request_json")"
            echo "Found [open PR #$open_pr_number]($GITHUB_SERVER_URL/$GITHUB_REPOSITORY/pull/$open_pr_number) - check-spelling should run there."
            echo
            echo '::warning title=WARNING: Skipped check-spelling::This workflow is intentionally terminating early with a success code -- it has not checked for misspellings.'
            pull_request_event_name=pull_request_target
            if [ -n "$workflow_path" ]; then
              if ! grep -q pull_request_target "$workflow_path" && grep -q pull_request "$workflow_path"; then
                pull_request_event_name=pull_request
              fi
              workflow="workflow (${b}$workflow_path${b})"
            else
              workflow='workflow'
            fi
            echo "::notice title=Workflow skipped::See ${b}check-spelling${b} ${b}$pull_request_event_name${b} $workflow in PR #$open_pr_number. $GITHUB_SERVER_URL/$GITHUB_REPOSITORY/pull/$open_pr_number/checks"
            echo "# ⏭️ Workflow skipped$n${n}See ${b}check-spelling${b} ${b}$pull_request_event_name${b} $workflow in PR #$open_pr_number.$n$n$GITHUB_SERVER_URL/$GITHUB_REPOSITORY/pull/$open_pr_number/checks" >> "$GITHUB_STEP_SUMMARY"
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
      if [ "$INPUT_TASK" = spelling ] && [ "$(are_head_and_base_in_same_repo "$GITHUB_EVENT_PATH" '.pull_request')" != 'true' ]; then
        api_output=$(mktemp)
        api_error=$(mktemp)
        GH_TOKEN="$GITHUB_TOKEN" gh api --method POST -H "Accept: application/vnd.github+json" "$GITHUB_API_URL/repos/$GITHUB_REPOSITORY/branches/${GITHUB_BASE_REF:-$GITHUB_REF_NAME}/rename" > "$api_output" 2> "$api_error" || true
        if ! grep -Eq 'not authorized|not accessible' "$api_output"; then
          if to_boolean "$INPUT_USE_SARIF"; then
            INPUT_USE_SARIF=
            set_up_reporter
          fi
          echo '::error title=Unsafe Permissions: check-spelling::This workflow configuration is unsafe. Please see https://github.com/check-spelling/check-spelling/wiki/Feature:-Restricted-Permissions'
          github_step_summary_likely_fatal \
            'Unsafe Permissions' \
            'This workflow configuration is unsafe.' \
            ':information_source: Please see https://github.com/check-spelling/check-spelling/wiki/Feature:-Restricted-Permissions'
          quit 5
        fi
      fi
      ;;
    schedule)
      export GH_TOKEN="$GITHUB_TOKEN"
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
      body="$(echo '
        If you are trying to ask @check-spelling-bot to update a PR,
        please quote the comment link as a top level comment instead
        of in a comment on a block of code.

        Future versions may support this feature.
        For the time being, early adopters should remove the
        `pull_request_review_comment` event from their workflow.
        workflow.
      ' | strip_lead)"
      ( echo 'check-spelling does not currently support comments on code.
        '"$body" \
        | strip_lead
      ) >&2
      github_step_summary_likely_fatal_event 'Handling comments on code is not supported by check-spelling' "$body" 'unsupported-configuration-review-comment'
      quit 0
      ;;
    *)
      body="$(echo "
          check-spelling does not currently support the GitHub $b$GITHUB_EVENT_NAME$b event.

          If you think it can, consider using:

            with:
              event_aliases: {$Q$GITHUB_EVENT_NAME$Q:${Q}supported_event_name${Q}}

          Future versions may support this feature." \
        | perl -pe 's/^ {10}//'
      )"
      echo "$body" >&2
      github_step_summary_likely_fatal_event 'Unsupported event name' "$body" 'unsupported-configuration-event'
      exit 1
      ;;
  esac
}

load_env() {
  input_variables="$(mktemp)"
  "$spellchecker/load-env.pl" > "$input_variables"
  . "$input_variables"
}

wrap_in_json() {
  echo '{}' | jq -r --arg arg "$2" ".$1="'$arg'
}

wrap_file_in_json() {
  echo '{}' | jq -r --rawfile arg "$2" ".$1="'$arg'
}

who_am_i() {
  who_am_i='query { viewer { databaseId } }'
  who_am_i_json="$(wrap_in_json 'query' "$who_am_i")"
  comment_author_id=$(
    call_curl \
    -H "Content-Type: application/json" \
    --data-binary "$who_am_i_json" \
    "$GITHUB_GRAPHQL_URL" |
    jq -r '.data.viewer.databaseId // empty'
  )
}

get_is_comment_minimized() {
  comment_is_collapsed_query="query { node(id:$Q$1$Q) { ... on IssueComment { minimizedReason } } }"
  comment_is_collapsed_json="$(wrap_in_json 'query' "$comment_is_collapsed_query")"
  call_curl \
  -H "Content-Type: application/json" \
  --data-binary "$comment_is_collapsed_json" \
  "$GITHUB_GRAPHQL_URL" |
  jq -r '.data.node.minimizedReason'
}

is_comment_minimized() {
  [ "$(get_is_comment_minimized "$1")" != "null" ]
}

get_previous_comment() {
  comment_search_re="$(title="$report_header" perl -e 'my $title=quotemeta($ENV{title}); $title=~ s/\\././g; print "(?:^|\n)$title";')"
  get_a_comment "$comment_search_re" | head -1
}

get_a_comment() {
  comment_search_re="$1"
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
    link="$(dir="$dir" perl -ne 'next unless s/^link:.*<([^>]*)>[^,]*$ENV{dir}.*/$1/; print' "$response_headers" )"
    if [ -n "$link" ] && [ "$dir" = "last" ]; then
      get_page "$link" "prev"
      return
    fi
    node_id="$(jq -r "$jq_comment_query" "$pr_comments")"
    if [ -n "$node_id" ]; then
      (
        echo "$node_id"
        get_is_comment_minimized "$node_id"
      )
      return
    fi
    if [ -n "$link" ]; then
      get_page "$link" "prev"
      return
    fi
  }

  pr_comments="$(mktemp_json)"
  get_page "$COMMENTS_URL" "last"
  rm "$pr_comments"
}

get_comment_url_from_id() {
  id="$1"
  comment_url_from_id_query="query { node(id:$Q$id$Q) { ... on IssueComment { url } } }"
  comment_url_from_id_json="$(wrap_in_json 'query' "$comment_url_from_id_query")"
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
      followup="$(cat "$INPUT_INTERNAL_STATE_DIRECTORY/followup")"
      if [ "$followup" = "collapse_previous_comment" ]; then
        previous_comment_node_id="$(cat "$data_dir/previous_comment.txt")"
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
        ls -d "$(dirname "$1")"/*/"$(basename "$1")" 2>/dev/null || echo "$1"
      fi
    }
    NEW_TOKENS="$(handle_mixed_archive "$NEW_TOKENS")"
    STALE_TOKENS="$(handle_mixed_archive "$STALE_TOKENS")"
    NEW_EXCLUDES="$(handle_mixed_archive "$NEW_EXCLUDES")"
    SUGGESTED_DICTIONARIES="$(handle_mixed_archive "$SUGGESTED_DICTIONARIES")"
  fi
  touch "$diff_output"

  if [ -f "$NEW_TOKENS" ]; then
    patch_add="$(cat "$NEW_TOKENS")"
  fi
  if [ -f "$STALE_TOKENS" ]; then
    patch_remove="$(cat "$STALE_TOKENS")"
  fi
  if [ -f "$NEW_EXCLUDES" ]; then
    cat "$NEW_EXCLUDES" > "$should_exclude_file"
  fi
  if [ -f "$SUGGESTED_DICTIONARIES" ]; then
    cat "$SUGGESTED_DICTIONARIES" > "$extra_dictionaries_json"
  fi
  fewer_misspellings_canary="$(mktemp)"
  quit_without_error=1
  get_has_errors
  if [ -z "$has_errors" ] && [ -z "$patch_add" ]; then
    quit
  fi
  check_spelling_report
}

get_pull_request_url() {
  jq -r '.pull_request.url // .issue.pull_request.url // empty' "$GITHUB_EVENT_PATH"
}

get_pr_sha_from_url() {
  pull_request_head_info="$(mktemp_json)"
  pull_request "$1" | jq -r ".head // empty" > "$pull_request_head_info"
  jq -r ".sha // empty" "$pull_request_head_info"
}

pr_head_sha_task() {
  pull_request_url="$(get_pull_request_url)"
  if [ -n "$pull_request_url" ]; then
    echo "PR_HEAD_SHA=$(get_pr_sha_from_url "$pull_request_url")" >> "$GITHUB_ENV"
  fi
  quit
}

get_action_repo_info() {
  workflow="$workflow_path" perl -e '
    exit if defined $ENV{ACT};
    exit unless $ENV{GITHUB_WORKSPACE} =~ m{(.*?)(?:/[^/]+){2}$};
    my $base = "$1/_actions/";
    exit unless $ENV{GITHUB_ACTION_PATH} =~ m{\Q$base\E(.*)};
    my @parts = split m{/}, $1;
    exit unless scalar @parts == 3;
    my $action = "$parts[0]/$parts[1]\@$parts[2]";
    exit unless open WORKFLOW, "<", $ENV{workflow };
    while (<WORKFLOW>) {
      next unless /^\s*uses:\s*\Q$action\E/;
      print $action;
      exit;
    }
  '
}

get_workflow_path() {
  if [ -s "$action_workflow_path_file" ]; then
    cat "$action_workflow_path_file"
  elif [ -e "$GITHUB_WORKFLOW" ]; then
    echo "$GITHUB_WORKFLOW" | tee "$action_workflow_path_file"
  else
    workflow_path_from_env=$(perl -e 'my $workflow = $ENV{GITHUB_WORKFLOW_REF}; $workflow =~ s!(?:[^/]+/){2}!!; $workflow =~ s!\@.*!!; print $workflow')
    if [ -e "$workflow_path_from_env" ]; then
      echo "$workflow_path_from_env" | tee "$action_workflow_path_file"
      return
    fi
    action_run="$(mktemp_json)"
    if call_curl \
      "$GITHUB_API_URL/repos/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID" > "$action_run"; then
      workflow_url="$(jq -r '.workflow_url // empty' "$action_run")"
      if [ -n "$workflow_url" ]; then
        workflow_json="$(mktemp_json)"
        if call_curl \
          "$workflow_url" > "$workflow_json"; then
          jq -r .path "$workflow_json" | tee "$action_workflow_path_file"
        fi
      else
        possible_workflows=$(mktemp)
        github_job_pattern="^\s\s*$GITHUB_JOB\s*:\s*$"
        if [ -n "$ACT" ]; then
          # https://github.com/nektos/act/issues/1473
          github_job_pattern="$github_job_pattern\|^\s\s*name\s*:\s*$GITHUB_JOB\s*$"
        fi
        find .github/workflows \( -name '*.yml' -o -name '*.yaml' \) -type f ! -empty -print0 |
          xargs -0 grep -l --null "^\s\s*uses\s*:\s*$GH_ACTION_REPOSITORY@$GH_ACTION_REF" |
          xargs -0 grep -l --null "^name\s*:\s*$GITHUB_WORKFLOW\s*$" |
          xargs -0 grep -l --null "$github_job_pattern" > "$possible_workflows"
        if [ "$(tr -cd '\000' < "$possible_workflows" | char_count)" -eq 1 ]; then
          xargs -0 < "$possible_workflows" | tee "$action_workflow_path_file"
        fi
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
    pull_request_url="$(get_pull_request_url)"
    if [ -z "$pull_request_url" ]; then
      false
    else
      pull_request_sha="$(get_pr_sha_from_url "$pull_request_url")"
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
    return "$offer_quote_reply_cached"
  fi
  if to_boolean "$INPUT_EXPERIMENTAL_APPLY_CHANGES_VIA_BOT"; then
    case "$GITHUB_EVENT_NAME" in
      issue_comment)
        issue="$(mktemp_json)"
        pull_request_info="$(mktemp_json)"
        if [ "$(are_issue_head_and_base_in_same_repo)" != 'true' ] || ! should_patch_head; then
          offer_quote_reply_cached=1
        else
          offer_quote_reply_cached=0
        fi
        ;;
      pull_request|pull_request_target)
        if [ "$(are_head_and_base_in_same_repo "$GITHUB_EVENT_PATH" '.pull_request')" != 'true' ] || ! should_patch_head; then
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
  return "$offer_quote_reply_cached"
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
  report="@check-spelling-bot: ${react_prefix}$message${N}See [log]($(get_action_log)) for details."
  if [ -n "$GITHUB_STEP_SUMMARY" ]; then
    echo "$report" >> "$GITHUB_STEP_SUMMARY"
  fi
  if [ -n "$COMMENTS_URL" ] && [ -z "${COMMENTS_URL##*:*}" ]; then
    PAYLOAD="$(mktemp_json)"
    wrap_in_json 'body' "$report" > "$PAYLOAD"

    res=0
    comment "$COMMENTS_URL" "$PAYLOAD" > /dev/null || res=$?
    if [ "$res" -gt 0 ]; then
      if ! to_boolean "$DEBUG"; then
        echo "::error ::Failed posting to $COMMENTS_URL"
        cat "$PAYLOAD"
      fi
      return "$res"
    fi

    rm "$PAYLOAD"
  fi
  quit 1
}

confused_comment() {
  react_comment_and_die "$1" "$2" "confused"
}

get_github_user_and_email() {
  user_json="$(mktemp_json)"
  call_curl \
    "$GITHUB_API_URL/users/$1" > "$user_json"

  github_name="$(jq -r '.name // empty' "$user_json")"
  if [ -z "$github_name" ]; then
    github_name="$1"
  fi
  github_email="$(jq -r '.email // empty' "$user_json")"
  rm "$user_json"
  if [ -z "$github_email" ]; then
    github_email="$1@users.noreply.github.com"
  fi
  COMMIT_AUTHOR="--author=$github_name <$github_email>"
}

git_commit() {
  commit_reason="$1"
  git add -u
  git config user.email "check-spelling-bot@users.noreply.github.com"
  git config user.name "check-spelling-bot"
  git commit \
    "$COMMIT_AUTHOR" \
    --date="$created_at" \
    -m "$(echo "[check-spelling] Update metadata

                $commit_reason

                Signed-off-by: check-spelling-bot <check-spelling-bot@users.noreply.github.com>
                on-behalf-of: @check-spelling <check-spelling-bot@check-spelling.dev>
                " | strip_lead)"
}

mktemp_json() {
  file="$(mktemp)"
  mv "$file" "$file.json"
  echo "$file.json"
}

show_github_actions_push_disclaimer() {
  pr_number="$(jq -r '.issue.number' "$GITHUB_EVENT_PATH")"
  pr_path_escaped="$(echo "$GITHUB_REPOSITORY/pull/$pr_number" | perl -pe 's{/}{\%2F}g')"
  pr_query=$(echo "{
      repository(owner:$Q${GITHUB_REPOSITORY%/*}$Q, name:$Q${GITHUB_REPOSITORY#*/}$Q) {
        pullRequest(number:$pr_number) {
          headRepository {
            nameWithOwner
          }
          headRefName
        }
      }
    }" |
    strip_lead_and_blanks
  )
  pr_query_json="$(wrap_in_json 'query' "$pr_query")"
  repository_edit_branch=$(
    call_curl \
    -H "Content-Type: application/json" \
    --data-binary "$pr_query_json" \
    "$GITHUB_GRAPHQL_URL" |
    jq -r '(.data.repository.pullRequest.headRepository.nameWithOwner + "/edit/" + .data.repository.pullRequest.headRefName)'
  )

  get_job_info_and_step_info > /dev/null
  update_job_name="${job_name:-update}"

  action_ref=$(get_action_repo_info)
  if to_boolean "$INPUT_CHECKOUT"; then
    workflow_ssh_key_hint='`check-spelling`/`with`/`ssh_key`, then add them:

  ``` diff
      name: '"${update_job_name}"'
      ...
      steps:
      ...
      - name: apply spelling updates
        uses: ${action_ref:-check-spelling/check-spelling@...}
        with:
          checkout: '"$INPUT_CHECKOUT"'
  +       ssh_key: "${{ secrets.CHECK_SPELLING }}"
  ```'
  else
    workflow_ssh_key_hint='`checkout`/`with`/`ssh-key`, then add them:

  ``` diff
      name: '"${update_job_name}"'
      ...
      steps:
      ...
      - name: checkout
        uses: actions/checkout@...
  +     with:
  +       ssh-key: "${{ secrets.CHECK_SPELLING }}"
  ```'
  fi
  if [ -n "$workflow_path" ]; then
    qualified_workflow_path="$b$workflow_path$b workflow"
  else
    qualified_workflow_path="workflow"
  fi
  if [ "$(jq -r '.repository.owner.type // empty' "$GITHUB_EVENT_PATH" )" = 'User' ]; then
    owner="$(jq -r '.repository.owner.login // empty' "$GITHUB_EVENT_PATH" )"
    OWNER_TEXT="The owner ${owner:+"($owner)"}"
  else
    OWNER_TEXT='Users with the Admin role'
  fi
  OUTPUT="### :hourglass: check-spelling changes applied

  As [configured](https://github.com/check-spelling/check-spelling/wiki/Feature:-Update-expect-list#github_token), the commit pushed by @check-spelling-bot to GitHub doesn't trigger GitHub workflows due to a limitation of the @github-actions system.

  <details><summary>$OWNER_TEXT can address this for future interactions :magic_wand:</summary>

  #### Create a deploy key and secret
  $B sh
  (
    set -e
    brand=check-spelling; repo=$q$GITHUB_REPOSITORY$q; SECRET_NAME=CHECK_SPELLING"'
    cd "$(mktemp -d)"
    ssh-keygen -f "./$brand" -q -N "" -C "$brand key for $repo"
    gh repo deploy-key add "./$brand.pub" -R "$repo" -w -t "$brand-talk-to-bot"
    gh secret -R "$repo" set "$SECRET_NAME" < "./$brand"
  )'"
  $B

  #### Configure update job in workflow to use secret

  If the $qualified_workflow_path ${b}${update_job_name}${b} job doesn't already have the $workflow_ssh_key_hint

  </details>

  <!--$n$report_header$n-->
  To trigger another validation round and hopefully a :white_check_mark:, please add a blank line, e.g. to [$expect_file]($GITHUB_SERVER_URL/$repository_edit_branch/$expect_file?pr=$pr_path_escaped) and commit the change."
  echo "$OUTPUT" | tee -a "$GITHUB_STEP_SUMMARY" > "$BODY"
  body_to_payload
  COMMENTS_URL="$(jq -r '.issue.comments_url' "$GITHUB_EVENT_PATH")"
  response="$(mktemp)"
  res=0
  comment "$COMMENTS_URL" "$PAYLOAD" > "$response" || res=$?
  if [ $res -eq 0 ]; then
    track_comment "$response"
  fi
}

are_head_and_base_in_same_repo() {
  jq -r '('"$2"'.head.repo.full_name // "head") == ('"$2"'.base.repo.full_name // "base")' "$1"
}

are_issue_head_and_base_in_same_repo() {
  jq -r '.issue // empty' "$GITHUB_EVENT_PATH" > "$issue"
  pull_request_url="$(jq -r '.pull_request.url // empty' "$issue")"
  pull_request "$pull_request_url" > "$pull_request_info"
  are_head_and_base_in_same_repo "$pull_request_info" ''
}

report_if_bot_comment_is_minimized() {
  minimized_info=$(mktemp_json)
  call_curl \
  -H "Content-Type: application/json" \
  --data-binary "$(echo '{}' | jq --arg query "query { node(id: $Q$bot_comment_node_id$Q) { ... on IssueComment { isMinimized minimizedReason } } }" '.query = $query')" \
  "$GITHUB_GRAPHQL_URL" > "$minimized_info"

  if [ "$(jq '.data.node.isMinimized' "$minimized_info")" == 'true' ]; then
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
        minimized_reason="$decorated_reason. This probably means the referenced report has been obsoleted by a more recent push & review";;
      *)
        minimized_reason="$decorated_reason";;
    esac
    confused_comment "$trigger_comment_url" "The referenced report comment $(comment_url_to_html_url "$comment_url") is hidden$minimized_reason$minimized_reason_suffix"
  fi
}

char_count() {
  wc -c | xargs
}

line_count() {
  wc -l | xargs
}

handle_comment() {
  action="$(jq -r '.action // empty' "$GITHUB_EVENT_PATH")"
  if [ "$action" != "created" ]; then
    quit 0
  fi

  if ! offer_quote_reply; then
    quit 0
  fi

  comment="$(mktemp_json)"
  jq -r '.comment // empty' "$GITHUB_EVENT_PATH" > "$comment"
  body="$(mktemp)"
  jq -r '.body // empty' "$comment" > "$body"

  trigger="$(perl -ne 'print if /\@check-spelling-bot(?:\s+|:\s*)apply.*\Q$ENV{INPUT_REPORT_TITLE_SUFFIX}\E/' < "$body")"
  rm "$body"
  if [ -z "$trigger" ]; then
    quit 0
  fi

  trigger_comment_url="$(jq -r '.url // empty' "$comment")"
  sender_login="$(jq -r '.sender.login // empty' "$GITHUB_EVENT_PATH")"
  pull_request_head_info="$(mktemp_json)"
  jq .head "$pull_request_info" > "$pull_request_head_info"
  pull_request_sha="$(jq -r '.sha // empty' "$pull_request_head_info")"
  set_comments_url "$GITHUB_EVENT_NAME" "$GITHUB_EVENT_PATH" "$pull_request_sha"
  react_prefix_base="Could not perform [request]($(comment_url_to_html_url "$trigger_comment_url")).$N"
  react_prefix="$react_prefix_base"

  # Ideally we'd be able to consider `.repository.collaborators_url`` and honor
  # `Allow edits from maintainers`:
  # https://docs.github.com/pull-requests/collaborating-with-pull-requests/working-with-forks/allowing-changes-to-a-pull-request-branch-created-from-a-fork
  # However, at this time, that doesn't work.
  #
  # Note that the PR author doesn't have to have any ownership stake in the head
  # repo branch, so we don't special case that account.
  collaborators_url="$(jq -r '.head.repo.collaborators_url // empty' "$pull_request_info")"
  collaborators_url="$(echo "$collaborators_url" | perl -pe "s<\{/collaborator\}></$sender_login/permission>")"
  collaborator_permission="$(collaborator "$collaborators_url" | jq -r '.permission // empty')"

  case "$collaborator_permission" in
    admin)
      ;;
    write)
      ;;
    *)
      collaborator_suffix="$(jq -r '(if .pull_request.head.repo.full_name then " to " + .pull_request.head.repo.full_name else "" end)' "$pull_request_info")"
      confused_comment "$trigger_comment_url" "Commenter (@$sender_login) isn't a collaborator$collaborator_suffix."
      ;;
  esac

  created_at="$(jq -r '.created_at // empty' "$comment")"
  issue_url="$(jq -r '.url // empty' "$issue")"
  pull_request_ref="$(jq -r '.ref // empty' "$pull_request_head_info")"
  if git remote get-url origin | grep -q ^https://; then
    pull_request_repo="$(jq -r '.repo.clone_url // empty' "$pull_request_head_info")"
  else
    pull_request_repo="$(jq -r '.repo.ssh_url // empty' "$pull_request_head_info")"
  fi
  git remote add request "$pull_request_repo"
  git fetch request "$pull_request_sha"
  git config advice.detachedHead false
  git reset --hard
  git checkout "$pull_request_sha"

  set_up_files
  git reset --hard

  number_filter() {
    perl -pe 's<\{.*\}></(\\d+)>'
  }
  export pull_request_base="$(jq -r '.comment.html_url' "$GITHUB_EVENT_PATH" | perl -pe 's/\d+$/(\\d+)/')"
  comments_base="$(jq -r '.repository.comments_url // empty' "$GITHUB_EVENT_PATH" | number_filter)"
  export issue_comments_base="$(jq -r '.repository.issue_comment_url // empty' "$GITHUB_EVENT_PATH" | number_filter)"
  export comments_url="$pull_request_base|$comments_base|$issue_comments_base"

  summary_url=$(echo "$trigger" | perl -ne '
    next unless m{($ENV{GITHUB_SERVER_URL}/$ENV{GITHUB_REPOSITORY}/actions/runs/\d+(?:/attempts/\d+|))};
    print $1;
  ')
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
  if [ -n "$summary_url" ]; then
    [ -n "$comment_url" ] &&
      confused_comment "$trigger_comment_url" "Found both summary url (/actions/runs) and _/_$b$comments_url${b}_/_ in comment."
  else
    [ -n "$comment_url" ] ||
      confused_comment "$trigger_comment_url" "Did not find match for _/_$b$comments_url${b}_/_ in comment."
    [ "$(echo "$comment_url" | line_count)" -gt 1 ] &&
      confused_comment "$trigger_comment_url" "Found more than one _/_$b$comments_url${b}_/_ match in comment:$n$B$n$comment_url$n$B"
  fi

  if [ -n "$comment_url" ]; then
    res=0
    comment "$comment_url" > "$comment" ||
      confused_comment "$trigger_comment_url" "Failed to retrieve $b$comment_url$b."

    bot_comment_author=$(jq -r '.user.login // empty' "$comment")
    bot_comment_node_id=$(jq -r '.node_id // empty' "$comment")
    bot_comment_url=$(jq -r '.issue_url // .comment.url' "$comment")
    github_actions_bot="github-actions[bot]"
    [ -n "$bot_comment_author" ] ||
      confused_comment "$trigger_comment_url" "Could not retrieve author of $(comment_url_to_html_url "$comment_url")."
    [ "$bot_comment_author" = "$github_actions_bot" ] ||
      confused_comment "$trigger_comment_url" "Expected @$github_actions_bot to be author of $(comment_url_to_html_url "$comment_url") (found @$bot_comment_author)."
    [ "$issue_url" = "$bot_comment_url" ] ||
      confused_comment "$trigger_comment_url" "Referenced comment was for a different object: $bot_comment_url"

    comment_body=$(mktemp)
    jq -r '.body // empty' "$comment" > "$comment_body"
    rm "$comment"
    grep -q '@check-spelling-bot Report' "$comment_body" ||
      confused_comment "$trigger_comment_url" "$(comment_url_to_html_url "$comment_url") does not appear to be a @check-spelling-bot report"

    report_if_bot_comment_is_minimized
    skip_wrapping=1

    instructions_head=$(mktemp)
    (
      patch_add=1
      patch_remove=1
      should_exclude_patterns=$(mktemp)
      patch_variables "$comment_body" > "$instructions_head"
    )
    git restore -- "$bucket/$project" 2> /dev/null || true

    res=0
    . "$instructions_head" || res=$?
    if [ $res -gt 0 ]; then
      echo "instructions_head failed ($res)"
      cat "$instructions_head"
      confused_comment "$trigger_comment_url" "Failed to set up environment to apply changes for $(comment_url_to_html_url "$comment_url")."
    fi
    rm "$comment_body" "$instructions_head"
    instructions=$(generate_instructions)

    react_prefix="${react_prefix}[Instructions]($(comment_url_to_html_url "$comment_url")) "
    . "$instructions" || res=$?
    if [ $res -gt 0 ]; then
      echo "instructions failed ($res)"
      cat "$instructions"
      res=0
      confused_comment "$trigger_comment_url" "Failed to apply changes."
    fi
    rm "$instructions"
    update_note="per $(comment_url_to_html_url "$comment_url")"
  elif [ -n "$summary_url" ]; then
    if [ -n "$INPUT_REPORT_TITLE_SUFFIX" ]; then
      title_suffix_re='.*'"$("$quote_meta" "$INPUT_REPORT_TITLE_SUFFIX")"
    fi
    comment_search_re='@check-spelling-bot(?:[\t ]+|:[\t ]*)apply.*'"$("$quote_meta" "$summary_url")$title_suffix_re"
    COMMENTS_URL=$(jq -r '.issue.comments_url' "$GITHUB_EVENT_PATH")
    bot_comment_node_id_and_status=$(get_a_comment "$comment_search_re")
    if [ -n "$bot_comment_node_id_and_status" ]; then
      bot_comment_node_id="$(echo "$bot_comment_node_id_and_status" | head -1)"
      comment_url=$(get_comment_url_from_id "$bot_comment_node_id")
      report_if_bot_comment_is_minimized
    fi

    summary_url_api=$(
      echo "$summary_url" | perl -ne '
      next unless m{$ENV{GITHUB_SERVER_URL}/($ENV{GITHUB_REPOSITORY}/actions/runs/\d+(?:/attempts/\d+|))};
      print "/repos/$1";
    ')
    [ -n "$summary_url_api" ] || confused_comment "$trigger_comment_url" "Failed to retrieve api url -- this should never happen. Please file a bug."
    gh_api_fault=$(mktemp)
    gh_api_err=$(mktemp)
    if ! GH_TOKEN="$GITHUB_TOKEN" gh api "/repos/$GITHUB_REPOSITORY/actions/cache/usage" > "$gh_api_fault" 2> "$gh_api_err"; then
      if [ "$(jq -r .message "$gh_api_fault")" = 'Resource not accessible by integration' ]; then
        confused_comment "$trigger_comment_url" "In order for this job to handle $summary_url, it needs:$(echo "

        $B diff
         permissions:
        +  actions: read
        $B
        " | perl -pe 's/^ {8}//')"
      fi
      confused_comment "$trigger_comment_url" "$(echo "Unexpected error retrieving action metadata for $GITHUB_REPOSITORY. Please file a bug.

      Details:
      $B json
      $(cat "$gh_api_fault")
      $B

      $B
      $(cat "$gh_api_err")
      $B
      " | strip_lead)"
    fi
    head_branch=$(GH_TOKEN="$GITHUB_TOKEN" gh api "$summary_url_api" -q '.head_branch')
    [ -n "$head_branch" ] ||
    confused_comment "$trigger_comment_url" "Failed to retrieve $b.head_branch$b for $summary_url. Please file a bug."
    [ "$head_branch" = "$pull_request_ref" ] ||
    confused_comment "$trigger_comment_url" "$summary_url ($head_branch) does not match expected branch ($pull_request_ref)"
    apply_output=$(mktemp)
    apply_err=$(mktemp)

    GH_TOKEN="$GITHUB_TOKEN" \
      "$spellchecker/apply.pl" "$summary_url" > "$apply_output" 2> "$apply_err" ||
    confused_comment "$trigger_comment_url" "Apply failed.${N}$(cat "$apply_output")${N}${N}$(cat "$apply_err")"
    update_note="for $summary_url"
  else
    confused_comment "$trigger_comment_url" "Unexpected state."
  fi
  git status --u=no --porcelain | grep -q . ||
    confused_comment "$trigger_comment_url" "Request did not change repository content.${N}Maybe someone already applied these changes?"
  react_prefix="$react_prefix_base"
  get_github_user_and_email "$sender_login"
  git_commit "$(echo "Update $update_note
                      Accepted in $(comment_url_to_html_url "$trigger_comment_url")
                    "|strip_lead)" ||
    confused_comment "$trigger_comment_url" "Did not generate a commit.${N}Perhaps there was a merge conflict or an object changed from being a directory to a file or vice versa? (Please file a bug including a link to this comment.)"
  git push request "HEAD:$pull_request_ref" ||
  {
    {
      git show HEAD
    } || true
    confused_comment "$trigger_comment_url" "Generated a commit, but the $pull_request_repo rejected the commit.${N}Maybe this task lost a race with another push?"
  }

  react "$trigger_comment_url" 'eyes' > /dev/null

  react "${comment_url:-$trigger_comment_url}" 'rocket' > /dev/null
  trigger_node=$(jq -r '.comment.node_id // empty' "$GITHUB_EVENT_PATH")
  collapse_comment "$trigger_node" "$bot_comment_node_id"

  if git remote get-url origin | grep -q ^https://; then
    show_github_actions_push_disclaimer
  else
    echo "### :white_check_mark: check-spelling changes applied" >> "$GITHUB_STEP_SUMMARY"
  fi
  echo "
  #### Metadata updates

  $B
  $(git diff HEAD~..HEAD --stat)
  $B
  " | strip_lead >> "$GITHUB_STEP_SUMMARY"
  echo "# end"
  quit 0
}

encode_artifact() {
  echo 'You will want to cat the following content to:'
  echo
  echo "perl -ne 'next if /--- (?:BEGIN|END) BASE64 ---/; next unless s{^[^|]*\|\s*}{};print' | base64 -d -o artifact.zip"
  echo '--- BEGIN BASE64 ---'
  base64 "$1"
  echo '--- END BASE64 ---'
}

build_artifact_suffix() {
  artifact_suffix="-$(echo "$INPUT_REPORT_TITLE_SUFFIX" | perl -pe 's/^\s+|\s+$//; s/[^a-z]+/-/gi;')"
}

define_variables() {
  if [ -f "$output_variables" ]; then
    return
  fi
  . "$spellchecker/update-state.sh"
  load_env
  GITHUB_TOKEN="${GITHUB_TOKEN:-"$INPUT_GITHUB_TOKEN"}"
  if [ -n "$GITHUB_TOKEN" ]; then
    export AUTHORIZATION_HEADER="Authorization: token $GITHUB_TOKEN"
  else
    export AUTHORIZATION_HEADER='X-No-Authorization: Sorry About That'
  fi

  if  [ -n "$ACT" ] &&
      [ -z "$GITHUB_ACTION_REPOSITORY" ] &&
      [ -z "$GITHUB_ACTION_REF" ] &&
      [ "$GH_ACTION_REF" = "$GITHUB_REF_NAME" ] &&
      [ "$GH_ACTION_REPOSITORY" = "$GITHUB_REPOSITORY" ]; then
    # https://github.com/nektos/act/issues/1473 github.action_repository / github.action_ref aren't properly filled in
    GH_ACTION_REPOSITORY=$(git -C "$GITHUB_ACTION_PATH" config --get remote.origin.url|perl -pe 's{.*[:/]([^:/]+/[^/]+)$}{$1}')
    GH_ACTION_REF=${GITHUB_ACTION_PATH##*@}
  fi

  export early_warnings="$(mktemp)"
  if [ -n "$INPUT_INTERNAL_STATE_DIRECTORY" ]; then
    data_dir="$INPUT_INTERNAL_STATE_DIRECTORY"
    if [ ! -e "$data_dir" ] && [ -n "$INPUT_CALLER_CONTAINER" ]; then
      mkdir -p "$data_dir"
      docker cp "$INPUT_CALLER_CONTAINER:$data_dir" "$(dirname "$data_dir")"
    fi
    artifact=artifact
    if [ -n "$INPUT_REPORT_TITLE_SUFFIX" ]; then
      build_artifact_suffix
      if [ -e "$data_dir/$artifact$artifact_suffix.zip" ]; then
        artifact="$artifact$artifact_suffix"
      fi
    fi
    if [ -s "$data_dir/$artifact.zip" ]; then
      artifact="$artifact.zip"
      (
        cd "$data_dir"
        if [ -n "$INPUT_CALLER_CONTAINER" ]; then
          encode_artifact "$artifact"
        fi
        unzip -q "$artifact"
        rm "$artifact"
      )
    fi
  else
    data_dir="$(mktemp -d)"
  fi
  bucket="${INPUT_BUCKET:-"$bucket"}"
  project="${INPUT_PROJECT:-"$project"}"
  if to_boolean ${junit:+"$junit"} || to_boolean "$INPUT_QUIT_WITHOUT_ERROR"; then
    quit_without_error=1
  fi
  if [ -z "$bucket" ] && [ -z "$project" ] && [ -n "$INPUT_CONFIG" ]; then
    bucket=${INPUT_CONFIG%/*}
    project=${INPUT_CONFIG##*/}
  fi
  job_count="${INPUT_EXPERIMENTAL_PARALLEL_JOBS:-2}"
  if ! [ "$job_count" -eq "$job_count" ] 2>/dev/null || [ "$job_count" -lt 2 ]; then
    job_count=1
  fi
  extra_dictionary_limit="$(echo "${INPUT_EXTRA_DICTIONARY_LIMIT}" | perl -pe 's/\D+//g')"
  if [ -z "$extra_dictionary_limit" ]; then
    extra_dictionary_limit=5
  fi
  action_workflow_path_file="$data_dir/workflow-path.txt"
  workflow_path=$(get_workflow_path)

  dict=$(mktemp)
  splitter_configuration=$(mktemp -d)
  patterns="$splitter_configuration/patterns.txt"
  forbidden_path="$splitter_configuration/forbidden.txt"
  candidates_path="$splitter_configuration/candidates.txt"
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
  expect_collator="$spellchecker/expect-collator.pl"
  strip_word_collator_suffix="$spellchecker/strip-word-collator-suffix.pl"
  find_token="$spellchecker/find-token.pl"
  output_covers="$spellchecker/output-covers.pl"
  cleanup_file="$spellchecker/cleanup-file.pl"
  file_size="$spellchecker/file-size.pl"
  check_dictionary="$spellchecker/check-dictionary.pl"
  check_yaml_key_value="$spellchecker/check-yaml-key-value.pl"
  get_yaml_value="$spellchecker/get-yaml-value.pl"
  quote_meta="$spellchecker/quote-meta.pl"
  summary_tables="$spellchecker/summary-tables.pl"
  generate_sarif="$spellchecker/generate-sarif.pl"
  get_commits_for_check_commit_message="$spellchecker/get-commits-for-check-commit-message.pl"
  scope_files="$spellchecker/exclude.pl"
  run_output="$temp/unknown.words.txt"
  diff_output="$temp/output.diff"
  tokens_file="$data_dir/tokens.txt"
  remove_words="$data_dir/remove_words.txt"
  action_log_ref="$data_dir/action_log_ref.txt"
  action_log_file_name="$data_dir/action_log_file_name.txt"
  job_id_ref="$data_dir/job_id_ref.txt"
  jobs_summary_link="$GITHUB_SERVER_URL/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID/attempts/$GITHUB_RUN_ATTEMPT"
  extra_dictionaries_json="$data_dir/suggested_dictionaries.json"
  export sarif_overlay_path="$data_dir/overlay.sarif.json"
  file_list="$data_dir/checked_files.lst"
  BODY="$data_dir/comment.md"
  output_variables="$(mktemp)"
  instructions_preamble="$(mktemp)"
  if to_boolean "$INPUT_REPORT_TIMING"; then
    timing_report="$data_dir/timing_report.csv"
  fi

  warnings_list="$(echo "$INPUT_WARNINGS,$INPUT_NOTICES" | perl -pe 's/[^-a-z]+/|/g;s/^\||\|$//g')"

  report_header="# @check-spelling-bot Report"
  if [ -n "$INPUT_REPORT_TITLE_SUFFIX" ]; then
    report_header="$report_header $INPUT_REPORT_TITLE_SUFFIX"
  fi
  INPUT_TASK="${INPUT_TASK:-"$INPUT_CUSTOM_TASK"}"
  if [ -z "$GITHUB_OUTPUT" ]; then
    echo 'Warning - $GITHUB_OUTPUT is required for this workflow to work' >&2
    GITHUB_OUTPUT=$(mktemp)
    GH_OUTPUT_STUB=1
  fi
}

check_yaml_key_value() {
  (
  if [ -n "$1" ]; then
    KEY="$KEY" \
    VALUE="$VALUE" \
    MESSAGE=${MESSAGE:+"$MESSAGE"} \
    "$check_yaml_key_value" "$1"
  else
    echo "?:0:1, $MESSAGE"
  fi
  ) >> "$early_warnings"
}

check_inputs() {
  if to_boolean "$WARN_USE_SARIF_NEED_SECURITY_EVENTS_WRITE"; then
    KEY=use_sarif \
    VALUE="$WARN_USE_SARIF_NEED_SECURITY_EVENTS_WRITE" \
    MESSAGE='Warning - Unsupported configuration: use_sarif needs security-events: write. (unsupported-configuration)' \
    check_yaml_key_value "$workflow_path"
  fi
  if to_boolean "$WARN_USE_SARIF_NEEDS_ADVANCED_SECURITY"; then
    KEY=use_sarif \
    VALUE="$WARN_USE_SARIF_NEEDS_ADVANCED_SECURITY" \
    MESSAGE='Warning - Unsupported configuration: use_sarif needs GitHub Advanced Security to be enabled - see <https://docs.github.com/get-started/learning-about-github/about-github-advanced-security>. (unsupported-configuration)' \
    check_yaml_key_value "$workflow_path"
  fi
  if to_boolean "$WARN_USE_SARIF_ONLY_CHANGED_FILES"; then
    KEY=use_sarif \
    VALUE="$WARN_USE_SARIF_NEED_SECURITY_EVENTS_WRITE" \
    MESSAGE='Warning - Unsupported configuration: use_sarif is incompatible with only_check_changed_files. (unsupported-configuration)' \
    check_yaml_key_value "$workflow_path"
  fi
  if [ -n "$ACT" ] &&
    to_boolean "$INPUT_POST_COMMENT" ; then
    KEY=post_comment \
    VALUE="$INPUT_POST_COMMENT" \
    MESSAGE='Warning - Unsupported configuration: post_comment is not compatible with nektos/act. (unsupported-configuration)' \
    check_yaml_key_value "$workflow_path"
  fi
  if [ -n "$ACT" ] &&
    to_boolean "$INPUT_USE_SARIF" &&
    [ "$GITHUB_REPOSITORY" = '.' ]; then
    INPUT_USE_SARIF=
    echo '::warning ::Disabling sarif under act without repository'
  fi
  if [ -n "$INPUT_SPELL_CHECK_THIS" ] &&
    ! echo "$INPUT_SPELL_CHECK_THIS" | perl -ne 'chomp; exit 1 unless m{^[-_.A-Za-z0-9]+/[-_.A-Za-z0-9]+(?:|\@[-_./A-Za-z0-9]+)$};'; then
    KEY=spell_check_this \
    VALUE="$INPUT_SPELL_CHECK_THIS" \
    MESSAGE='Warning - Unsupported repository: spell_check_this. (unsupported-repo-notation)' \
    check_yaml_key_value "$workflow_path"
    INPUT_SPELL_CHECK_THIS=''
  fi
  if [ -n "$INPUT_EXTRA_DICTIONARIES" ]; then
    INPUT_EXTRA_DICTIONARIES="$(echo "$INPUT_EXTRA_DICTIONARIES" | words_to_lines | sort)"
    for duplicated_dictionary in $(echo "$INPUT_EXTRA_DICTIONARIES" | uniq -d); do
      KEY=extra_dictionaries \
      VALUE="$duplicated_dictionary" \
      MESSAGE="Warning - \`$duplicated_dictionary\` appears multiple times in 'extra_dictionaries' (duplicate-extra-dictionary)" \
      check_yaml_key_value "$workflow_path"
    done
    INPUT_EXTRA_DICTIONARIES="$(echo "$INPUT_EXTRA_DICTIONARIES" | uniq)"
  fi
}

sort_unique() {
  sort -u -f | perl -ne 'next unless /./; print'
}

project_file_path() {
  echo "$bucket/$project/$1"
}

check_pattern_file() {
  perl -i -e 'open WARNINGS, ">>", $ENV{early_warnings};
  while (<>) {
    next if /^#/;
    my $line = $_;
    chomp;
    next unless /./;
    if (eval {qr/$_/}) {
      print $line;
    } else {
      $@ =~ s/(.*?)\n.*/$1/m;
      my $err = $@;
      $err =~ s{^.*? in regex; marked by <-- HERE in m/(.*) <-- HERE.*$}{$1};
      my $start = $+[1] - $-[1];
      my $end = $start + 1;
      print WARNINGS "$ARGV:$.:$start ... $end, Warning - Bad regex: $@ (bad-regex)\n";
      print "^\$\n";
    }
  }
  close WARNINGS;
  ' "$1"
}

check_for_newline_at_eof() {
  maybe_missing_eol="$1"
  if [ -s "$maybe_missing_eol" ] && [ "$(tail -1 "$maybe_missing_eol" | line_count)" -eq 0 ]; then
    line="$(( $(line_count < "$maybe_missing_eol") + 1 ))"
    start="$(tail -1 "$maybe_missing_eol" | char_count)"
    stop="$(( start + 1 ))"
    echo "$maybe_missing_eol:$line:$start ... $stop, Warning - No newline at eof. (no-newline-at-eof)" >> "$early_warnings"
    echo >> "$maybe_missing_eol"
  fi
}

check_dictionary() {
  file="$1"
  comment_char="#" \
  "$check_dictionary" "$file"
}

cleanup_file() {
  export maybe_bad="$1"

  result=0
  "$cleanup_file" || result=$?
  if [ "$result" -gt 0 ]; then
    quit "$result"
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
  ext="$(echo "$1" | sed -e 's/^.*\.//')"
  file="$(echo "$1" | sed -e "s/\.$ext$//")"
  dest="$2"
  type="$file"
  if [ ! -e "$dest" ] && [ -n "$bucket" ] && [ -n "$project" ]; then
    from="$(project_file_path "$file"."$ext")"
    case "$from" in
      ssh://git@*|git@*)
        (
          echo "Retrieving $file from $from"
          cd "$temp"
          repo="$(echo "$bucket" | perl -pe 's#(?:ssh://|)git\@github.com[:/]([^/]*)/(.*.git)#https://github.com/$1/$2#')"
          [ -d metadata ] || git clone --depth 1 "$repo" --single-branch --branch "$project" metadata
          cleanup_file metadata/"$file".txt "$type"
          cp metadata/"$file".txt "$dest" 2> /dev/null || touch "$dest"
        );;
      gs://*)
        echo "Retrieving $file from $from"
        gsutil cp -Z "$from" "$dest" >/dev/null 2>/dev/null || touch "$dest"
        cleanup_file "$dest" "$type"
        ;;
      *://*)
        echo "Retrieving $file from $from"
        download "$from" "$dest" || touch "$dest"
        cleanup_file "$dest" "$type"
        ;;
      *)
        append_to="$from"
        if [ -f "$from" ]; then
          echo "Retrieving $file from $from"
          cleanup_file "$from" "$type"
          cp "$from" "$dest"
          from_expanded="$from"
        else
          if [ ! -e "$from" ]; then
            from="$(echo "$from" | sed -e "s/\.$ext$//")"
          fi
          if [ -d "$from" ]; then
            from_expanded="$(find "$from" -mindepth 1 -maxdepth 1 -name "*$ext" ! -name "*$n*" |sort)"
            append_to="$from"/"$(git rev-parse --revs-only HEAD || date '+%Y%M%d%H%m%S')"."$ext"
            touch "$dest"
            echo "Retrieving $file from $from_expanded"
            while IFS= read -r item; do
              if [ -s "$item" ]; then
                cleanup_file "$item" "$type"
                cat "$item" >> "$dest"
              fi
            done <<< "$from_expanded"
            from="$from"/"$(basename "$from")"."$ext"
          else
            from_expanded="$from"."$ext"
            from="$from_expanded"
          fi
        fi;;
    esac
  fi
}
get_project_files_deprecated() {
  # "preferred" "deprecated" "path"
  if [ ! -s "$3" ]; then
    save_append_to="$append_to"
    get_project_files "$2" "$3"
    if [ -s "$3" ]; then
      example="$(echo "$from_expanded"|head -1)"
      if [ "$(basename "$(dirname "$example")")" = "$2" ]; then
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
  if [ "$exit_value" = 0 ]; then
    echo "Downloaded $1 (to $2)" >&2
  else
    echo "Failed to download $1 (to $2)" >&2
  fi
  return "$exit_value"
}

github_step_summary_likely_fatal() {
  head="$1"
  body="$2"
  hint="$3"
  (
    echo "# :stop_sign: $head"
    echo
    echo "$body"
    echo
    echo "$hint"
    echo
  ) >> "$GITHUB_STEP_SUMMARY"
}

github_step_summary_likely_fatal_event() {
  category="$3"
  github_step_summary_likely_fatal "$1" "$2" ":warning: For more information, see [$category](https://github.com/check-spelling/check-spelling/wiki/Event-descriptions#$category)."
}

download_or_quit_with_error() {
  exit_code="$(mktemp)"
  download "$1" "$2" || (
    echo "$?" > "$exit_code"
    echo "Could not download $1 (to $2) (required-download-failed)" >&2
    github_step_summary_likely_fatal_event \
      'Required download failed' \
      "Could not download $1 (to $2)." \
      'required-download-failed'
  )
  if [ -s "$exit_code" ]; then
    exit_value="$(cat "$exit_code")"
    rm "$exit_code"
    quit "$exit_value"
  fi
}

set_up_ua() {
  export CHECK_SPELLING_VERSION="$(cat "$spellchecker/version")"
  curl_ua="check-spelling/$CHECK_SPELLING_VERSION; $(curl --version|perl -ne '$/=undef; <>; s/\n.*//;s{ }{/};s/ .*//;print')"
}

install_tools() {
  if [ -n "$perl_libs" ] && ! command_v cpanm; then
    command -v cpanm >/dev/null 2>/dev/null ||
      curl -s -S -L https://cpanmin.us | perl - --sudo App::cpanminus
  fi
  if [ -n "$apps" ]; then
    if command_v apt-get; then
      export DEBIAN_FRONTEND=noninteractive
      echo "$apps" | xargs ${SUDO:+"$SUDO"} apt-get -qq install --no-install-recommends -y >/dev/null 2>/dev/null ||
      ${SUDO:+"$SUDO"} apt-get -qq update &&
      echo "$apps" | xargs ${SUDO:+"$SUDO"} apt-get -qq install --no-install-recommends -y >/dev/null 2>/dev/null
      echo "Installed:$apps" >&2
      apps=
    elif command_v brew; then
      echo "$apps" | xargs brew install
      apps=
    else
      echo "missing $apps -- things will fail" >&2
    fi
  fi
  if [ -n "$perl_libs" ]; then
    echo "$perl_libs" | xargs perl "$(command -v cpanm)" --notest
    perl_libs=''
  fi
}

add_app() {
  if ! command_v "$1"; then
    apps="$apps $@"
  fi
}

add_perl_lib() {
  if ! perl -M"$1" -e '' 2>/dev/null; then
    if [ -n "$HAS_APT" ]; then
      apps="$apps $2"
    else
      perl_libs="$perl_libs $1"
    fi
  fi
}

need_hunspell() {
  echo "$INPUT_EXTRA_DICTIONARIES $INPUT_CHECK_EXTRA_DICTIONARIES" | grep -q '\.dic'
}

check_perl_libraries() {
  if command_v apt-get; then
    HAS_APT=1
  fi

  add_perl_lib HTTP::Date libhttp-date-perl
  add_perl_lib URI::Escape liburi-escape-xs-perl
  if to_boolean "$INPUT_USE_SARIF"; then
    add_perl_lib Hash::Merge libhash-merge-perl
  fi
  if need_hunspell; then
    add_app hunspell
    add_perl_lib Text::Hunspell libtext-hunspell-perl
  fi
}

set_up_tools() {
  apps=""

  add_app curl ca-certificates
  add_app git
  if need_hunspell; then
    add_app hunspell
  fi
  if ! command_v gh; then
    if command_v apt-get && ! apt-cache policy gh | grep -q Candidate:; then
      curl -A "$curl_ua" -f -s -S -L https://cli.github.com/packages/githubcli-archive-keyring.gpg |
        $SUDO dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg 2> /dev/null
      $SUDO chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
      echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" |
        $SUDO tee /etc/apt/sources.list.d/github-cli.list > /dev/null
    fi
    add_app gh
  fi
  check_perl_libraries
  install_tools
  set_up_jq
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
  response_headers="$(mktemp)"
  response_body="$(mktemp)"
  curl_output="$(mktemp)"
  until [ "$curl_attempt" -ge 3 ]
  do
    curl -D "$response_headers" -A "$curl_ua" -s -H "$(curl_auth)" "$@" -o "$response_body" > "$curl_output"
    if [ ! -s "$response_body" ] && [ -s "$curl_output" ]; then
      mv "$curl_output" "$response_body"
    fi
    echo >> "$response_headers"
    response_code=$(perl -e '$_=<>; $_=0 unless s#^HTTP/[\d.]+ (\d+).*#$1#;print;' "$response_headers")
    if [ "$response_code" -ne 429 ] && [ "$response_code" -ne 503 ]; then
      cat "$response_body"
      rm -f "$response_body"
      if [ -z "$keep_headers" ]; then
        rm -f "$response_headers"
      fi
      return
    fi
    delay="$("$spellchecker/calculate-delay.pl" "$response_headers")"
    (echo "call_curl received a $response_code and will wait for ${delay}s:"; grep -E -i 'x-github-request-id|x-rate-limit-|retry-after' "$response_headers") >&2
    sleep "$delay"
    curl_attempt="$(( curl_attempt + 1 ))"
  done
}

set_up_jq() {
  if ! command_v jq || jq --version | perl -ne 'exit 0 unless s/^jq-//;exit 1 if /^(?:[2-9]|1\d|1\.(?:[6-9]|1\d+))/; exit 0'; then
    jq_url=https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64
    spellchecker_bin="$spellchecker/bin"
    jq_bin="$spellchecker_bin/jq"
    mkdir -p "$spellchecker_bin"
    download_or_quit_with_error "$jq_url" "$jq_bin"
    chmod 0755 "$jq_bin"
    PATH="$spellchecker_bin:$PATH"
  fi
}

words_to_lines() {
  xargs -n1
}

build_dictionary_alias_pattern() {
  if [ -z "$dictionary_alias_pattern" ]; then
    dictionary_alias_pattern="$(
      echo "$INPUT_DICTIONARY_SOURCE_PREFIXES" |
      jq -r 'to_entries | map( {("s{^" +.key + ":}{" + .value +"};"): 1 } ) | .[] | keys[]' |xargs echo
    )"
  fi
}

expand_dictionary_url() {
  echo "$1" | perl -pe "$dictionary_alias_pattern"
}

get_extra_dictionary() {
  extra_dictionary_url="$1"
  source_link="$dictionaries_dir"/."$2"
  url="$(expand_dictionary_url "$extra_dictionary_url")"
  dest="$dictionaries_dir"/"$2"
  if [ -s "$dest" ]; then
    if [ ! -s "$dest.etag" ]; then
      return
    fi
    check_etag="-H"
    check_etag_value="$(perl -ne 's/\s+$//; print qq<If-None-Match: $_>; last' "$dest.etag")"
    real_dest="$dest"
    dest="$(mktemp)"
  else
    check_etag=-H
    check_etag_value=Ignore:1
    real_dest=
  fi
  if [ "$url" != "${url#"${GITHUB_SERVER_URL}"/*}" ]; then
    no_curl_auth=1
  fi
  keep_headers=1 call_curl "$check_etag" "$check_etag_value" "$url" > "$dest"
  if { [ -z "$response_code" ] || [ "$response_code" -ge 400 ] || [ "$response_code" -eq 000 ] ; } 2> /dev/null; then
    echo "::error ::Failed to retrieve $extra_dictionary_url -- HTTP $response_code for $url (dictionary-not-found)" >> "$early_warnings"
    (
      echo "Failed to retrieve $extra_dictionary_url ($url)"
      cat "$response_headers"
    ) >&2
    rm -f "$dictionaries_canary"
    return
  fi
  if [ "$response_code" -eq 304 ]; then
    return
  fi
  echo "Retrieved $extra_dictionary_url" >&2
  if [ -n "$real_dest" ]; then
    mv "$dest" "$real_dest"
    dest="$real_dest"
  fi
  echo "$extra_dictionary_url" > "$source_link"
  perl -ne 'next unless s/^etag: //; chomp; print' "$response_headers" > "$dest.etag"
  [ -s "$CACHE_DICTIONARIES" ] || echo 1 > "$CACHE_DICTIONARIES"
}

get_hunspell_stem() {
  echo "$1" | perl -pe 's{.*?([^:/]+)/src/hunspell/index.*}{$1};s{.*/}{}'
}

get_extra_dictionaries() {
  dictionaries_dir="$spellchecker/dictionaries/$1"
  extra_dictionaries="$(echo "$2" | words_to_lines)"
  dictionaries_canary="$3"
  mkdir -p "$dictionaries_dir"
  response_headers="$(mktemp)"
  if [ -n "$extra_dictionaries" ]; then
    parallel_task_list=$(mktemp -d)
    (cd "$parallel_task_list"; touch $(seq "$(echo "$extra_dictionaries"|line_count)"))
    parallel_task=0
    for extra_dictionary in $extra_dictionaries; do
    parallel_task=$(( parallel_task + 1 ))
    (
      dictionary_base="$(basename "$extra_dictionary")"
      if [ "$dictionary_base" = index.dic ]; then
        dictionary_base="$(get_hunspell_stem "$extra_dictionary")".dic
      fi
      get_extra_dictionary "$extra_dictionary" "$dictionary_base"
      if echo "$extra_dictionary" | grep -q '\.dic$'; then
        get_extra_dictionary "$(echo "$extra_dictionary" | sed -e 's/\.dic$/.aff/')" "$(echo "$dictionary_base" | sed -e 's/\.dic$/.aff/')"
      fi
      rm "$parallel_task_list/$parallel_task"
    ) &
    done
    while find "$parallel_task_list/" -mindepth 1 -print -quit |grep -q .; do sleep 1; done
  fi
  rm -f "$response_headers"
  echo "$dictionaries_dir"
}

set_up_reporter() {
  if to_boolean "$DEBUG"; then
    echo 'env:'
    env|sort
  fi
  if [ -z "$GITHUB_EVENT_PATH" ] || [ ! -s "$GITHUB_EVENT_PATH" ]; then
    GITHUB_EVENT_PATH=/dev/null
  fi
  if to_boolean "$DEBUG"; then
    echo 'GITHUB_EVENT_PATH:'
    cat "$GITHUB_EVENT_PATH"
  fi
  if to_boolean "$INPUT_USE_SARIF"; then
    set_up_tools
    sarif_error=$(mktemp)
    sarif_output=$(mktemp_json)
    GH_TOKEN="$GITHUB_TOKEN" gh api --method POST -H "Accept: application/vnd.github+json" "$GITHUB_API_URL/repos/$GITHUB_REPOSITORY/code-scanning/sarifs" > "$sarif_output" 2> "$sarif_error" || true
    if grep -q 'Advanced Security must be enabled' "$sarif_error" ||
       grep -q 'GH_TOKEN environment' "$sarif_error"; then
      if true || to_boolean "$DEBUG"; then
        cat "$sarif_error"
        cat "$sarif_output"
        echo
      fi
      WARN_USE_SARIF_NEEDS_ADVANCED_SECURITY="$INPUT_USE_SARIF"
    else
      if grep -Eq 'not authorized|not accessible' "$sarif_output"; then
        if true || to_boolean "$DEBUG"; then
          cat "$sarif_error"
          cat "$sarif_output"
          echo
        fi
        WARN_USE_SARIF_NEED_SECURITY_EVENTS_WRITE="$INPUT_USE_SARIF"
      fi
    fi
    if to_boolean "$INPUT_ONLY_CHECK_CHANGED_FILES"; then
      WARN_USE_SARIF_ONLY_CHANGED_FILES="$INPUT_USE_SARIF"
    fi
    if to_boolean "$WARN_USE_SARIF_NEED_SECURITY_EVENTS_WRITE" || to_boolean "$WARN_USE_SARIF_ONLY_CHANGED_FILES" || to_boolean "$WARN_USE_SARIF_NEEDS_ADVANCED_SECURITY"; then
      INPUT_USE_SARIF=
    fi
  fi
  echo "::add-matcher::$spellchecker/reporter-misc.json"
  if ! to_boolean "$INPUT_USE_SARIF"; then
    echo "::add-matcher::$spellchecker/reporter.json"
  fi
}

set_up_files() {
  if [ "$GITHUB_EVENT_NAME" = "pull_request_target" ] || [ "$GITHUB_EVENT_NAME" = "pull_request" ]; then
    if [ -z "$GITHUB_HEAD_REF" ]; then
      GITHUB_HEAD_REF="$(jq -r '.pull_request.head.ref // empty' "$GITHUB_EVENT_PATH")"
    fi
  fi
  case "$INPUT_TASK" in
    comment|collapse_previous_comment|pr_head_sha)
      if [ -e "$data_dir/spell_check_this.json" ]; then
        spell_check_this_repo=$(mktemp -d)
        spelling_config=$(jq -r .config "$data_dir/spell_check_this.json")
        spell_check_this_repo_url=$(jq -r .url "$data_dir/spell_check_this.json")
        spell_check_this_repo_branch=$(jq -r .branch "$data_dir/spell_check_this.json")
        spell_check_this_config=$(jq -r .path "$data_dir/spell_check_this.json")
      fi
    ;;
    *)
      if [ ! -d "$bucket/$project/" ] && [ -n "$INPUT_SPELL_CHECK_THIS" ]; then
        spelling_config="$bucket/$project/"
        spell_check_this_repo=$(mktemp -d)
        spell_check_this_config=.github/actions/spelling/
        spell_check_this_repo_name=${INPUT_SPELL_CHECK_THIS%%@*}
        if [ "$spell_check_this_repo_name" != "$INPUT_SPELL_CHECK_THIS" ]; then
          spell_check_this_repo_branch=${INPUT_SPELL_CHECK_THIS##*@}
        fi
      fi
    ;;
  esac
  if [ -n "$spelling_config" ]; then
    if git clone --depth 1 "https://github.com/$spell_check_this_repo_name" ${spell_check_this_repo_branch:+--branch "$spell_check_this_repo_branch"} "$spell_check_this_repo" > /dev/null 2> /dev/null; then
      if [ ! -d "$spell_check_this_repo/$spell_check_this_config" ]; then
        (
          if [ -n "$workflow_path" ]; then
            spell_check_this_config="$spell_check_this_config" perl -e '$pattern=quotemeta($ENV{INPUT_SPELL_CHECK_THIS}); while (<>) { next unless /$pattern/; $start=$-[0]+1; print "$ARGV:$.:$start ... $+[0], Warning - Could not find spell_check_this: $ENV{spell_check_this_config} (spell-check-this-error)\n" }' "$workflow_path"
          else
            echo "?:0:1, Warning - Could not find spell_check_this: $spell_check_this_config (spell-check-this-error)"
          fi
        ) >> "$early_warnings"
      else
        mkdir -p "$spelling_config"
        cp -R "$spell_check_this_repo/$spell_check_this_config"/* "$spelling_config"
        spell_check_this_repo_url=$(cd "$spell_check_this_repo"; git remote get-url origin)
        (
          echo "mkdir -p '$spelling_config'"
          echo 'cp -i -R $('
          echo 'cd $(mktemp -d)'
          echo "git clone --depth 1 --no-tags $spell_check_this_repo_url ${spell_check_this_repo_branch:+--branch "$spell_check_this_repo_branch"} . > /dev/null 2> /dev/null"
          echo "cd '$spell_check_this_config'; pwd"
          echo ")/* '$spelling_config'"
          echo "git add '$spelling_config'"
        ) > "$instructions_preamble"
        if [ ! -e "$data_dir/spell_check_this.json" ]; then
          spell_check_this_repo_branch=$(git -C "$spell_check_this_repo" branch --show-current)
          echo '{}' |
          jq -r \
            --arg config "$spelling_config" \
            --arg url "$spell_check_this_repo_url" \
            --arg branch "$spell_check_this_repo_branch" \
            --arg path "$spell_check_this_config" \
          '.config=$config|.url=$url|.branch=$branch|.path=$path' > "$data_dir/spell_check_this.json"
        fi
        add_spell_check_this_text=" using the spell-check-this repository,"
      fi
    fi
  fi
  get_project_files word_expectations.words "$expect_path"
  get_project_files expect.txt "$expect_path"
  get_project_files_deprecated word_expectations.words whitelist.txt "$expect_path"
  expect_files="$from_expanded"
  expect_file="$from"
  if [ -n "$expect_files" ]; then
    expect_notes="$(mktemp)"
    expect_collated="$(mktemp)"
    echo "$expect_files" | xargs env INPUT_USE_SARIF='' "$word_splitter" 2> /dev/null |
    INPUT_USE_SARIF='' INPUT_DISABLE_CHECKS=noisy-file "$word_collator" 2> "$expect_notes" > "$expect_collated"
    perl -pe 's/ \(.*\)//' "$expect_collated" > "$expect_path"
    "$expect_collator" "$expect_collated" "$expect_notes" >> "$early_warnings"
  else
    touch "$expect_path"
  fi
  new_expect_file="$append_to"
  get_project_files file_ignore.patterns "$excludelist_path"
  get_project_files excludes.txt "$excludelist_path"
  excludes_files="$from_expanded"
  excludes_file="$from"
  if [ -s "$excludes_path" ]; then
    cp "$excludes_path" "$excludes"
  fi
  expect_files="$expect_files" \
  excludes_files="$excludes_files" \
  new_expect_file="$new_expect_file" \
  excludes_file="$excludes_file" \
  spelling_config="${spelling_config:-"$bucket/$project/"}" \
  "$spellchecker/generate-apply.pl" > "$data_dir/apply.json"
  should_exclude_file=$data_dir/should_exclude.txt
  should_exclude_patterns=$data_dir/should_exclude.patterns
  remove_exclude_patterns=$data_dir/remove_exclude.patterns
  counter_summary_file=$data_dir/counter_summary.json
  candidate_summary="$data_dir/candidate_summary.txt"
  if [ "$INPUT_TASK" = 'spelling' ]; then
    get_project_files dictionary.words "$dictionary_path"
    get_project_files dictionary.txt "$dictionary_path"
    if [ -s "$dictionary_path" ]; then
      cp "$dictionary_path" "$dict"
    fi
    if [ ! -s "$dict" ]; then
      DICTIONARY_VERSION="${DICTIONARY_VERSION:-$INPUT_DICTIONARY_VERSION}"
      DICTIONARY_URL="${DICTIONARY_URL:-$INPUT_DICTIONARY_URL}"
      DICTIONARY_URL="$(
        DICTIONARY_URL="$DICTIONARY_URL" \
        DICTIONARY_VERSION="$DICTIONARY_VERSION" \
        perl -e '
          my $url = $ENV{DICTIONARY_URL};
          my $version=$ENV{DICTIONARY_VERSION};
          $url =~ s{\$DICTIONARY_VERSION}{$version}g;
          print $url;
        '
      )"
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
    CACHE_DICTIONARIES=$(mktemp)
    if [ -n "$INPUT_CHECK_EXTRA_DICTIONARIES" ]; then
      begin_group 'Retrieving check extra dictionaries'
      build_dictionary_alias_pattern
      check_extra_dictionaries="$(
        echo "$INPUT_EXTRA_DICTIONARIES $INPUT_EXTRA_DICTIONARIES $INPUT_CHECK_EXTRA_DICTIONARIES" |
        words_to_lines |
        sort |
        uniq -u
      )"
      if [ -n "$check_extra_dictionaries" ]; then
        check_extra_dictionaries_canary=$(mktemp)
        export check_extra_dictionaries_dir="$(get_extra_dictionaries check "$check_extra_dictionaries" "$check_extra_dictionaries_canary")"
        if [ ! -e "$check_extra_dictionaries_canary" ]; then
          echo 0 > "$CACHE_DICTIONARIES"
        else
          :
          # should handle hunspell
        fi
      fi
      end_group
    fi
    if [ -n "$INPUT_EXTRA_DICTIONARIES" ]; then
      begin_group 'Retrieving extra dictionaries'
      build_dictionary_alias_pattern
      extra_dictionaries_canary=$(mktemp)
      extra_dictionaries_dir="$(get_extra_dictionaries extra "$INPUT_EXTRA_DICTIONARIES" "$extra_dictionaries_canary")"
      if [ -n "$extra_dictionaries_dir" ]; then
        if [ ! -e "$extra_dictionaries_canary" ]; then
          message="Problems were encountered retrieving extra dictionaries ($INPUT_EXTRA_DICTIONARIES)."
          echo 0 > "$CACHE_DICTIONARIES"
          if [ "$GITHUB_EVENT_NAME" = 'pull_request_target' ]; then
            message=$(echo "
            $message

            This workflow is running from a ${b}pull_request_target${b} event. In order to test changes to
            dictionaries, you will need to use a workflow that is **not** associated with a ${b}pull_request${b} as
            pull_request_target relies on the configuration of the destination branch, not the branch which
            you are changing.
            " | strip_lead)
          fi
          github_step_summary_likely_fatal_event \
            'Dictionary not found' \
            "$message" \
            'dictionary-not-found'
          if [ -n "$INPUT_CHECK_EXTRA_DICTIONARIES" ]; then
            end_group
            begin_group 'Check default extra dictionaries'
            check_extra_dictionaries="$(
              "$get_yaml_value" "$GITHUB_ACTION_PATH/action.yml" inputs.check_extra_dictionaries.default |
              words_to_lines |
              sort |
              uniq -u
            )"
            if [ -n "$check_extra_dictionaries" ]; then
              INPUT_DICTIONARY_SOURCE_PREFIXES=$(
              "$get_yaml_value" "$GITHUB_ACTION_PATH/action.yml" inputs.dictionary_source_prefixes.default)
              dictionary_alias_pattern=
              build_dictionary_alias_pattern
              fallback_extra_dictionaries_canary=$(mktemp)
              fallback_extra_dictionaries_dir="$(get_extra_dictionaries fallback "$check_extra_dictionaries" "$fallback_extra_dictionaries_canary")"
              if [ ! -e "$fallback_extra_dictionaries_canary" ]; then
                fallback_extra_dictionaries_dir=
                echo 0 > "$CACHE_DICTIONARIES"
              fi
              if [ -d "$fallback_extra_dictionaries_dir" ]; then
                # should handle hunspell
                if [ -n "$check_extra_dictionaries_dir" ] && [ -d "$check_extra_dictionaries_dir" ]; then
                  (cd "$fallback_extra_dictionaries_dir"; mv ./* "$check_extra_dictionaries_dir")
                else
                  check_extra_dictionaries_dir="$fallback_extra_dictionaries_dir"
                  fallback_extra_dictionaries_dir=
                fi
                extra_dictionary_limit=100
              fi
            fi
          fi
        fi
        if [ -d "$extra_dictionaries_dir" ]; then
          if find "$extra_dictionaries_dir" -type f -name '*.aff' -o -name '*.dic' | grep -q .; then
            hunspell_dictionary_path=$(mktemp -d)
          fi
          (
            cd "$extra_dictionaries_dir"
            if [ -d "$hunspell_dictionary_path" ]; then
              mv ./*.aff ./*.dic "$hunspell_dictionary_path" 2>/dev/null || true
            fi
            # Items that aren't proper should be moved to patterns instead
            etag_temp=$(mktemp -d)
            mv ./*.etag "$etag_temp"
            "$spellchecker/dictionary-word-filter.pl" ./* | sort -u >> "$dict"
            mv "$etag_temp"/* .
          )
        fi
      fi
      end_group
    fi
    if to_boolean "$INPUT_CACHE_DICTIONARIES" &&
        [ -s "$CACHE_DICTIONARIES" ] &&
        grep -q 1 "$CACHE_DICTIONARIES"; then
      echo "CACHE_DICTIONARIES=1" >> "$output_variables"
    fi
    get_project_files dictionary_additions.words "$allow_path"
    get_project_files allow.txt "$allow_path"
    if [ -s "$allow_path" ]; then
      cat "$allow_path" >> "$dict"
    fi
    get_project_files dictionary_removals.patterns "$reject_path"
    get_project_files reject.txt "$reject_path"
    if [ -s "$reject_path" ]; then
      dictionary_temp="$(mktemp)"
      if grep_v_string '^('"$(xargs < "$reject_path" | tr " " '|')"')$' < "$dict" > "$dictionary_temp"; then
        cat "$dictionary_temp" > "$dict"
      fi
    fi
    get_project_files file_exclusive.patterns "$only_path"
    get_project_files only.txt "$only_path"
    if [ -s "$only_path" ]; then
      cp "$only_path" "$only"
    fi
    get_project_files line_forbidden.patterns "$forbidden_path"
    get_project_files candidate.patterns "$candidates_path"
  fi
  extra_dictionaries_cover_entries="$(mktemp)"
  get_project_files line_masks.patterns "$patterns_path"
  get_project_files patterns.txt "$patterns_path"
  new_patterns_file="$append_to"
  if [ -s "$patterns_path" ]; then
    cp "$patterns_path" "$patterns"
  fi
  get_project_files advice.md "$advice_path"
  if [ ! -s "$advice_path" ]; then
    get_project_files_deprecated advice.md advice.txt "$advice_path_txt"
  fi
  get_project_files sarif.json "$sarif_overlay_path"

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

get_before() {
  if [ -z "$BEFORE" ]; then
    COMPARE="$(jq -r '.compare // empty' "$GITHUB_EVENT_PATH" 2>/dev/null)"
    AFTER="${GITHUB_HEAD_REF:-$GITHUB_SHA}"
    if [ -n "$COMPARE" ]; then
      BEFORE="$(echo "$COMPARE" | perl -ne 'if (m{/compare/(.*)\.\.\.}) { print $1; } elsif (m{/commit/([0-9a-f]+)$}) { print "$1^"; };')"
      BEFORE="$(call_curl \
        "$GITHUB_API_URL/repos/$GITHUB_REPOSITORY/commits/$BEFORE" | jq -r '.sha // empty')"
    elif [ -n "$GITHUB_BASE_REF" ]; then
      BEFORE="$GITHUB_BASE_REF"
    elif [ -n "$AFTER" ] && [ -n "$GITHUB_REF_NAME" ]; then
      BEFORE="$(git reflog --no-abbrev --decorate|grep -v "$AFTER" |grep "$GITHUB_REF_NAME" | head -1 | perl -pe 's/\s.*//')"
    else
      BEFORE="$(git rev-parse "$AFTER"~)"
    fi
    if [ -e .git/shallow ]; then
      UNSHALLOW=--unshallow
      echo "Unshallowing (this may take a while)" >&2
    fi
    git_fetch_log="$(mktemp)"
    git_fetch_err="$(mktemp)"
    if ! git fetch -f origin ${UNSHALLOW:+"$UNSHALLOW"} "$BEFORE":refs/private/before "$AFTER:refs/private/after" > "$git_fetch_log" 2> "$git_fetch_err"; then
      echo "git fetch origin ${UNSHALLOW:+"$UNSHALLOW"} '$BEFORE:refs/private/before' '$AFTER:refs/private/after' -- failed:"
      cat "$git_fetch_err"
      cat "$git_fetch_log"
      if ! git fetch -f . "$BEFORE":refs/private/before "$AFTER:refs/private/after" > "$git_fetch_log" 2> "$git_fetch_err"; then
        echo "git fetch . '$BEFORE:refs/private/before' '$AFTER:refs/private/after' -- also failed:"
        cat "$git_fetch_err"
        cat "$git_fetch_log"
      fi
    fi
  fi
}

append_file_to_file_list() {
  echo "$1" | tr "\n" "\0" >> "$file_list"
}

append_commit_message_to_file_list() {
  commit_message_file="$commit_messages/$1.message"
  git log -1 --format='%B%n' "$1" > "$commit_message_file"
  append_file_to_file_list "$commit_message_file"
}

get_file_list() {
  xargs -0 -n1 < "$file_list"
}

build_file_list() {
  (
    if to_boolean "$INPUT_ONLY_CHECK_CHANGED_FILES"; then
      get_before
    fi
    if [ -n "$BEFORE" ]; then
      echo "Only checking files changed from $BEFORE" >&2
      git diff -z --name-only refs/private/before
    else
      INPUT_ONLY_CHECK_CHANGED_FILES=''
      git 'ls-files' -z 2> /dev/null
    fi
  ) |\
    exclude_file="$excludes" \
    only_file="$only" \
      "$scope_files" > "$1"
}

run_spell_check() {
  echo "internal_state_directory=$data_dir" >> "$output_variables"

  synthetic_base="/tmp/check-spelling/$GITHUB_REPOSITORY"
  echo "^\Q$synthetic_base/\E" >> "$patterns"
  mkdir -p "$synthetic_base"

  build_file_list "$file_list"
  if to_boolean "$INPUT_CHECK_FILE_NAMES"; then
    if [ -s "$file_list" ]; then
      check_file_names="$synthetic_base/paths-of-checked-files.txt"
      get_file_list > "$check_file_names"
      append_file_to_file_list "$check_file_names"
    fi
  fi
  if [ -n "$INPUT_CHECK_COMMIT_MESSAGES" ]; then
    commit_messages="$synthetic_base/commits"
    mkdir -p "$commit_messages"
    if [ 1 = "$(echo "$INPUT_CHECK_COMMIT_MESSAGES" | "$find_token" commits)" ]; then
      get_before
      log_revs=$(mktemp)
      git log --format='%H' refs/private/before..refs/private/after > "$log_revs"
      if [ -n "$workflow_path" ]; then
        workflow_blame=$(mktemp)
        git blame HEAD -- "$workflow_path" > "$workflow_blame"
        workflow_commits_revs=$(mktemp)
        "$get_commits_for_check_commit_message" "$workflow_blame" | sort -u |xargs -n1 git rev-parse > "$workflow_commits_revs"
        clip_log=$(mktemp)
        while IFS= read -r commit_sha; do
          grep -q "$commit_sha" "$log_revs" && echo "$commit_sha" || true
        done < "$workflow_commits_revs" > "$clip_log"
        if [ -s "$clip_log" ]; then
          clipped_log_revs=$(mktemp)
          while IFS= read -r commit_sha; do
            git log --format='%H' "$commit_sha..refs/private/after" >> "$clipped_log_revs"
          done < "$clip_log"
          sort -u "$clipped_log_revs" > "$log_revs"
        fi
      fi
      while IFS= read -r commit_sha; do
        append_commit_message_to_file_list "$commit_sha"
      done < "$log_revs"
      if [ 1 = "$(echo "$INPUT_CHECK_COMMIT_MESSAGES" | "$find_token" commit)" ]; then
        # warning about duplicate flag
        echo > /dev/null
      fi
    elif [ 1 = "$(echo "$INPUT_CHECK_COMMIT_MESSAGES" | "$find_token" commit)" ]; then
      append_commit_message_to_file_list "${GITHUB_BASE_REF:-$GITHUB_REF}"
    fi

    pr_number="$(jq -r '.pull_request.number // empty' "$GITHUB_EVENT_PATH")"
    if [ -n "$pr_number" ]; then
      pr_details_path="$synthetic_base/pull-request/$pr_number"
      mkdir -p "$pr_details_path"
      if [ 1 = "$(echo "$INPUT_CHECK_COMMIT_MESSAGES" | "$find_token" title)" ]; then
        pr_title_file="$pr_details_path/summary.txt"
        jq -r .pull_request.title "$GITHUB_EVENT_PATH" > "$pr_title_file"
        append_file_to_file_list "$pr_title_file"
      fi
      if [ 1 = "$(echo "$INPUT_CHECK_COMMIT_MESSAGES" | "$find_token" description)" ]; then
        pr_description_file="$pr_details_path/description.txt"
        jq -r .pull_request.body "$GITHUB_EVENT_PATH" > "$pr_description_file"
        append_file_to_file_list "$pr_description_file"
      fi
    fi
  fi
  count="$(perl -e '$/="\0"; $count=0; while (<>) {s/\R//; $count++ if /./;}; print $count;' "$file_list")"
  if [ "$count" = "0" ]; then
    echo ":0:0 ... 0, Warning - No files to check. (no-files-to-check)" >> "$early_warnings"
  fi
  begin_group "Spell checking ($count) files"
  get_file_list
  end_group
  queue_size="$((count / job_count / 4))"
  if [ "$queue_size" -lt 4 ]; then
    queue_size="$((count / job_count))"
    if [ "$queue_size" -lt 1 ]; then
      queue_size=1
    fi
  fi

  begin_group 'Spell check'
  warning_output="$(mktemp -d)"/warnings.txt
  more_warnings="$(mktemp)"
  cat "$file_list" |\
  env -i \
    SHELL="$SHELL" \
    PATH="$PATH" \
    LC_ALL="C" \
    HOME="$HOME" \
    INPUT_LONGEST_WORD="$INPUT_LONGEST_WORD" \
    INPUT_SHORTEST_WORD="$INPUT_SHORTEST_WORD" \
    INPUT_LARGEST_FILE="$INPUT_LARGEST_FILE" \
    INPUT_DISABLE_CHECKS="$INPUT_DISABLE_CHECKS" \
    INPUT_CANDIDATE_EXAMPLE_LIMIT="$INPUT_CANDIDATE_EXAMPLE_LIMIT" \
    INPUT_USE_MAGIC_FILE="$INPUT_USE_MAGIC_FILE" \
    INPUT_IGNORE_PATTERN="$INPUT_IGNORE_PATTERN" \
    INPUT_UPPER_PATTERN="$INPUT_UPPER_PATTERN" \
    INPUT_LOWER_PATTERN="$INPUT_LOWER_PATTERN" \
    INPUT_NOT_LOWER_PATTERN="$INPUT_NOT_LOWER_PATTERN" \
    INPUT_NOT_UPPER_OR_LOWER_PATTERN="$INPUT_NOT_UPPER_OR_LOWER_PATTERN" \
    INPUT_PUNCTUATION_PATTERN="$INPUT_PUNCTUATION_PATTERN" \
    dict="$dict" \
    hunspell_dictionary_path="$hunspell_dictionary_path" \
    check_file_names="$check_file_names" \
    splitter_configuration="$splitter_configuration" \
  xargs -0 -n$queue_size "-P$job_count" "$word_splitter" |\
    expect="$expect_path" \
    warning_output="$warning_output" \
    more_warnings="$more_warnings" \
    should_exclude_file="$should_exclude_file" \
    counter_summary="$counter_summary_file" \
    unknown_word_limit="$INPUT_UNKNOWN_WORD_LIMIT" \
    candidates_path="$candidates_path" \
    candidate_summary="$candidate_summary" \
    check_file_names="$check_file_names" \
    timing_report="$timing_report" \
    "$word_collator" |\
  "$strip_word_collator_suffix" > "$run_output"
  word_splitter_status="${PIPESTATUS[2]} ${PIPESTATUS[3]}"
  check_file_names_warning="$(perl -i -e 'while (<>) { if (/\(noisy-file-list\)$/) { s/.*, Warning/Warning/; print STDERR; } else { print; } }' "$warning_output")"
  if [ -n "$check_file_names_warning" ]; then
    KEY=check_file_names \
    VALUE="$INPUT_CHECK_FILE_NAMES" \
    MESSAGE="$check_file_names_warning" \
    check_yaml_key_value "$workflow_path" >> "$more_warnings"
  fi
  cat "$more_warnings" >> "$warning_output"
  rm "$more_warnings"
  commit_messages="$commit_messages" \
  pr_details_path="$pr_details_path" \
  synthetic_base="$synthetic_base" \
  WARNINGS_LIST="$warnings_list" \
  perl -pi -e '
    my $GITHUB_SERVER_URL=$ENV{GITHUB_SERVER_URL};
    my $GITHUB_REPOSITORY=$ENV{GITHUB_REPOSITORY};
    my $commit_messages=$ENV{commit_messages};
    my $pr_details_path=$ENV{pr_details_path};
    my $synthetic_base=$ENV{synthetic_base};
    if (defined $commit_messages) {
      s<^$commit_messages/([0-9a-f]+)\.message><$GITHUB_SERVER_URL/$GITHUB_REPOSITORY/commit/$1#>;
    }
    if (defined $pr_details_path) {
      s<^$synthetic_base/pull-request/(\d+)/(?:description|summary).txt><$GITHUB_SERVER_URL/$GITHUB_REPOSITORY/pull/$1#>;
    }
    next if /\((?:$ENV{WARNINGS_LIST})\)$/;
    s{(^(?:.+?):(?:\d+):(?:\d+) \.\.\. (?:\d+),)\sWarning(\s-\s.+\s\(.*\))}{$1 Error$2}
    ' "$warning_output"
  cat "$warning_output"
  echo "warnings=$warning_output" >> "$output_variables"
  if to_boolean "$INPUT_USE_SARIF"; then
    SARIF_FILE="$(mktemp).sarif.json"
    echo UPLOAD_SARIF="$SARIF_FILE" >> "$GITHUB_ENV"
    warning_output="$warning_output" "$generate_sarif" > "$SARIF_FILE" || (
      echo "::error title=Sarif generation failed::Please file a bug (sarif-generation-failed)"
      cp "$spellchecker/sarif.json" "$SARIF_FILE"
    )
  fi
  end_group
  if [ "$word_splitter_status" != '0 0' ]; then
    echo "$word_splitter failed ($word_splitter_status)"
    quit 2
  fi
}

relative_note() {
  if [ -n "$bucket" ] && [ -n "$project" ]; then
    from="$(project_file_path "$file")"
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
      echo "git clone --depth 1 '$bucket' --single-branch --branch '$project' metadata; cp metadata/expect.txt .";;
    gs://*)
      echo "gsutil cp -Z '$(project_file_path expect.txt)' expect.txt";;
    *://*)
      echo "curl -L -s '$(project_file_path expect.txt)' -o expect.txt";;
  esac
}

calculate_exclude_patterns() {
  to_boolean "$INPUT_ONLY_CHECK_CHANGED_FILES" ] || \
  [ -s "$should_exclude_patterns" ] || \
  [ ! -s "$should_exclude_file" ] && \
    return
  if [ -s "$file_list" ]; then
    calculate_exclude_file_list="$file_list"
  else
    calculate_exclude_file_list=$(mktemp)
    build_file_list "$calculate_exclude_file_list" 2>/dev/null
  fi
  file_list="$calculate_exclude_file_list" \
  should_exclude_file="$should_exclude_file" \
  remove_excludes_file="$remove_exclude_patterns" \
  should_exclude_patterns="$should_exclude_patterns" \
  current_exclude_patterns="$excludes" \
    "$spellchecker/suggest-excludes.pl" ||
    echo "::error title=Excludes generation failed::Please file a bug (excludes-generation-failed)" >&2
}

remove_items() {
  if to_boolean "$INPUT_ONLY_CHECK_CHANGED_FILES"; then
    echo "<!-- Because only_check_changed_files is active, checking for obsolete items cannot be performed-->"
  else
    if [ ! -s "$remove_words" ]; then
      perl -ne 'next unless s/^-([^-])/$1/; s/\n/ /; print' "$diff_output" > "$remove_words"
    fi
    if [ -s "$remove_words" ]; then
      echo "
        <details><summary>Previously acknowledged words that are now absent
        </summary>$(cat "$remove_words")$N🫥$N</details>
      " | strip_lead_and_blanks
      echo "stale_words=$remove_words" >> "$output_variables"
    else
      rm "$fewer_misspellings_canary"
    fi
  fi
}

get_action_log_overview() {
  echo "$GITHUB_SERVER_URL/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID"
}

get_has_errors() {
  if [ -z "$has_errors" ] && [ -s "$counter_summary_file" ] && jq -r 'keys | .[]' "$counter_summary_file" | grep -E -v "$warnings_list" 2> /dev/null | grep -q .; then
    has_errors=1
  fi
}

get_job_info_and_step_info() {
  if [ -z "$step_number" ] && [ -z "$job_log" ]; then
    run_info=$(mktemp)
    if call_curl "$GITHUB_API_URL/repos/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID" > "$run_info" 2>/dev/null; then
      jobs_url=$(jq -r '.jobs_url // empty' "$run_info")
      if [ -n "$jobs_url" ]; then
        jobs_info=$(mktemp)
        if call_curl "$jobs_url" > "$jobs_info" 2>/dev/null; then
          job=$(mktemp)
          jq -r '.jobs[] | select(.status=="in_progress" and .runner_name=="'"$RUNNER_NAME"'" and .run_attempt=='"${GITHUB_RUN_ATTEMPT:-1}"')' "$jobs_info" > "$job" 2>/dev/null
          job_log=$(jq -r .html_url "$job")
          job_name=$(jq -r .name "$job")
          if [ -n "$job_log" ]; then
            step_info=$(mktemp)
            jq -r '[.steps[] | select(.status=="pending") // empty]' "$job" > "$step_info" 2>/dev/null
            if [ -s "$step_info" ]; then
              step_name=$(jq -r '.[0].name // empty' "$step_info")
            else
              step_name='check-spelling'
              jq -r '[.steps[] | select(.status=="queued" and .name=="'"$step_name"'")]' "$job" > "$step_info" 2>/dev/null
            fi
            step_number=$(jq -r .[0].number "$step_info")
          fi
        fi
      fi
    fi
  fi
  if [ -n "$step_number" ] && [ -n "$job_log" ] && [ -n "$step_number" ] && [ -n "$step_name" ]; then
    echo "$job_log"
    echo "$job_name"
    echo "$step_number"
    echo "$step_name"
  fi
}

get_action_log() {
  if [ -z "$action_log" ]; then
    if [ -s "$action_log_ref" ]; then
      action_log="$(cat "$action_log_ref")"
    else
      action_log="$(get_action_log_overview)"

      job_info_and_step_info="$(get_job_info_and_step_info)"
      if [ "$(echo "$job_info_and_step_info" | line_count)" -eq 4 ]; then
        job_log=$(echo "$job_info_and_step_info" | head -1)
        job_name=$(echo "$job_info_and_step_info" | head -2 | tail -1)
        step_number=$(echo "$job_info_and_step_info" | head -3 | tail -1)
        step_name=$(echo "$job_info_and_step_info" | head -4 | tail -1)
        if [ -n "$job_log" ] && [ -n "$step_number" ] && [ -n "$job_name" ]; then
          action_log="$job_log#step:$step_number:1"
          echo "$job_name/${step_number}_${step_name}.txt" > "$action_log_file_name"
        fi
      fi
      echo "$action_log" > "$action_log_ref"
      echo "${job_log##*/}" > "$job_id_ref"
    fi
  fi
  echo "$action_log"
}

repo_clone_note() {
  echo "
        ... in a clone of the [$remote_url_ssh]($remote_url_https) repository
        on the $b$remote_ref$b branch ([:information_source: how do I use this?](
        https://github.com/check-spelling/check-spelling/wiki/Accepting-Suggestions)):
  "
}

spelling_warning() {
  OUTPUT="### :red_circle: $1
"
  spelling_body "$2" "$3" "$4"
  if [ -n "$OUTPUT" ]; then
    post_summary
  fi
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
  if [ -n "$OUTPUT" ]; then
    post_summary
  fi
  if [ -n "$VERBOSE" ]; then
    post_commit_comment
  else
    echo "$OUTPUT"
  fi
}
spelling_body() {
  message="$1"
  extra="$2"
  err="$3"
  action_log_markdown="the [:scroll:action log]($(get_action_log))"
  memo="[:memo: job summary]($jobs_summary_link#summary-$(cat "$job_id_ref" 2>/dev/null))"
  if to_boolean "$INPUT_USE_SARIF"; then
    pr_number=$(jq -r '.pull_request.number // empty' "$GITHUB_EVENT_PATH")
    if [ -n "$pr_number" ]; then
      sarif_report_query="pr:$pr_number"
    else
      sarif_report_query="branch:${GITHUB_HEAD_REF:-$GITHUB_REF_NAME}"
    fi
    sarif_report="[:angel: SARIF report]($GITHUB_SERVER_URL/$GITHUB_REPOSITORY/security/code-scanning?query=is:open+$sarif_report_query),"
    # check-spelling here corresponds to the uses github/codeql-action/upload-sarif / with / category
    code_scanning_results_run=$(GH_TOKEN="$GITHUB_TOKEN" gh api "/repos/$GITHUB_REPOSITORY/commits/${GITHUB_HEAD_SHA:-$GITHUB_SHA}/check-runs" -q '.check_runs|map(select(.app.id==57789 and .name=="check-spelling"))[0].url // empty' || true)
    if [ -n "$code_scanning_results_run" ]; then
      code_scanning_results_url=$(GH_TOKEN="$GITHUB_TOKEN" gh api "$code_scanning_results_run" -q '.html_url // empty')
      sarif_report="$sarif_report [:rotating_light: alerts]($code_scanning_results_url),"
    fi
    or_markdown=','
  else
    or_markdown=' or'
  fi

  case "$GITHUB_EVENT_NAME" in
    pull_request|pull_request_target)
      details_note="See the [:open_file_folder: files]($(jq -r .pull_request.html_url "$GITHUB_EVENT_PATH")/files/) view, $action_log_markdown, $sarif_report or $memo for details.";;
    push)
      details_note="See $action_log_markdown${sarif_report:+,} $sarif_report or $memo for details.";;
    *)
      details_note=$(echo "<!-- If you can see this, please [file a bug](https://github.com/$GH_ACTION_REPOSITORY/issues/new)
        referencing this comment url, as the code does not expect this to happen. -->" | strip_lead);;
  esac
  if [ -z "$err" ] && [ -e "$fewer_misspellings_canary" ]; then
    output_remove_items="$N$(remove_items)"
  fi
    if [ -n "$err" ] && [ -e "$fewer_misspellings_canary" ]; then
      cleanup_text=" and remove the previously acknowledged and now absent words"
    fi
    if [ -n "$GITHUB_HEAD_REF" ]; then
      remote_url_ssh="$(jq -r '.pull_request.head.repo.ssh_url // empty' "$GITHUB_EVENT_PATH")"
      remote_url_https="$(jq -r '.pull_request.head.repo.clone_url // empty' "$GITHUB_EVENT_PATH")"
      if should_patch_head; then
        remote_ref="$GITHUB_HEAD_REF"
      else
        remote_ref="$GITHUB_BASE_REF"
      fi
    else
      remote_url_ssh="$(jq -r '.repository.ssh_url // empty' "$GITHUB_EVENT_PATH")"
      remote_url_https="$(jq -r '.repository.clone_url // empty' "$GITHUB_EVENT_PATH")"
      remote_ref="$GITHUB_REF"
    fi
    if [ -z "$remote_url_ssh" ]; then
      remote_url_ssh="$(git remote get-url --push origin 2>/dev/null || true)"
    fi
    if [ -z "$remote_url_https" ]; then
      remote_url_https="$(echo "$remote_url_ssh" | perl -pe 's{(?:git\@|^)github\.com:}{https://github.com/}')"
    fi
    if [ -z "$remote_ref" ]; then
      remote_ref="$(perl -pe 's{^ref: }{}' .git/HEAD)"
    fi
    remote_ref=${remote_ref#refs/heads/}
    if [ -s "$extra_dictionaries_cover_entries" ]; then
      expected_item_count="$(line_count < "$expect_path")"
      if [ "$expected_item_count" -gt 0 ]; then
        expect_details="This includes both **expected items** ($expected_item_count) from $expect_files and **unrecognized words** ($unknown_count)
        "
        expect_head=" (expected and unrecognized)"
      fi

      extra_dictionaries_cover_entries_limited="$(mktemp)"
      head -"$extra_dictionary_limit" "$extra_dictionaries_cover_entries" > "$extra_dictionaries_cover_entries_limited"
      if [ -n "$workflow_path" ]; then
        workflow_path_hint=" (in $b$workflow_path$b)"
      fi
      action_ref=$(get_action_repo_info)
      if [ -n "$action_ref" ]; then
        action_ref_hint=" for ${b}uses: ${action_ref}${b}"
        inline_with_hint=" in its ${b}with${b}"
      fi
      if [ -n "$INPUT_EXTRA_DICTIONARIES" ]; then
        extra_dictionaries_hint=' to `extra_dictionaries`'
      else
        with_hint='
              with:
                extra_dictionaries:'
      fi
      output_dictionaries="$(echo "
        <details><summary>Available :books: dictionaries could cover words$expect_head not in the :blue_book: dictionary</summary>

        $expect_details

        Dictionary | Entries | Covers | Uniquely
        -|-|-|-
        $(perl -pe 's/ \((\d+)\) covers (\d+) of them \((\d+) uniquely\)/|$1|$2|$3|/ || s/ \((\d+)\) covers (\d+) of them/|$1|$2||/' "$extra_dictionaries_cover_entries_limited")

        Consider adding them$workflow_path_hint$action_ref_hint$inline_with_hint$extra_dictionaries_hint:
        $B yml$with_hint$n$(
          perl -pe 's/\s.*//;s/^/                  /;s{\[(.*)\]\(.*}{$1}' "$extra_dictionaries_cover_entries_limited"
        )
        $B
        To stop checking additional dictionaries, add$workflow_path_hint$action_ref_hint$inline_with_hint:
        $B yml
        check_extra_dictionaries: ''
        $B

        </details>
        " | perl -pe 's/^ {8}//')"
    fi
    if [ -s "$should_exclude_file" ]; then
      calculate_exclude_patterns
      echo "skipped_files=$should_exclude_file" >> "$output_variables"
      if ! grep -qE '\w' "$should_exclude_patterns"; then
        echo '::error title=Excludes generation failed::Please file a bug (excludes-generation-failed)' >&2
      else
        echo "should_exclude_patterns=$should_exclude_patterns" >> "$output_variables"
        exclude_files_text="update file exclusions"
        output_excludes="$(echo "
          <details><summary>Some files were automatically ignored :see_no_evil:</summary>

          These sample patterns would exclude them:
          $B
          $(cat "$should_exclude_patterns")
          $B"| strip_lead)"
        if [ "$(line_count < "$should_exclude_file")" -gt 10 ]; then
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
        if ! to_boolean "$INPUT_ONLY_CHECK_CHANGED_FILES"; then
          can_offer_to_apply=1
        fi
      fi
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
      if [ -s "$counter_summary_file" ]; then
        warnings_details="$(echo "
          [$event_icon ${event_title}](https://github.com/check-spelling/check-spelling/wiki/Event-descriptions) | Count
          -|-
          $(jq -r 'to_entries[] | "[:information_source: \(.key)](https://github.com/check-spelling/check-spelling/wiki/Event-descriptions#\(.key)) | \(.value)"' "$counter_summary_file" | WARNINGS_LIST="$warnings_list" perl -pe 'next if /$ENV{WARNINGS_LIST}/; s/information_source/x/')

          See [$event_icon Event descriptions](https://github.com/check-spelling/check-spelling/wiki/Event-descriptions) for more information.
          " | strip_lead)"
      else
        warnings_details="_Could not get warning list from ${counter_summary_file}_"
      fi
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
    if [ -s "$candidate_summary" ]; then
      pattern_suggestion_count=$(perl -ne 'next if /^#/;next unless /\S/;print' "$candidate_summary"|line_count)
      output_candidate_pattern_suggestions="$(echo "
        <details><summary>Pattern suggestions :scissors: ($pattern_suggestion_count)</summary>

        You could add these patterns to $b$new_patterns_file$b:
        $B
        # Automatically suggested patterns
        $(
        cat "$candidate_summary"
        )

        $B

        </details>
      " | strip_lead)"
    fi
    if ! to_boolean "$INPUT_ONLY_CHECK_CHANGED_FILES" && [ -n "$patch_add" ]; then
      can_offer_to_apply=1
      accept_words_text="accept $add_spell_check_this_text these unrecognized words as correct$cleanup_text"
    fi
    if [ "$can_offer_to_apply" = 1 ]; then
      if [ -n "$accept_words_text" ] && [ -n "$exclude_files_text" ]; then
        accept_conjunction=' and '
        if [ -n "$add_spell_check_this_text" ]; then
          accept_conjunction=', and '
        fi
      fi
      accept_heading="To $accept_words_text$accept_conjunction$exclude_files_text"
      output_accept_script="$(echo "
        <details><summary>$accept_heading,
        you could run the following commands</summary>
        $(repo_clone_note)
        $(relative_note)

        $B sh
        $err
        $B
        </details>
        " | strip_lead)"
      if [ -s "$advice_path" ]; then
        output_advice="$N$(cat "$advice_path")$n"
      fi
      if offer_quote_reply; then
        output_quote_reply_placeholder="$n<!--QUOTE_REPLY-->$n"
      fi
    fi
    OUTPUT=$(echo "$n$report_header$n$OUTPUT$details_note$N$message$extra$output_remove_items$output_excludes$output_excludes_large$output_excludes_suffix$output_accept_script$output_quote_reply_placeholder$output_dictionaries$output_candidate_pattern_suggestions$output_warnings$output_advice
      " | perl -pe 's/^\s+$/\n/;'| uniq)
}

quit() {
  echo "::remove-matcher owner=check-spelling::"
  echo "::remove-matcher owner=check-spelling-https::"
  status="$1"
  if { [ -z "$status" ] || [ "$status" -eq 0 ] ; } && [ -n "$has_errors" ]; then
    status=1
  fi
  case "$status" in
    0) followup='';;
    1) followup='comment';;
    2) followup='debug';;
    3) followup='collapse_previous_comment';;
  esac
  echo "result_code=$status" >> "$GITHUB_OUTPUT"
  echo "followup=$followup" >> "$GITHUB_OUTPUT"
  echo "$followup" > "$data_dir/followup"
  echo "result_code=$status" >> "$GITHUB_ENV"
  echo "docker_container=$(perl -ne 'next unless m{:/docker/(.*)}; print $1;last' /proc/self/cgroup)" >> "$GITHUB_OUTPUT"
  cat "$output_variables" >> "$GITHUB_OUTPUT"
  if [ -n "$GH_OUTPUT_STUB" ]; then
    perl -pe 's/^(\S+)=(.*)/::set-output name=$1::$2/' "$GITHUB_OUTPUT"
  fi
  if ls "$data_dir" 2> /dev/null | grep -q .; then
    artifact="$(mktemp)"
    (
      cd "$data_dir"
      zip -q "$artifact.zip" ./*
      if [ -n "$ACT" ]; then
        if to_boolean "$INPUT_POST_COMMENT"; then
          encode_artifact "$artifact.zip"
        else
          echo "::warning ::input_post_comment is suppressed -- if you're looking for the complete comment archive, you probably should disable that suppression."
        fi
      fi
      rm ./*
      if [ -n "$INPUT_REPORT_TITLE_SUFFIX" ]; then
        build_artifact_suffix
      fi
      mv "$artifact.zip" "artifact$artifact_suffix.zip"
    )
  fi
  if to_boolean "$quit_without_error"; then
    exit
  fi
  exit ${status:+"$status"}
}

body_to_payload() {
  PAYLOAD="$(mktemp)"
  wrap_file_in_json 'body' "$BODY" > "$PAYLOAD"
  if to_boolean "$DEBUG"; then
    cat "$PAYLOAD" >&2
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
    method="$3"
  fi
  call_curl -L -S \
    ${method:+-X "$method"} \
    -H "Content-Type: application/json" \
    -H 'Accept: application/vnd.github.comfort-fade-preview+json' \
    ${payload:+--data "@$payload"} \
    "$comments_url"
}

track_comment() {
  HTML_COMMENT_URL="$(jq -r '.html_url // empty' "$response")"
  echo "Comment posted to ${HTML_COMMENT_URL:-"$COMMENT_URL"}"
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
      COMMENTS_URL="$(jq -r '.issue.comments_url // empty' "$file")";;
    pull_request|pull_request_target|pull_request_review_comment)
      COMMENTS_URL="$(jq -r '.pull_request.comments_url // empty' "$file")";;
    push|commit_comment)
      COMMENTS_URL="$(jq -r '.repository.commits_url // empty' "$file" | perl -pe 's#\{/sha}#/'"$sha"'/comments#')";;
  esac
}

trim_commit_comment() {
  stripped="$(mktemp)"
  (perl -p -i.raw -e '$/=undef; s{'"$2"'}{$1'"$3"'_Truncated, please see the log or artifact if available._\n}s; my $capture=$2; my $overview=q<'"$(get_action_log_overview)"'>; s{\n(See the) (\[action log\])}{\n$1 [overview]($overview) or $2}s unless m{\Q$overview\E}; print STDERR "$capture\n"' "$BODY") 2> "$stripped"
  body_to_payload
  previous_payload_size="$payload_size"
  payload_size="$("$file_size" "$PAYLOAD")"
  if [ "$payload_size" -lt "$previous_payload_size" ]; then
    echo "::warning ::Trimming '$1' ($previous_payload_size=>$payload_size) to get comment payload under GitHub size limit ($github_comment_size_limit)"
    cat "$stripped"
    rm "$stripped"
  elif ! diff -q "$BODY.raw" "$BODY" > /dev/null; then
    echo "Trimming $1 did not reduce the payload size ($previous_payload_size => $payload_size)"
    cp "$BODY.raw" "$BODY"
    payload_size="$previous_payload_size"
  fi
}

minimize_comment_body() {
  if [ "$payload_size" -le "$github_comment_size_limit" ]; then
    return 0
  fi
  trim_commit_comment 'Script' '(<details><summary>)To accept.* these unrecognized.*?</summary>().*?(?=</details>\n)' 'Script unavailable</summary>\n\n'
  if [ "$payload_size" -le "$github_comment_size_limit" ]; then
    return 0
  fi
  trim_commit_comment 'Stale words' '(<details><summary>Previously acknowledged words that are now absent.*?</summary>)(.*?)(?=</details>)' '\n\n'
  if [ "$payload_size" -le "$github_comment_size_limit" ]; then
    return 0
  fi
  trim_commit_comment 'Available dictionaries' '(<details><summary>Available dictionaries.*?</summary>\n*)(.*?)(?=</details>)' ''
  if [ "$payload_size" -le "$github_comment_size_limit" ]; then
    return 0
  fi
  trim_commit_comment 'Unrecognized words' '(<details><summary>Unrecognized words.*?</summary>\n*)\`\`\`(.*?)\`\`\`'
  if [ "$payload_size" -le "$github_comment_size_limit" ]; then
    return 0
  fi
  trim_commit_comment 'Files' '(<details><summary>Some files were automatically ignored.*</summary>)\n.*?\`\`\`(.*?)\`\`\`.*?(?=</details>)' '\n\n'
  if [ "$payload_size" -le "$github_comment_size_limit" ]; then
    return 0
  fi
  trim_commit_comment '' '(\nSee the [^\n]*\n)(.*)$' '\n\n'
  if [ "$payload_size" -le "$github_comment_size_limit" ]; then
    return 0
  fi
  cat "$BODY"
  body_to_payload
  echo "::warning ::Truncated comment payload ($payload_size) is likely to exceed GitHub size limit ($github_comment_size_limit)"
}

update_would_change_things() {
  { [ -n "$INPUT_SPELL_CHECK_THIS" ] && [ ! -d "$bucket/$project/" ] ; } ||
  [ -n "$patch_add" ] ||
  [ -n "$patch_remove" ] ||
  [ -s "$should_exclude_file" ]
}

add_talk_to_bot_message() {
  if offer_quote_reply && update_would_change_things; then
    quote_reply_insertion="$(mktemp)"
    (
      if [ -n "$INPUT_REPORT_TITLE_SUFFIX" ]; then
        apply_changes_suffix=" $INPUT_REPORT_TITLE_SUFFIX"
      fi
      echo
      echo "**OR**"
      echo
      echo "To have the bot accept them for you, reply quoting the following line:"
      echo "@check-spelling-bot apply [updates]($jobs_summary_link)$apply_changes_suffix."
    )> "$quote_reply_insertion"
    perl -e '$/=undef; my ($insertion, $body) = @ARGV; open INSERTION, "<", $insertion; my $text = <INSERTION>; close INSERTION; open BODY, "<", $body; my $content=<BODY>; close BODY; $content =~ s/<!--QUOTE_REPLY-->/$text/; open BODY, ">", $body; print BODY $content; close BODY;' "$quote_reply_insertion" "$1"
  fi
}

generate_sample_commit_help() {
  if [ ! -s "$tokens_file" ]; then
    return
  fi
  git remote set-url --push origin .
  archive_directory=$(mktemp -d)
  if [ -s "$tokens_file" ]; then
    cp "$tokens_file" "$archive_directory/tokens.txt"
  fi
  if [ -s "$remove_words" ]; then
    cp "$remove_words" "$archive_directory/remove_words.txt"
  fi
  cp "$data_dir/apply.json" "$archive_directory"
  apply_archive=$(mktemp).zip
  (
    cd "$archive_directory"
    zip -r "$apply_archive" . >/dev/null 2>/dev/null
  )
  if should_patch_head; then
    remote_ref="$GITHUB_HEAD_REF"
    remote_sha="$(get_pr_sha_from_url "$pull_request_url")"
    remote_sha="${remote_sha:-$GITHUB_SHA}"
  else
    remote_ref="${GITHUB_BASE_REF:-$GITHUB_REF_NAME}"
    if [ "$GITHUB_EVENT_NAME" = 'pull_request' ]; then
      remote_sha="$GITHUB_SHA"'~'
    else
      remote_sha="$GITHUB_SHA"
    fi
  fi
  git_stashed="$(git stash list|line_count)"
  git stash --include-untracked >/dev/null 2>/dev/null
  git_stashed_now="$(git stash list|line_count)"
  current_branch="$(git rev-parse --abbrev-ref HEAD)"
  if [ "$current_branch" = "HEAD" ]; then
    current_branch="$(git rev-parse HEAD)"
  fi
  git branch -f update-check-spelling-metadata "$remote_sha"
  git checkout update-check-spelling-metadata >/dev/null 2>/dev/null
  "$spellchecker/apply.pl" "$apply_archive"
  sender_login="$(jq -r '.sender.login // empty' "$GITHUB_EVENT_PATH")"
  get_github_user_and_email "$sender_login"
  created_at="$(date)" git_commit "check-spelling run ($GITHUB_EVENT_NAME) for $remote_ref" >/dev/null 2>/dev/null
  git_apply_commit="$(mktemp)"
  delim="@@@@$(shasum "$git_apply_commit" |perl -pe 's/\s.*//')--$(date +%s)"
  git format-patch HEAD~..HEAD --stdout > "$git_apply_commit"
  echo "<details><summary>To accept these unrecognized words as correct, you could apply this commit</summary>$N$(repo_clone_note | strip_lead)$n${B}sh"
  echo "git am <<'$delim'"
  cat "$git_apply_commit"
  echo "$delim$n$B$N"
  echo 'And `git push` ...'
  echo "</details>$N**OR**$N"
  git checkout "$current_branch" >/dev/null 2>/dev/null
  if [ "$git_stashed" != "$git_stashed_now" ]; then
    git stash pop >/dev/null 2>/dev/null
  fi
  git remote set-url --delete --push origin .
}

post_summary() {
  if [ -z "$GITHUB_STEP_SUMMARY" ]; then
    echo 'The $GITHUB_STEP_SUMMARY environment variable is unavailable'
    echo 'This feature is available in:'
    echo 'github.com - https://docs.github.com/actions/using-workflows/workflow-commands-for-github-actions#environment-files'
    echo 'GitHub Enterprise Server 3.6+ - https://docs.github.com/enterprise-server@3.6/actions/using-workflows/workflow-commands-for-github-actions#environment-files'
    echo 'GitHub Enterprise Cloud - https://docs.github.com/enterprise-cloud@latest/actions/using-workflows/workflow-commands-for-github-actions#environment-files'
    echo
    if [ -n "$ACT" ]; then
      echo 'For `act`, you can pass `--env GITHUB_STEP_SUMMARY=/dev/stdout`, however much of the logic has been reworked to rely on it.'
    fi
    return
  fi

  step_summary_draft=$(mktemp)
  echo "$OUTPUT" >> "$step_summary_draft"
  add_talk_to_bot_message "$step_summary_draft"
  sample_commit="$(mktemp)"
  generate_sample_commit_help >> "$sample_commit" ||
    echo 'generate_sample_commit_help failed, please file a bug' >&2
  if [ -s "$sample_commit" ]; then
    draft_with_commit="$(mktemp)"
    base="$step_summary_draft" insert="$sample_commit" perl -e '
      open BASE, "<", $ENV{base};
      while (<BASE>){
        if (!$found && $_=~/To accept /){
          $found=1;
          $/=undef;
          open INSERT, "<", $ENV{insert};
          print <INSERT>;
        }
        print;
      }' > "$draft_with_commit"
    cp "$draft_with_commit" "$step_summary_draft"
  fi
  if [ -n "$INPUT_SUMMARY_TABLE" ] && [ -s "$warning_output" ]; then
    begin_group 'Building summary table'
    summary_table="$(mktemp)"
    summary_budget=$((1024*1024 - $(char_count < "$step_summary_draft") - 100))
    summary_budget="$summary_budget" "$summary_tables" "$warning_output" > "$summary_table"
    if [ $summary_budget -gt "$(char_count < "$summary_table")" ]; then
      cat "$summary_table" >> "$step_summary_draft"
    else
      echo "::warning title=Summary Table skipped::Details too big to include in Step Summary. (summary-table-skipped)"
    fi
    end_group
  fi
  cat "$step_summary_draft" >> "$GITHUB_STEP_SUMMARY"
}
post_commit_comment() {
  if [ -z "$OUTPUT" ]; then
    return
  fi
  if to_boolean "$INPUT_POST_COMMENT"; then
    echo "Preparing a comment for $GITHUB_EVENT_NAME"
    set_comments_url "$GITHUB_EVENT_NAME" "$GITHUB_EVENT_PATH" "$GITHUB_SHA"
    if [ -n "$COMMENTS_URL" ] && [ -z "${COMMENTS_URL##*:*}" ]; then
      if [ ! -s "$BODY" ]; then
        echo "$OUTPUT" > "$BODY"
        add_talk_to_bot_message "$BODY"
        body_to_payload
        payload_size="$("$file_size" "$PAYLOAD")"
        github_comment_size_limit=65000
        minimize_comment_body
      else
        body_to_payload
      fi

      response="$(mktemp_json)"

      res=0
      unlock_pr
      keep_headers=1 comment "$COMMENTS_URL" "$PAYLOAD" > "$response" || res=$?
      lock_pr
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
          if [ "$response_code" -eq 403 ]; then
            if grep -q '#create-a-commit-comment' "$response"; then
              echo "Consider adding:"
              echo
              echo "permissions:"
              echo "  contents: write"
            elif grep -q '#create-an-issue-comment' "$response"; then
              echo "Consider adding:"
              echo
              echo "permissions:"
              echo "  pull-requests: write"
            fi
          fi
        fi
      else
        if to_boolean "$DEBUG"; then
          cat "$response"
        fi
        track_comment "$response"
      fi
      return
    fi
  fi
  echo "$OUTPUT"
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
  wrap_in_json 'query' "$query"
}

collapse_comment() {
  call_curl \
  -H "Content-Type: application/json" \
  --data-binary "$(collapse_comment_mutation "$@")" \
  "$GITHUB_GRAPHQL_URL"
}

should_collapse_previous_and_not_comment() {
  if [ -z "$COMMENTS_URL" ]; then
    set_comments_url "$GITHUB_EVENT_NAME" "$GITHUB_EVENT_PATH" "$GITHUB_SHA"
  fi
  previous_comment_node_id="$(get_previous_comment)"
  if [ -n "$previous_comment_node_id" ]; then
    echo "previous_comment=$previous_comment_node_id" >> "$GITHUB_OUTPUT"
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
  NEEDLE="$1" perl -ne 'next if m{$ENV{NEEDLE}}; print'
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
  instructions="$(mktemp)"
  if [ -n "$ACT" ]; then
    echo '# look for the instructions to extract `artifact.zip` from your log' >> "$instructions"
    jobs_summary_link=./artifact.zip
  fi
  calculate_exclude_patterns
  echo "curl -s -S -L 'https://raw.githubusercontent.com/$GH_ACTION_REPOSITORY/$GH_ACTION_REF/apply.pl' |
  perl - '$jobs_summary_link'" >> "$instructions"
  echo "$instructions"
}

set_patch_remove_add() {
  patch_remove="$(perl -ne 'next unless s/^-([^-])/$1/; s/\n/ /; print' "$diff_output")"
  begin_group 'New output'
    patch_add="$(perl -ne 'next unless s/^\+([^+])/$1/; s/\n/ /; print' "$diff_output")"

    get_has_errors
    if [ -z "$has_errors" ] && [ -z "$patch_add" ]; then
      begin_group 'No misspellings'
      expect_count="$(line_count < "$expect_path")"
      if [ "$expect_count" = 0 ]; then
        headline="There is currently _one_ expected item."
      else
        headline="There are currently $expect_count expected items."
      fi
      title="No new words with misspellings found"
      spelling_info "$title" "$headline" ""
      end_group
      should_collapse_previous_and_not_comment
      quit 0
    fi
  end_group
}

make_instructions() {
  instructions="$(generate_curl_instructions)"
  if [ -n "$instructions" ]; then
    cat "$instructions"
    rm "$instructions"
  fi
}

check_spelling_report() {
  if [ -s "$extra_dictionaries_json" ]; then
    "$output_covers" "$extra_dictionaries_json" > "$extra_dictionaries_cover_entries"
  elif [ -z "$INPUT_TASK" ] || [ "$INPUT_TASK" = 'spelling' ]; then
    if [ ! -s "$extra_dictionaries_json" ]; then
      if [ -n "$check_extra_dictionaries_dir" ]; then
        begin_group 'Check for extra dictionaries'
        (
          cd "$check_extra_dictionaries_dir";
          aliases="$dictionary_alias_pattern" extra_dictionaries="$check_extra_dictionaries" "$spellchecker/dictionary-coverage.pl" "$run_output" |
          perl -e 'print sort {
            $a =~ /^(\d+)-(\d+)-(\d+)-(.*)/;
            my ($a1, $a2, $a3, $a4) = ($1, $2, $3, $4);
            $b =~ /^(\d+)-(\d+)-(\d+)-(.*)/;
            my ($b1, $b2, $b3, $b4) = ($1, $2, $3, $4);
            (($b3 >= 3 || $a3 >= 3) && $b3 <=> $a3) ||
            $b1 <=> $a1 ||
            $b3 / $b2 <=> $a3 / $a2 ||
            $a2 <=> $b2 ||
            $a4 cmp $b4
          } <>;
          ' |
          perl -pe 's/^\S+ //' > "$extra_dictionaries_cover_entries"
        )
        end_group
      fi
    fi
  fi
  if [ -s "$extra_dictionaries_cover_entries" ]; then
    cover_log=$(mktemp)
    perl -pe 's/^.*?\[(\S+)\]\([^)]*\) \((\d+)\).* covers (\d+) of them \((\d+) uniquely\).*/{"$1":[$3, $2, $4]}/ || s/^.*?\[(\S+)\]\([^)]*\) \((\d+)\).* covers (\d+).*/{"$1":[$3, $2]}/' < "$extra_dictionaries_cover_entries" |
    tee "$cover_log" |
    jq -s '.' > "$extra_dictionaries_json" ||
    (
      echo "jq -s failed collecting extra_dictionaries_cover_entries from:"
      cat "$cover_log"
    ) >&2
    echo "suggested_dictionaries=$extra_dictionaries_json" >> "$output_variables"
  fi

  instructions=$(
    make_instructions
  )
  (echo "$patch_add" | tr " " "\n" | grep . || true) > "$tokens_file"
  unknown_count="$(line_count < "$tokens_file")"
  get_has_errors
  title='Please review'
  if [ -n "$patch_add" ]; then
    begin_group "Unrecognized ($unknown_count)"
  elif [ -n "$has_errors" ]; then
    begin_group "Errors ..."
  elif [ -n "$patch_remove" ]; then
    begin_group 'Fewer misspellings'
    title='There are now fewer misspellings than before'
  fi
  echo "unknown_words=$tokens_file" >> "$output_variables"
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
  if [ -n "$has_errors" ] || [ "$unknown_count" -gt 0 ]; then
    spelling_warning "$title" "$unknown_word_body" "$N$(remove_items)$n" "$instructions"
  else
    if [ -n "$INPUT_EXPERIMENTAL_COMMIT_NOTE" ]; then
      instructions="$(generate_curl_instructions)"

      . "$instructions" &&
      git_commit "$INPUT_EXPERIMENTAL_COMMIT_NOTE" &&
      git push origin "${GITHUB_HEAD_REF:-"$GITHUB_REF"}"
      spelling_info "$title" "" "Applied"
    else
      spelling_info "$title" "" "$instructions"
    fi
    should_collapse_previous_and_not_comment
  fi
  end_group
  echo "$title"
  if [ -n "$comment_author_id" ]; then
    previous_comment_node_id="$(get_previous_comment)"
    if [ -n "$previous_comment_node_id" ]; then
      reason=OUTDATED collapse_comment "$previous_comment_node_id" > /dev/null
    fi
  fi

  quit 1
}

hash_dictionaries() {
  if ! to_boolean "$INPUT_CACHE_DICTIONARIES"; then
    exit
  fi
  if [ -n "$INPUT_EXTRA_DICTIONARIES$INPUT_CHECK_EXTRA_DICTIONARIES" ]; then
    build_dictionary_alias_pattern
    dictionary_list=$(mktemp)
    (
      for url in $INPUT_EXTRA_DICTIONARIES $INPUT_CHECK_EXTRA_DICTIONARIES; do
        expand_dictionary_url "$url"
      done |
      sort -u > "$dictionary_list"
    )
    if [ -s "$dictionary_list" ]; then
      echo "DICTIONARY_URLS_HASH=$(
        shasum "$dictionary_list" |
        perl -pe 's/\s.*//'
      )" >> "$GITHUB_ENV"
    fi
  fi
  . "$spellchecker/common.sh"
  check_perl_libraries
  echo "perl-libraries=$perl_libs" >> "$GITHUB_OUTPUT"
  exit
}

if [ "$INPUT_TASK" = hash-dictionaries ]; then
  . "$spellchecker/common.sh"
  hash_dictionaries
fi
basic_setup
set_up_ua
define_variables
set_up_reporter
check_inputs
set_up_tools
dispatcher
set_up_files
welcome
run_spell_check
exit_if_no_unknown_words
compare_new_output
fewer_misspellings_canary="$(mktemp)"
set_patch_remove_add
check_spelling_report
