#!/usr/bin/env -S perl -w -Ilib

use strict;
use warnings;
use utf8;

use Cwd qw/ abs_path getcwd realpath /;
use File::Copy;
use File::Temp qw/ tempfile tempdir /;
use File::Basename;
use Test::More;
use Capture::Tiny ':all';

plan tests => 27;

use_ok('CheckSpelling::CleanupFiles');

my $tests = dirname(abs_path(__FILE__)).'/cleanup-files';

my $sandbox = tempdir();
$ENV{GITHUB_WORKSPACE} = $sandbox;
chdir $sandbox;
my ($fh, $temp) = tempfile();
close $temp;
$ENV{maybe_bad} = $temp;
$ENV{early_warnings} = '/dev/stderr';
$ENV{output} = '/dev/stdout';
$ENV{type} = 'unknown';
my ($stdout, $stderr, @results);
($stdout, $stderr, @results) = capture {
  return CheckSpelling::CleanupFiles::clean_files($temp);
};

my $sandbox_name = basename $sandbox;
my $temp_name = basename $temp;
like($stdout, qr!::error ::Configuration files must live within .*?$sandbox_name\.\.\.!, 'cleanup-files (stdout) sandbox');
like($stdout, qr!::error ::Unfortunately, file '[\w/]+?/$temp_name' appears to reside elsewhere\.!, 'cleanup-files (stdout) temp');
is($stderr, '', 'cleanup-files (stderr)');
my $result = $results[0];
is($result, 3, 'cleanup-files (exit code)');

my $git_dir = "$sandbox/.git";
mkdir $git_dir;
my $git_child = "$sandbox/.git/bad";

($stdout, $stderr, @results) = capture {
  return CheckSpelling::CleanupFiles::clean_files($git_child);
};
like($stdout, qr!::error ::Configuration files must not live within \`\.git/\`\.\.\.!, 'cleanup-files (stdout) sandbox');
like($stdout, qr!::error ::Unfortunately, file '[\w/]+?/\.git/bad' appears to\.!, 'cleanup-files (stdout) temp');
is($stderr, '', 'cleanup-files (stderr)');
$result = $results[0];
is($result, 4, 'cleanup-files (exit code)');

$ENV{GITHUB_WORKSPACE} = $tests;
($stdout, $stderr, @results) = capture {
  return CheckSpelling::CleanupFiles::clean_files("$tests/no-such-file.txt", "$tests/empty.txt", "$tests/missing-eol-at-eof.txt");
};
$result = $results[0];
is($stdout, 'this
file
is
\missing
eol at eof

', 'cleanup-files (stdout)');
is($stderr, "$tests/empty.txt:1:1 ... 1, Notice - File is empty (empty-file)
$tests/missing-eol-at-eof.txt:4:1 ... 32, Warning - Missing newline at end of file (no-newline-at-eof)
", 'cleanup-files (stderr)');
is($result, 0, 'cleanup-files (exit code)');

($stdout, $stderr, @results) = capture {
  return CheckSpelling::CleanupFiles::clean_files("$tests/dos.txt");
};
$result = $results[0];
is($stdout, 'hello
world
', 'cleanup-files (stdout)');
is($stderr, '', 'cleanup-files (stderr)');
is($result, 0, 'cleanup-files (exit code)');

($stdout, $stderr, @results) = capture {
  return CheckSpelling::CleanupFiles::clean_files("$tests/mac.txt");
};
$result = $results[0];
is($stdout, 'what
ever
', 'cleanup-files (stdout)');
is($stderr, '', 'cleanup-files (stderr)');
is($result, 0, 'cleanup-files (exit code)');

($stdout, $stderr, @results) = capture {
  return CheckSpelling::CleanupFiles::clean_files("$tests/mixed-dos-mac.txt");
};
$result = $results[0];
is($stdout, 'hello
world
what
ever
', 'cleanup-files (stdout)');
is($stderr, "$tests/mixed-dos-mac.txt:4:1 ... 24, Warning - Mixed DOS [2] and Mac classic [2] line endings (mixed-line-endings)
$tests/mixed-dos-mac.txt:3:0 ... 5, Warning - Entry has inconsistent line endings (unexpected-line-ending)
$tests/mixed-dos-mac.txt:4:0 ... 5, Warning - Entry has inconsistent line endings (unexpected-line-ending)
", 'cleanup-files (stderr)');
is($result, 0, 'cleanup-files (exit code)');

$ENV{type} = 'patterns';
($stdout, $stderr, @results) = capture {
  return CheckSpelling::CleanupFiles::clean_files("$tests/empty.txt", "$tests/one.txt", "$tests/two.txt");
};
$result = $results[0];
is($stdout, '# comment
this-that

# broken
$^

# repeated
not-allowed
# maybe repeated
$^

# meta
\Qthis.*that\E

# bad meta
$^
', 'cleanup-files (stdout)');

my $q_bad_reg_ex = 'Warning - Unrecognized escape \Q passed through: `\Q` (bad-regex)';
is($stderr, "$tests/empty.txt:1:1 ... 1, Notice - File is empty (empty-file)
$tests/one.txt:5:2 ... 3, Warning - Unmatched `[`: `a[` (bad-regex)
$tests/two.txt:2:1 ... 11, Warning - Pattern is the same as pattern on `$tests/one.txt:8` (duplicate-pattern)
$tests/two.txt:8:2 ... 3, $q_bad_reg_ex
", 'cleanup-files (stderr)');
is($result, 0, 'cleanup-files (exit code)');

$ENV{type} = 'dictionary';
$ENV{INPUT_IGNORE_PATTERN} = "[^A-Za-z']";
($stdout, $stderr, @results) = capture {
  return CheckSpelling::CleanupFiles::clean_files("$tests/empty.txt", "$tests/non-alpha.txt");
};
$result = $results[0];
is($stdout, 'worldly

this
', 'cleanup-files (stdout)');
is($stderr, "$tests/empty.txt:1:1 ... 1, Notice - File is empty (empty-file)
$tests/non-alpha.txt:2:6 ... 7, Warning - Ignoring entry because it contains non-alpha characters - `:` (non-alpha-in-dictionary)
", 'cleanup-files (stderr)');
is($result, 0, 'cleanup-files (exit code)');
