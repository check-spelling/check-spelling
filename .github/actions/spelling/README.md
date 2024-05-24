# check-spelling/check-spelling configuration

File | Purpose | Format | Info
-|-|-|-
[allow.txt](allow.txt) | Add words to the dictionary | one word per line (only letters and `'`s allowed) | [allow](https://docs.check-spelling.dev/Configuration#allow)
[reject.txt](reject.txt) | Remove words from the dictionary (after allow) | grep pattern matching whole dictionary words | [reject](https://docs.check-spelling.dev/Configuration-Examples%3A-reject)
[excludes.txt](excludes.txt) | Files to ignore entirely | perl regular expression | [excludes](https://docs.check-spelling.dev/Configuration-Examples%3A-excludes)
[only.txt](only.txt) | Only check matching files (applied after excludes) | perl regular expression | [only](https://docs.check-spelling.dev/Configuration-Examples%3A-only)
[patterns.txt](patterns.txt) | Patterns to ignore from checked lines | perl regular expression (order matters, first match wins) | [patterns](https://docs.check-spelling.dev/Configuration-Examples%3A-patterns)
[line_forbidden.patterns](line_forbidden.patterns) | Patterns to flag in checked lines | perl regular expression (order matters, first match wins) | [patterns](https://docs.check-spelling.dev/Configuration-Examples%3A-patterns)
[expect.txt](expect.txt) | Expected words that aren't in the dictionary | one word per line (sorted, alphabetically) | [expect](https://docs.check-spelling.dev/Configuration#expect)
[advice.md](advice.md) | Supplement for GitHub comment when unrecognized words are found | GitHub Markdown | [advice](https://docs.check-spelling.dev/Configuration-Examples%3A-advice)

Note: you can replace any of these files with a directory by the same name (minus the suffix)
and then include multiple files inside that directory (with that suffix) to merge multiple files together.
