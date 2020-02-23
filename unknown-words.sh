#!/bin/bash
# This CI acceptance test is based on:
# https://github.com/jsoref/spelling/tree/04648bdc63723e5cdf5cbeaff2225a462807abc8
# It is conceptually `f` which runs `w` (spelling-unknown-word-splitter)
# plus `fchurn` which uses `dn` mostly rolled together.
set -e
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
export spellchecker=${spellchecker:-/app}
export temp='/tmp/spelling'

if [ "$GITHUB_EVENT_NAME" = "schedule" ]; then
  exec "$spellchecker/check-pull-requests.sh"
fi

dict="$temp/english.words"
whitelist_path="$spellchecker/whitelist.words.txt"
excludelist_path="$spellchecker/excludes.txt"
word_splitter="$spellchecker/spelling-unknown-word-splitter.pl"
run_output="$spellchecker/unknown.words.txt"
run_files="$temp/reporter-input.txt"
run_warnings="$temp/matcher.txt"
wordlist=$bucket/english.words.txt

project_file_path() {
  echo $bucket/$project/$1.txt
}

get_project_files() {
  file=$1
  dest=$2
  if [ ! -e "$dest" ] && [ -n "$bucket" ] && [ -n "$project" ]; then
    from=$(project_file_path $file)
    echo "Retrieving cached $file from $from"
    case "$from" in
      .*)
        cp $from $dest;;
      ssh://git@*|git@*)
        (
          cd $temp
          repo=$(echo "$bucket" | perl -pne 's#(?:ssh://|)git\@github.com[:/]([^/]*)/(.*.git)#https://github.com/$1/$2#')
          [ -d metadata ] || git clone --depth 1 $repo --single-branch --branch $project metadata
          cp metadata/$file.txt $dest
        );;
      gs://*)
        gsutil cp -Z $from $dest >/dev/null 2>/dev/null;;
      *://*)
        curl -L -s "$from" -o "$dest";;
    esac
  fi
}
get_project_files whitelist $whitelist_path
get_project_files excludes $excludelist_path

if [ -n "$debug" ]; then
  echo "Clean up from previous run"
fi
rm -f "$run_output"

echo "Checking spelling..."
if [ -n "$DEBUG" ]; then
  begin_group 'Excluded paths'
  if [ -e "$excludelist_path" ]; then
    echo 'Excluded paths:'
    cat "$excludelist_path"
  else
    echo 'No excluded paths file'
  fi
  end_group
fi

xargs_zero() {
  if [ $(uname) = "Linux" ]; then
    xargs --no-run-if-empty -0 -n1 "$@"
  else
    arguments="$*" "$spellchecker/xargs_zero"
  fi
}
begin_group 'Spell check'
(git 'ls-files' -z 2> /dev/null) |\
  "$spellchecker/exclude.pl" |\
  xargs_zero "$word_splitter" |\
  "$word_splitter" |\
  perl -p -n -e 's/ \(.*//' > "$run_output"
  word_splitter_status="${PIPESTATUS[2]} ${PIPESTATUS[3]}"
  end_group
  if [ "$word_splitter_status" != '0 0' ]; then
    echo "$word_splitter failed ($word_splitter_status)"
    exit 2
  fi

printDetails() {
  echo ''
  echo 'If you are ok with the output of this run, you will need to'
}

