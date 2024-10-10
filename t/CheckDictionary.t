#!/usr/bin/env -S perl -Ilib

use strict;
use warnings;

use Cwd qw/ abs_path realpath /;
use File::Copy;
use File::Temp qw/ tempfile tempdir /;
use File::Basename;
use Test::More;
use Capture::Tiny ':all';
plan tests => 12;
use_ok('CheckSpelling::CheckDictionary');

$ENV{comment_char} = '#';
$ENV{INPUT_IGNORE_PATTERN} = "[^A-Za-z']";

my $temp_dir = tempdir();
my ($fh, $filepath) = tempfile();
my $multiline_text = "world!567
hello\rcruel\r\nworld\n
";
print $fh $multiline_text;
close $fh;
my $filename = basename $filepath;
my $test_path = "$temp_dir/$filename";
rename($filepath, $test_path);
$filepath = $test_path;

my ($line, $warning);
$. = 10;
($line, $warning) = CheckSpelling::CheckDictionary::process_line($filepath, "hello#123");
is($warning, '', 'valid entry (warning)');
is($line, 'hello', 'valid entry (result)');

$ENV{comment_char} = '$';
($line, $warning) = CheckSpelling::CheckDictionary::process_line($filepath, "hello#123");
is($warning, "$filepath:10:6 ... 10, Warning - Ignoring entry because it contains non-alpha characters. (non-alpha-in-dictionary)
", 'invalid entry (warning)');
is($line, '', 'invalid entry (result)');

open $fh, '>', $filepath;
print $fh $multiline_text;
close $fh;
my $spellchecker = abs_path(dirname(dirname(__FILE__)));
$ENV{spellchecker} = $spellchecker;
$ENV{PATH} =~ /^(.*)$/;
$ENV{PATH} = $1;

my ($stdout, $stderr, @results);
($stdout, $stderr, @results) = capture {
  chdir($temp_dir);
  system("$spellchecker/wrappers/check-dictionary", $filepath)
};
is($stdout, '', 'wrappers/check-dictionary (stdout)');
is($stderr, "$filename:1:6 ... 10, Warning - Ignoring entry because it contains non-alpha characters. (non-alpha-in-dictionary)
$filename:2:0 ... 6, Warning - Entry has inconsistent line ending. (unexpected-line-ending)
$filename:3:0 ... 7, Warning - Entry has inconsistent line ending. (unexpected-line-ending)
", 'wrappers/check-dictionary (stderr)');
my $result = $results[0] >> 8;
is($result, '0', 'wrappers/check-dictionary (exit code)');

open $fh, '<', $filepath;
$/ = undef;
$result = <$fh>;
close $fh;

is($result, 'hello
cruel
world
', 'wrappers/check-dictionary (validation)');

SKIP: {
  my $link;
  ($fh, $link) = tempfile();
  close $fh;
  unlink($link);
  my $symlink_exists = eval { symlink($filepath, $link); };
  skip 'could not create symlink', 3 unless $symlink_exists;

  open $fh, '>', $filepath;
  print $fh $multiline_text;
  close $fh;

  ($stdout, $stderr, @results) = capture {
    chdir($temp_dir);
    system("$spellchecker/wrappers/check-dictionary", $link);
  };

  is($stdout, '', 'wrappers/check-dictionary (stdout)');
  is($stderr, "$filename:1:6 ... 10, Warning - Ignoring entry because it contains non-alpha characters. (non-alpha-in-dictionary)
$filename:2:0 ... 6, Warning - Entry has inconsistent line ending. (unexpected-line-ending)
$filename:3:0 ... 7, Warning - Entry has inconsistent line ending. (unexpected-line-ending)
", 'wrappers/check-dictionary (stderr)');
  $result = $results[0] >> 8;
  is($result, '0', 'wrappers/check-dictionary (exit code)');
}
