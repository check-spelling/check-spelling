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

[More information](https://github.com/jsoref/spelling#overview)

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

##### dictionary

This replaces the default dictionary.
One word per line.

##### excludes

This file contains Perl regular expressions.
Generally, one regular expression per line.
They are merged using an `OR` (`|`).

Files matching these patterns will be skipped.

Possible examples include:

```
^\.github/workflows/
```

##### patterns

This file contains Perl regular expressions.
Generally, one regular expression per line.
Lines that begin with `#` will be skipped.
They are merged using an `OR` (`|`).

Tokens within files that match these expressions will be skipped.

Possible examples include:

```
https://(?:(?:www\.|)youtube\.com|youtu.be)/[-a-zA-Z0-9?&=]*
data:[a-zA-Z=;,/0-9+]+
0x[a-f0-9A-F]{2,}[Uu]?[Ll]?
```

##### whitelist

This contains whitelisted "words", one word per line.
Whitelisted words that are not otherwise present in the corpus will be suggested for removal,
but will not trigger a failure.
Words that are present (i.e. not matched by the excludes file) in the repository
and which are not listed in the whitelist will trigger a failure as part of **push** and
**pull_request** actions.

You can use `#` followed by text to add a comment at the end of a line..
Note that some automatic pruning may not properly handle this.

### Optional Configuration Variables

| Variable | Description |
| ------------- | ------------- |
| VERBOSE | `1` if you want to be reminded of how many words are in your whitelist for each run. |

## Behavior

* This action will automatically comment on PRs / commits with its opinion.
* It will try to identify a limited number of lines containing the words it
doesn't recognize.

## Limitations

* GitHub Actions generally don't run on forked repositories unless the forking user enables them.
* Pull Requests from forked repositories run with read-only permissions.
  - To ensure some coverage for such PRs, you can add a **schedule**.

# License

MIT
