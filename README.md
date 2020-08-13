# Spelling tools

## Overview

Everyone makes typos. This includes people writing documentation and comments,
but it also includes programmers naming variables, functions, apis, classes,
and filenames.

Often, programmers will use `InitialCapitalization`, `camelCase`,
`ALL_CAPS`, or `IDLCase` when naming their things. When they do this, it makes
it much harder for naive spelling tools to recognize misspellings, and as such,
with a really high false-positive rate, people don't tend to enable spellchecking
at all.

This repository's tools are capable of tolerating all of those variations.
Specifically, [w](https://github.com/jsoref/spelling/blob/master/w) understands
enough about how programmers name things that it can split the above conventions
into word-like things for checking against a dictionary.

## Spell Checker GitHub Actions

[![Spell checking](https://github.com/check-spelling/check-spelling/workflows/Spell%20checking/badge.svg?branch=master)](https://github.com/check-spelling/check-spelling/actions?query=workflow:"Spell+checking"+branch:master)

* [Possible features](https://github.com/check-spelling/check-spelling/wiki/Possible-features)
are listed on the [wiki](https://github.com/check-spelling/check-spelling/wiki/)
* [Historical information](https://github.com/jsoref/spelling#overview)

### Sample output

#### Comment as seen in a PR

![github action comment](images/check-spelling-comment.png)

#### Comment as seen in a commit

![github action annotation](images/check-spelling-annotation.png)

#### The GitHub Action Run log

![github action log](images/check-spelling-log.png)

### Basic Configuration

#### Variables

| Variable | Description |
| ------------- | ------------- |
| [bucket](#bucket) | file/url for which the tool has read access to a couple of files. |
| [project](#project) | a folder within `bucket`. This allows you to share common items across projects. |
| [timeframe](#timeframe) | number of minutes (default 60) to consider when a **schedule** workflow checks for updated PRs. |
| GITHUB_TOKEN | Secret used to retrieve your code and comment on PRs/commits. |

##### bucket

* unset - especially initially...
* `./path` - a local directory
* `ssh://git@*`, `git@*` - git urls (if the url isn't for github, you'll need to have set up credentials)
* `https://` (or `http://`) - curl compatible
* `gs://` - gsutil url

##### project

* unset - especially initially
* branch - for git urls
* `./` - if you don't need an extra nesting layer
* directory - especially for sharing a general bucket across multiple projects

##### timeframe

Used by the **schedule** action. Any open pull requests from another repository
will be checked, and if the commit is within that timeframe, it will be processed.

#### Files

Note that each of the below items can either be a file w/ a `.txt` suffix,
or a directory, where each file with a `.txt` suffix will be merged together.

| Variable | Description |
| ------------- | ------------- |
| [advice](#advice) | This allows you to supplement the comment. |
| [allow](#allow) | This allows you to supplement the dictionary. |
| [dictionary](#dictionary) | This allows you to replace the dictionary. |
| [excludes](#excludes) | This allows you to skip checking files/directories. |
| [expect](#expect) | This defines the list of words in the repository that aren't in the dictionary. |
| [only](#only) | This allows you to limit checking to certain files/directories. |
| [patterns](#patterns) | This allows you to define patterns of acceptable strings. |
| [reject](#reject) | This allows you to remove items from the default dictionary. |

##### advice

This adds a supplemental portion to the comment
posted to github. It's freeform. You can use
it to explain how contributors should decide
where to put new entries.

##### allow

This allows you to add supplemental words to
the dictionary without relacing the core dictionary.

##### dictionary

This replaces the [default dictionary](https://github.com/check-spelling/check-spelling/raw/dictionary/dict.txt).
One word per line.

If you want to include the default dictionary,
place it into the directory next to your own.

##### excludes

This file contains Perl regular expressions.
Generally, one regular expression per line.
They are merged using an `OR` (`|`).

Files matching these patterns will be skipped.

Possible examples include:

```
(?:^|/)vendor/
(?:^|/)yarn\.lock$
LICENSE
\.pdf$
\.png$
\.xslx?$
^CONTRIBUTING\.md$
^\.github/action/spell-check/
^\.github/workflows/
```

Lines that start with `#` will be ignored.

##### expect

This contains of expected "words" that aren't in the dictionary, one word per line.
Expected words that are not otherwise present in the corpus will be suggested for removal,
but will not trigger a failure.

Words that are present (i.e. not matched by the excludes file) in the repository
and which are not listed in the expect list will trigger a failure as part of **push** and
**pull_request** actions (depending on how you've configured this action).

You can use `#` followed by text to add a comment at the end of a line.
Note that some automatic pruning may not properly handle this.

:arrow_right: Until you add an `expect` file, the output will only be provided in the **GitHub
Action Run Log**.

* This is because it's assumed that you will want to perform
some tuning (probably adding `excludes` and possibly adding `patterns`) before
the action starts commenting on commits.
* You can simply copy the list from that output.

:warning: This was previously called `whitelist` -- that name is *deprecated*.
Support for the deprecated name may be removed in a future release.
Until then, warnings will be reported in the action run log.
At a future date, comments may report this as well.

##### only

This file contains Perl regular expressions.
Generally, one regular expression per line.
They are merged using an `OR` (`|`).

Files not matching these patterns will be skipped.

Possible examples include:

```
\.pl$
\.js$
\.py$
```

Lines that start with `#` will be ignored.

##### patterns

This file contains Perl regular expressions.
Generally, one regular expression per line.
Lines that begin with `#` will be skipped.
They are merged using an `OR` (`|`).

Tokens within files that match these expressions will be skipped.

Possible examples include:

```
# this is a comment
https?://(?:(?:www\.|)youtube\.com|youtu.be)/[-a-zA-Z0-9?&=]*
data:[a-zA-Z=;,/0-9+]+
# c99 hex digits (not the full format, just one I've seen)
0x[0-9a-fA-F](?:\.[0-9a-fA-F]*|)[pP]
# hex digits including css/html color classes:
(?:0[Xx]|U\+|#)[a-f0-9A-FGgRr]{2,}[Uu]?[Ll]{0,2}\b
# uuid:
\{[0-9A-FA-F]{8}-(?:[0-9A-FA-F]{4}-){3}[0-9A-FA-F]{12}\}
# the negative lookahead here is to allow catching 'templatesz' as a misspelling
# but to otherwise recognize a Windows path with \templates\foo.template or similar:
\\templates(?![a-z])
# ignore long runs of a single character:
\b([A-Za-z])\1{3,}\b
# Note that the next example is no longer necessary if you are using
# to match a string starting with a `#`, use a character-class:
[#]backwards
```

##### reject

This allows you to remove words from the dictionary
without having to replace the core dictionary.

The order of operations is:

> `(dictionary + allows) - reject`

### Optional Configuration Variables

| Variable | Description |
| ------------- | ------------- |
| VERBOSE | `1` if you want to be reminded of how many words are in your expect list for each run. |

## Behavior

* This action will automatically comment on PRs / commits with its opinion.
* It will try to identify a limited number of lines containing the words it
doesn't recognize.

## Limitations

* GitHub Actions generally don't run on forked repositories unless the forking user enables them.
* Pull Requests from forked repositories run with read-only permissions.
  - To ensure some coverage for such PRs, you can add a **schedule**.

# License

[MIT](LICENSE.txt)
