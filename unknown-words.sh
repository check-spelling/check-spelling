#!/bin/bash
# This CI acceptance test is based on:
# https://github.com/jsoref/spelling/tree/04648bdc63723e5cdf5cbeaff2225a462807abc8
# It is conceptually `f` which runs `w` (spelling-unknown-word-splitter)
# plus `fchurn` which uses `dn` mostly rolled together.
set -e
export spellchecker=${spellchecker:-/app}
. "$spellchecker/common.sh"

if [ "$GITHUB_EVENT_NAME" = "schedule" ]; then
  exec "$spellchecker/check-pull-requests.sh"
fi
if [ -z "$GITHUB_EVENT_PATH" ] || [ ! -e "$GITHUB_EVENT_PATH" ]; then
  GITHUB_EVENT_PATH=/dev/null
fi

dict="$temp/english.words"
whitelist_path="$temp/whitelist.words.txt"
excludelist_path="$temp/excludes.txt"
word_splitter="$spellchecker/spelling-unknown-word-splitter.pl"
run_output="$temp/unknown.words.txt"
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
    case "$from" in
      .*)
        append_to="$from"
        if [ -f "$from" ]; then
          echo "Retrieving $file from $from"
          cp "$from" $dest
          from_expanded="$from"
        else
          if [ ! -e "$from" ]; then
            ext=$(echo "$from" | sed -e 's/^.*\.//')
            from=$(echo $from | sed -e "s/\.$ext$//")
            echo "Retrieving $file from $from"
          fi
          if [ -d "$from" ]; then
            from_expanded=$from/*$ext
            append_to=$from/${GITHUB_SHA:-$(date +%Y%M%d%H%m%S)}.$ext
            sort -u -f $from_expanded | grep . > $dest
            echo "Retrieving $file from $from_expanded"
          else
            from_expanded=$(echo $from*$ext)
            if [ "$from*$ext" != "$from_expanded" ]; then
              sort -u -f $from_expanded | grep . > $dest
              append_to=$from_${GITHUB_SHA:-$(date +%Y%M%d%H%m%S)}.$ext
            else
              touch $dest
            fi
            echo "Retrieving $file from $from_expanded"
          fi
        fi;;
      ssh://git@*|git@*)
        (
          echo "Retrieving $file from $from"
          cd $temp
          repo=$(echo "$bucket" | perl -pne 's#(?:ssh://|)git\@github.com[:/]([^/]*)/(.*.git)#https://github.com/$1/$2#')
          [ -d metadata ] || git clone --depth 1 $repo --single-branch --branch $project metadata
          cp metadata/$file.txt $dest 2> /dev/null || touch $dest
        );;
      gs://*)
        echo "Retrieving $file from $from"
        gsutil cp -Z $from $dest >/dev/null 2>/dev/null || touch $dest;;
      *://*)
        echo "Retrieving $file from $from"
        curl -L -s "$from" -o "$dest" || touch $dest;;
    esac
  fi
}
get_project_files whitelist $whitelist_path
whitelist_files=$from_expanded
new_whitelist_file=$append_to
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
(
  export exclude_file=$excludelist_path;
  git 'ls-files' -z 2> /dev/null |\
  "$spellchecker/exclude.pl") |\
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
to_retrieve_whitelist() {
  whitelist_file=whitelist.txt
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
      whitelist_file="$(project_file_path whitelist)";;
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
"$(relative_note)"

"'```'"
$err
"'```
</details>'
  fi
}
bullet_words() {
  echo "$1" | perl -pne 's/^(.)/* $1/'
  rm -f "$run_warnings"
  export tokens="$1"
  head=$(cat $GITHUB_EVENT_PATH | jq -r '.pull_request.head.sha' -M)
  if [ "$head" = "null" ]; then
    head=${GITHUB_SHA:-HEAD}
  fi
  base=$(cat $GITHUB_EVENT_PATH | jq -r '.pull_request.base.sha // .before // "HEAD^"' -M)
  if ! git show $base 2>/dev/null >/dev/null; then
    base=$head^
  fi
  if [ -z "$ONLY_REPORT_HEAD" ] && !git show $base 2>/dev/null >/dev/null; then
    ONLY_REPORT_HEAD=1
  fi
  if [ -z "$ONLY_REPORT_HEAD" ]; then
    rm -f "$run_files"
    (
    export with_blame=1
    export HEAD=$head;
    git diff-tree \
      --no-commit-id \
      --name-only \
      --diff-filter=d \
      -r $base..$head \
      -z 2> /dev/null |
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
      echo "::remove-matcher owner=check-spelling::"
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
sorted_whitelist="$temp/whitelist.sorted.txt"
(sed -e 's/#.*//' "$whitelist_path" | sort -u -f | grep . || true) > "$sorted_whitelist"
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
  instructions=$(mktemp)
  to_retrieve_whitelist >> $instructions
  if [ -n "$patch_remove" ]; then
    if [ -z "$whitelist_files" ]; then
      whitelist_files=$whitelist_file
    fi
    perl_header='#!/usr/bin/perl -ni'
    echo 'remove_obsolete_words=$(mktemp)
echo '"'$perl_header"'
my $re=join "|", qw(' >> $instructions
    echo "$patch_remove"  >> $instructions
    echo ');
next if /^($re)(?:$| .*)/;
print;'"'"' > $remove_obsolete_words
chmod +x $remove_obsolete_words
for file in '$whitelist_files'; do $remove_obsolete_words $file; done
rm $remove_obsolete_words' >> $instructions
  fi
  echo '(' >> $instructions
  if [ -n "$patch_add" ]; then
    if [ -e "$new_whitelist_file" ]; then
      echo 'cat "'"$new_whitelist_file"'"' >> $instructions;
    fi
    echo 'echo "
'"$patch_add"'
"' >> $instructions
  fi
  echo ') | sort -u -f | grep . > new_whitelist.txt && mv new_whitelist.txt "'"$new_whitelist_file"'"' >> $instructions
  to_publish_whitelist >> $instructions
  cat $instructions
  rm $instructions
}

if [ -z "$new_output" ]; then
  begin_group 'Fewer misspellings'
  title='There are now fewer misspellings than before'
  instructions=$(
    make_instructions
  )
      spelling_info "$title" "$(bullet_words "$patch_add")" "$instructions"
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
