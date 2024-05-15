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

### How check-spelling approaches content

Input | Seen | Reported | Explanation
-|-|-|-
`InitialCapitalization`|`Initial` `Capitalization`| `` | Both words are in the dictionary
`camelCase`|`camel` `Case`| `` | Both words are in the dictionary
`ALL_CAPS`|`ALL` `CAPS`| `` | Both words are in the dictionary
`IDLCase`| `IDL` `Case`| `IDL` | The first word isn't in the dictionary, but the second is

### How check-spelling manages `expect.txt`

Generally, check-spelling wants to minimize the `expect.txt` (or similar file(s)) so that it's easier for someone to open the file up and complain that something in it shouldn't be there.

The enemy of that goal is repetition or near repetition. The longer the file, the more likely a reader's eyes will glaze over before they spot something that shouldn't be there.

#### uppercase

`about.txt`

```
IKEA was started July 28, 1943.
```

Corresponding `expect.txt`:

```
IKEA
```

Explanation: `IKEA` isn't in the dictionary.

This doesn't mean that it would be ok to write `Ikea` or `ikea`.
`Ikea` is definitely wrong (and outside of domain names, `ikea` is probably also wrong).

#### proper noun

`file.txt`

```
Microsoft shipped Windows in 1985.
```

Corresponding `expect.txt`:

```
Microsoft
```

Explanation: `Microsoft` isn't in the dictionary.

### proper noun and uppercase

`file.js`

```
// Microsoft shipped Windows in 1985.

MICROSOFT_WINDOWS_RELEASE_DATE="November 20, 1985"
```

Corresponding `expect.txt`:

```
Microsoft
```

Explanation: `Microsoft` isn't in the dictionary, but there's a reasonable expectation that in some programming language a proper noun will need to be written in uppercase in order to be used as constant (or similar).

This doesn't mean that a project has decided to allow `microsoft`,
in a documentation oriented project `microsoft` would be wrong.

### lowercase, proper noun, and uppercase

`file.js`

```
// http://microsoft.com/ie

MICROSOFT_IE_RELEASE_DATE="August 16, 1995"
```

Corresponding `expect.txt`:

```
microsoft
```

Explanation: `microsoft` isn't in the dictionary, and there's a reasonable expectation that in some cases it will have to be written as `Microsoft` (because in English the first word of a sentence will have its first letter capitalized) or as `MICROSOFT` (because programmers tend to write things in uppercase for constants).

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

Read about [running check-spelling locally](https://docs.check-spelling.dev/Feature:-Run-locally.html).

## Prerelease

I do test development on a [prerelease](https://github.com/check-spelling/check-spelling/tree/prerelease) branch.

Features and the behavior of this branch are not guaranteed to be stable
as they're under semi-active development.

## License

[MIT](LICENSE.txt)
