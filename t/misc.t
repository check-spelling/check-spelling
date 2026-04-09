#!/usr/bin/env -S perl -w -Ilib

use strict;
use warnings;
use utf8;
use File::Basename;
use Cwd qw/ abs_path /;

use Test::More;
use Capture::Tiny ':all';
use File::Temp qw/ tempfile tempdir /;

plan tests => 17;

my $spellchecker = abs_path(dirname(dirname(__FILE__)));
$ENV{spellchecker} = $spellchecker;

my ($stdout, $stderr, @results) = capture {
  system("
  echo 'hello (Hello, hello)
world' |
  $ENV{spellchecker}/strip-word-collator-suffix.pl");
};

is($stdout, "hello\nworld\n", 'strip-word-collator-suffix out');
is($stderr, '', 'strip-word-collator-suffix err');
is((join ':', @results), '0', 'strip-word-collator-suffix result');

my ($fd, $name) = tempfile;
print $fd "hello (Hello, hello)\nmeow\n";
close ($fd);
my $collated = $name;
($fd, $name) = tempfile;
print $fd "
`hello` not a recognized word (unrecognized-spelling)
`Hello` not a recognized word (unrecognized-spelling)
something else (something-else)
";

close ($fd);

($stdout, $stderr, @results) = capture {
  system("$spellchecker/expect-collator.pl $collated $name");
};

is($stdout, q<`Hello` ignored because another more general variant (`hello`) is also in expect (ignored-expect-variant)
something else (something-else)
>, 'expect-collator out');
is($stderr, '', 'expect-collator err');
is((join ':', @results), '0', 'expect-collator result');

$ENV{GITHUB_WORKSPACE}='/lib';
($stdout, $stderr, @results) = capture {
  system("early_warnings=/dev/stderr output=/dev/stdout $ENV{spellchecker}/wrappers/cleanup-files /etc/passwd");
};

like($stdout, qr<::error ::Configuration files must live within .*\.\.\.>, 'cleanup-files - out must live within');
like($stdout, qr<::error ::Unfortunately, file .* appears to reside elsewhere.>, 'cleanup-files - out resides elsewhere');
is($stderr, '', 'cleanup-files - elsewhere err');
is($results[0] >> 8, 3, 'cleanup-files - elsewhere result');

my $dir=tempdir;
$ENV{GITHUB_WORKSPACE}=$dir;
($stdout, $stderr, @results) = capture {
  system("
    git init -q '$dir';
    early_warnings=/dev/stderr output=/dev/stdout $ENV{spellchecker}/wrappers/cleanup-files '$dir/.git/config'
  ");
};

like($stdout, qr<::error ::Configuration files must not live within `\.git/`\.\.\.>, 'cleanup-files - out must not live within');
like($stdout, qr<::error ::Unfortunately, file '.*/\.git/config' appears to\.>, 'cleanup-files - out appears to');
is($stderr, '', 'cleanup-files - .git err');
is($results[0] >> 8, 4, 'cleanup-files - .git result');

($stdout, $stderr, @results) = capture {
  system('
patterns_file=$(mktemp)
cp "$spellchecker/t/unknown-words.pr/config/patterns.txt" "$patterns_file"
early_warnings=/dev/stderr file=something "$spellchecker/wrappers/check-pattern-file" "$patterns_file"');
};
is($stdout, '', 'check-pattern-file out');
is($stderr, "something:1:1 ... 2, Warning - Quantifier follows nothing: `+` (bad-regex)
", 'check-pattern-file err');
is($results[0], 0, 'check-pattern-file result');
