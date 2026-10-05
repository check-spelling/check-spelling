#!/bin/bash

no_comment() {
  echo "no-comment=1" >> "$GITHUB_OUTPUT"
  exit
}

# Check if run was skipped
gh_api_out=$(mktemp)
gh_api_err=$(mktemp)
gh api "/repos/$GITHUB_REPOSITORY/actions/runs/$RUN_ID/jobs" > "$gh_api_out" 2> "$gh_api_err"
check_run_url=$(jq -r '.jobs[] | select (.status=="completed" and (.name | startswith("Check Spelling"))).check_run_url // empty' "$gh_api_out")
if [ -n "$check_run_url" ]; then
  gh api "$check_run_url/annotations" > "$gh_api_out" 2> "$gh_api_err"
  if [ -n "$(jq -r '.[] | select(.title == "Workflow skipped").title // empty' "$gh_api_out")" ]; then
    no_comment
  fi
fi

"$spellchecker/gh-run-download.sh"

if [ -s artifact.zip ]; then
  if ! unzip -p artifact.zip followup | grep -q .; then
    no_comment
  fi
  exit
fi

canary=$(mktemp)
(
  if ! gh api "/repos/$GITHUB_REPOSITORY/actions/runs/$RUN_ID/artifacts?per_page=1" > "$gh_api_out" 2> "$gh_api_err"; then
    if grep -q 'HTTP 403' "$gh_api_err"; then
      act-summary
      if grep -q '#rate-limiting' "$gh_api_out"; then
        echo '# GitHub Rate limit hit'
        echo 'This generally happens when a repository triggers too many workflows in a short period of time. An admin or owner can rerun this workflow if necessary. Sorry about that.'
      else
        echo '# Workflow is missing permissions'
        echo 'Please add `actions: read` to enable check-spelling to retrieve the artifact it needs to post a comment. [more info](https://docs.check-spelling.dev/Workflow-Permissions#actions-read)'
      fi
      echo
      echo '#### Technical details'
      echo '```'
      cat "$gh_api_err"
      cat "$gh_api_out"
      echo
      echo '```'
      rm "$canary"
    fi
  fi
  if [ -e "$canary" ]; then
    echo '#### Could not find artifact'
    if [ "$RUN_ID" != "$GITHUB_RUN_ID" ]; then
      echo "See [run $RUN_ID]($GITHUB_SERVER_URL/$GITHUB_REPOSITORY/actions/runs/$RUN_ID) for details."
    else
      echo "Artifact retrieval failed, please check the list of [known issues](https://github.com/check-spelling/check-spelling/issues?q=is%3Aissue%20retrieve-comment) and [file an issue](https://github.com/check-spelling/check-spelling/issues/new?title=%60retrieve-comment%60%20scenario&body=Please%20provide%20details+preferably%20including%20a%20link%20to%20a%20workflow%20run,%20the%20configuration%20of%20the%20repository,%20and%20anything%20else%20you%20may%20know%20about%20the%20problem%2e) if you can't find a related issue."
    fi
  fi
) >> "$GITHUB_STEP_SUMMARY"
no_comment
