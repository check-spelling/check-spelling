#!/usr/bin/env -S perl -w -Ilib

use strict;
use warnings;
use utf8;

use File::Basename;
use File::Temp qw/ tempfile /;
use Test::More;
use JSON::PP;
use Capture::Tiny ':all';

plan tests => 9;
use_ok('CheckSpelling::Sarif');
is(CheckSpelling::Sarif::encode_low_ascii("\x05"), '\u0005');

is(CheckSpelling::Sarif::encode_message('this `is` something \\slash'), 'this [is](#security-tab) something \\\\\\\\\\\\slash');
is(CheckSpelling::Sarif::encode_message('this `is` some ``thing``'), q<this 'is' some [thing](#security-tab)>);
is(CheckSpelling::Sarif::encode_message('`this` is `a *pattern* with _lots_ of` stuff'), q<[this](#security-tab) is 'a \\\\*pattern\\\\* with \\\\_lots\\\\_ of' stuff>);

my $tests = dirname(__FILE__);
my $base = dirname($tests);

$ENV{'CHECK_SPELLING_VERSION'} = '0.0.0';
my ($sarif_merged);
my ($fh, $warnings) = tempfile();
binmode($fh, ":encoding(UTF-8)");
my $imaginary_rule = `$tests/sarif/code.sh`;
chomp $imaginary_rule;
print $fh 't/sarif/sample.txt:1:24 ... 28, Error - `meep` is not a recognized word (unrecognized-spelling)
t/sarif/sample.txt:1:30 ... 34, Error - `meep` is not a recognized word (unrecognized-spelling)
t/sarif/sample.txt:2:1 ... 5, Error - `meep` is not a recognized word (unrecognized-spelling)
t/sarif/sample.txt:5:1 ... 7, Error - `mibbit` is not a recognized word (unrecognized-spelling)
t/sarif/sample.txt:7:1 ... 7, Error - `mibbit` is not a recognized word (unrecognized-spelling)
t/sarif/sample.txt:8:6 ... 11, Error - ``je`ep`` is not a recognized word (unrecognized-spelling)
t/sarif/sample.txt:9:2 ... 4, Error - imaginary rule ('.$imaginary_rule.')
t/sarif/other.txt:10:5 ... 10, Error - ` a` matches pattern `\sa(?= (something))` (unrecognized-spelling)
t/sarif/forbidden.txt:11:17 ... 18, Error - `a` matches a line_forbidden.patterns rule: Should be `an` - `(?<=\s)a(?= (?:a(?!nd\s|s\s)|e(?!u)|i(?![ns]\s)|o(?!nc?e)|u(?!biquitous|int|kr|n[ai]|r[ael]|s[aeiu`… (forbidden-pattern)
https://example.com/lib/CheckSpelling/Sarif.pm:3:24 ... 28, Error - `Star` is not a recognized word (unrecognized-spelling)

';
close $fh;
my $rev = `git rev-parse HEAD`;
chomp $rev;
my $rev_masked = '70'x20;
my $branch = `git branch --show-current`;
my $fallback_rev = `git rev-parse HEAD`;
chomp $branch;
chomp $fallback_rev;
`
git branch -m expected-branch-name 2>/dev/null || git checkout -B expected-branch-name 2>/dev/null

if ! git remote get-url real-origin >/dev/null 2>/dev/null; then
  git remote rename origin real-origin
  git remote add origin http://localhost
fi
`;

$ENV{'warning_output'} = $warnings;
$ENV{'INPUT_REPORT_TITLE_SUFFIX'} = 'test';
($fh, $sarif_merged) = tempfile();

my ($stdout, $stderr, $sarif_generated) = capture {
CheckSpelling::Sarif::main("$base/sarif.json", "$tests/sarif.json", 'check-spelling/test');
};

is($stdout, '', 'CheckSpelling::Sarif::main out');
is($stderr, '::notice title=missing-rule-definition::t/sarif/code.sh:2:7 ... 21, Notice - No rule definition for `imaginary-rule` (missing-rule-definition)
', 'CheckSpelling::Sarif::main err');

`
git remote remove origin
git remote rename real-origin origin

git branch -m '$branch' 2>/dev/null || git checkout '$fallback_rev' 2>/dev/null
`;
$sarif_generated =~ s/\Q$rev\E/$rev_masked/g;
print $fh $sarif_generated;
close $fh;
my $formatted_sarif;
($fh, $formatted_sarif) = tempfile();
close $fh;
`jq -M . '$sarif_merged'|perl -pe 's/^\\s*//' > '$formatted_sarif'`;

$ENV{'HOME'} =~ /^(.*)$/;
my $home = $1;
$ENV{'PATH'} = "/bin:/usr/bin:/opt/homebrew/bin";
my $expected_json;
my $formatted_sarif_json;
{
  local $/;
  if (open(my $expected_json_file, '<', "$tests/sarif/expected.json")) {
    $expected_json = decode_json(<$expected_json_file>);
    close $expected_json_file;
    open my $formatted_sarif_file, '<', $formatted_sarif;
    $formatted_sarif_json = decode_json(<$formatted_sarif_file>);
    close $formatted_sarif_file;

    is_deeply($formatted_sarif_json, $expected_json);
  } else {
    fail("expected to open $tests/sarif/expected.json");
  }
}

my $rules = `
jq -r '.runs[].tool.driver.rules[].id' sarif.json|xargs|tr ' ' '|'
`;
chomp $rules;

my $exclude_tests = '.t$';
my $git_files = `git ls-files|grep -v '$exclude_tests'|xargs`;
chomp $git_files;

my $rules_with_leading_period = `egrep '\\. \(($rules)\)' $git_files`;

is($rules_with_leading_period, '');
