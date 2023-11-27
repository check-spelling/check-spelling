# @check-spelling/check-spelling GitHub Action

## Overview

Everyone makes typos. This includes people writing documentation and comments,
but it also includes programmers naming variables, functions, APIs, classes,
and filenames.

Often, programmers will use `InitialCapitalization`, `camelCase`,
`ALL_CAPS`, or `IDLCase` when naming their things. When they do this, it makes
it much harder for naive spelling tools to recognize misspellings, and as such,
with a really high false-positive rate, people don't tend to enable spell checking
at all.

This repository's tools are capable of tolerating all of those variations.
Specifically, [w](https://github.com/jsoref/spelling/blob/master/w) understands
enough about how programmers name things that it can split the above conventions
into word-like things for checking against a dictionary.

## GitHub Action

[![Check Spelling](https://github.com/check-spelling/check-spelling/actions/workflows/spelling.yml/badge.svg)](https://github.com/check-spelling/check-spelling/actions/workflows/spelling.yml)

- [@check-spelling/check-spelling GitHub Action](#check-spellingcheck-spelling-github-action)
  - [Overview](#overview)
  - [GitHub Action](#github-action)
  - [Quick Setup](#quick-setup)
  - [Configuration](#configuration)
  - [Events](#events)
  - [Multilingual](#multilingual)
  - [Wiki](#wiki)
  - [Sample output](#sample-output)
    - [Comment as seen in a PR](#comment-as-seen-in-a-pr)
    - [Comment as seen in a commit](#comment-as-seen-in-a-commit)
    - [GitHub Action Run log](#github-action-run-log)
  - [Running locally](#running-locally)
    - [Running locally with Act](#running-locally-with-act)
  - [Prerelease](#prerelease)
  - [License](#license)

## Quick Setup

Just copy the [spell-check-this](https://github.com/check-spelling/spell-check-this)
[`.github/workflows/spelling.yml`](https://github.com/check-spelling/spell-check-this/tree/main/.github/workflows/spelling.yml) into your `.github/workflows` in your project.

## Configuration

See the [documentation](https://docs.check-spelling.dev) for [Configuration information](https://docs.check-spelling.dev/Configuration).

## Events

When check-spelling runs and encounters something that isn't ideal,
it may output a message including an event code,
at the end of the message `(unrecognized-spelling)`.

You should be able to look up the code in
https://docs.check-spelling.dev/Event-descriptions.
For `unrecognized-spelling`,
that's:
https://docs.check-spelling.dev/Event-descriptions#unrecognized-spelling.

## Multilingual

As of [v0.0.22](https://github.com/check-spelling/check-spelling/releases/tag/v0.0.22), you can [use non English dictionaries](https://docs.check-spelling.dev/Feature%3A-Configurable-word-characters) with the help of [Hunspell](https://github.com/hunspell/hunspell).

## Wiki

There is a [wiki](https://github.com/check-spelling/check-spelling/wiki) containing evolving information. It's open to public editing (and is occasionally defaced/spammed).

## Sample output

### Comment as seen in a PR

![github action comment](https://raw.githubusercontent.com/check-spelling/art/86a33c871e0e01aaf210087d13614c166d0ba536/output/check-spelling-comment.png)

### Comment as seen in a commit

![github action annotation](https://raw.githubusercontent.com/check-spelling/art/86a33c871e0e01aaf210087d13614c166d0ba536/output/check-spelling-annotation.png)

### GitHub Action Run log

![github action log](https://raw.githubusercontent.com/check-spelling/art/86a33c871e0e01aaf210087d13614c166d0ba536/output/check-spelling-log.png)

## Running locally

Yes you can!

### Running locally with Act

1. [Install Act](https://github.com/nektos/act#installation)
1. `act`

:warning: This may break at times as **act** may be missing support for newer GitHub Actions features.

## Prerelease

I do test development on a [prerelease](https://github.com/check-spelling/check-spelling/tree/prerelease) branch.

Features and the behavior of this branch are not guaranteed to be stable
as they're under semi-active development.

## License

[MIT](LICENSE.txt)