to_retrieve_whitelist() {
  case "$bucket" in
    '')
      echo '# no bucket defined -- you can specify one per the README.md using the file defined below:';;
    ssh://git@*|git@*)
      echo "git clone --depth 1 $bucket --single-branch --branch $project metadata; cp metadata/whitelist.txt .";;
    gs://*)
      echo gsutil cp -Z $(project_file_path whitelist) whitelist.txt;;
    *://*)
      echo curl -L -s "$(project_file_path whitelist)" -o whitelist.txt;;
    *)
      echo cp "$(project_file_path whitelist)" whitelist.txt;;
  esac
}
to_publish_whitelist() {
  case "$bucket" in
    '')
      echo '# no bucket defined -- copy the whitelist.txt to a bucket and configure it per the README.md';;
    ssh://git@*|git@*)
      echo "cp whitelist.txt metadata; (cd metadata; git commit whitelist.txt -m 'Updating whitelist'; git push)";;
    gs://*)
      echo gsutil cp -Z whitelist.txt $(project_file_path whitelist);;
    *://*)
      echo "# command to publish is not known. URL: $(project_file_path whitelist)";;
    *)
      echo cp whitelist.txt $(project_file_path whitelist);;
  esac
}

spelling_warning() {
  OUTPUT="$OUTPUT$spelling_header"
  OUTPUT="$OUTPUT
#### $1:
"
  spelling_body "$2" "$3"
  OUTPUT="$OUTPUT$spelling_footer"
  comment
}
spelling_info() {
  OUTPUT="$OUTPUT$spelling_header"
  if [ -z "$2" ]; then
    out="$1"
  else
    out="$1

$2"
  fi
  spelling_body "$out" "$3"
  OUTPUT="$OUTPUT$spelling_footer"
  if [ -n "$VERBOSE" ]; then
    comment
  fi
}
spelling_body() {
  err="$2"
  if [ -z "$err" ]; then
    OUTPUT="$1"
  else
    OUTPUT="$OUTPUT
$1

<details><summary>To accept these changes, run the following commands</summary>
(They can be run anywhere with permissions to update the bucket.)

"'```'"
$err
"'```
</details>'
  fi
}
new_words() {
  echo "$1" | perl -ne 'next unless s/^\+//;print'
}
bullet_words() {
  echo "$1" | perl -pne 's/^(.)/* $1/'
  rm -f "$run_warnings"
  export tokens="$1"
  base=$(cat $GITHUB_EVENT_PATH | jq -r '.pull_request.base.sha // .before // "HEAD^"' -M)
  if [ "$base" != "HEAD^" ]; then
    head=$(cat $GITHUB_EVENT_PATH | jq -r '.pull_request.head.sha' -M)
    if [ "$head" = "null" ]; then
      head=${GITHUB_SHA:-HEAD}
    fi
  else
    head=HEAD
  fi
  if [ -z "$ONLY_REPORT_HEAD" ] && !git log $base 2>/dev/null >/dev/null; then
    ONLY_REPORT_HEAD=1
  fi
  if [ -z "$ONLY_REPORT_HEAD" ]; then
    rm -f "$run_files"
    (
    export with_blame=1
    export HEAD=$head;
    git diff-tree --no-commit-id --name-only -r $base..$head -z 2> /dev/null |
    "$spellchecker/exclude.pl" |
    xargs_zero "$spellchecker/porcelain.pl" > "$run_files"
    $spellchecker/reporter.pl < "$run_files" > "$run_warnings.raw"
    )
    rm -f "$run_files"
  else
    git ls-files -z 2> /dev/null |
    "$spellchecker/exclude.pl" | xargs_zero $spellchecker/reporter.pl > "$run_warnings.raw"
  fi
  if [ -s "$run_warnings.raw" ]; then
    (
      end_group
      begin_group 'Misspellings'
      echo "::add-matcher::.git/reporter.json"
      cat "$run_warnings.raw"
      echo "::remove-matcher owner=jsoref-spelling::"
      cp $spellchecker/reporter.json .git/
    ) > "$run_warnings"
    rm -f "$run_warnings.raw"
  fi
}

quit() {
  if [ -n "$junit" ]; then
    exit
  fi
  exit $1
}

comment() {
  if [ -e "$run_warnings" ]; then
    cat "$run_warnings"
    rm -f "$run_warnings"
  fi
  if [ -n "$OUTPUT" ]; then
    echo "Preparing a comment"
    if [ -n "$GITHUB_EVENT_PATH" ]; then
      case "$GITHUB_EVENT_NAME" in
        pull_request)
          COMMENTS_URL=$(cat $GITHUB_EVENT_PATH | jq -r .pull_request.comments_url);;
        push)
          COMMENTS_URL=$(cat $GITHUB_EVENT_PATH | jq -r .repository.commits_url | perl -pne 's#\{/sha}#/'$GITHUB_SHA'/comments#');;
      esac
    fi
    if [ -n "$COMMENTS_URL" ] && [ -z "${COMMENTS_URL##*:*}" ]; then
      PAYLOAD=$(echo '{}' | jq --arg body "$OUTPUT" '.body = $body')
      echo $PAYLOAD
      echo $COMMENTS_URL
      curl -s -S \
           -H "Authorization: token $GITHUB_TOKEN" \
           --header "Content-Type: application/json" \
           -H 'Accept: application/vnd.github.comfort-fade-preview+json' \
           --data "$PAYLOAD" \
           "$COMMENTS_URL" ||
      true
    else
      echo "$OUTPUT"
    fi
  fi
}

if [ ! -e "$whitelist_path" ]; then
  begin_group 'No whitelist'
  title="No preexisting $whitelist_path file"
  instructions=$(
    echo 'cat > '"$whitelist_path"' <<EOF=EOF'
    cat "$run_output"
    echo EOF=EOF
    to_publish_whitelist
  )
      spelling_info "$title" "$(bullet_words "$(cat "$run_output")")" "$instructions"
  end_group
  quit 2
fi

begin_group 'Compare whitelist with new output'
sorted_whitelist="$temp/$(basename $whitelist_path)"
(sort -u -f "$whitelist_path" | grep . || true) > "$sorted_whitelist"
whitelist_path="$sorted_whitelist"

diff_output=$(diff -U0 "$whitelist_path" "$run_output" |grep -v "$spellchecker" || true)
end_group

if [ -z "$diff_output" ]; then
  begin_group 'No misspellings'
  title="No new words with misspellings found"
      spelling_info "$title" "There are currently $(wc -l $whitelist_path|sed -e 's/ .*//') whitelisted items." ""
  end_group
  quit 0
fi

begin_group 'New output'
new_output=$(diff -i -U0 "$whitelist_path" "$run_output" |grep -v "$spellchecker" |\
  perl -n -w -e 'next unless /^\+/; next if /^\+{3} /; s/^.//; print;')
end_group

make_instructions() {
  patch_remove=$(echo "$diff_output" | perl -ne 'next unless s/^-([^-])/$1/; print')
  patch_add=$(echo "$diff_output" | perl -ne 'next unless s/^\+([^+])/$1/; print')
  to_retrieve_whitelist
  echo "$(
  echo '('
  if [ -n "$patch_remove" ]; then
    echo 'egrep -v "$(echo "'"$patch_remove"'" | tr "\n" " " | perl -pne '"'"'s/^/^(/;s/\s$/)\$/;s/\s/|/g'"'"')" whitelist.txt;'
  else
    echo 'cat whitelist.txt;'
  fi
  if [ -n "$patch_add" ]; then
    echo 'echo "'
    echo "$patch_add"
    echo '"'
  fi
  echo ') | sort -u -f | grep . > new_whitelist.txt && mv new_whitelist.txt whitelist.txt'
)"
  to_publish_whitelist
}

if [ -z "$new_output" ]; then
  begin_group 'Fewer misspellings'
  title='There are now fewer misspellings than before'
  instructions=$(
    make_instructions
  )
      spelling_info "$title" "$(bullet_words "$(new_words "$diff_output")")" "$instructions"
  end_group
  quit
fi
begin_group 'New misspellings'
title='New misspellings found, please review'
instructions=$(
  make_instructions
)
    spelling_warning "$title" "$(bullet_words "$new_output")" "$instructions"
end_group
quit 1
