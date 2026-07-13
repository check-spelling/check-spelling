#!/usr/bin/env -S perl -w -Ilib

use strict;
use warnings;
use utf8;

use Cwd qw/ abs_path realpath /;
use File::Copy;
use File::Temp qw/ tempfile tempdir /;
use File::Basename;
use Test::More;
use Capture::Tiny ':all';
plan tests => 6;
use_ok('CheckSpelling::CheckDictionary');

$ENV{comment_char} = '#';
delete $ENV{INPUT_IGNORE_PATTERN};

my ($line, $warning);
$. = 10;

($line, $warning) = CheckSpelling::CheckDictionary::process_line('hello?#123');
is($line, 'hello?', 'valid entry (result)');

my $hello = "hello#123";
$ENV{INPUT_IGNORE_PATTERN} = "[^A-Za-z']";
($line, $warning) = CheckSpelling::CheckDictionary::process_line($hello);
is($warning, '', 'valid entry (warning)');
is($line, 'hello', 'valid entry (result)');

$ENV{comment_char} = '$';
($line, $warning) = CheckSpelling::CheckDictionary::process_line($hello);
is($warning, "6 ... 10, Warning - Ignoring entry because it contains non-alpha characters - `#123` (non-alpha-in-dictionary)
", 'invalid entry (warning)');
is($line, '', 'invalid entry (result)');

my $temp_dir = tempdir();
my ($fh, $filepath) = tempfile();
close $fh;
my $multiline_text = "world!567
hello\rcruel\r\nworld\n
";

my $filename = basename $filepath;
my $test_path = "$temp_dir/$filename";
rename($filepath, $test_path);
$filepath = $test_path;

open $fh, '>', $filepath;
print $fh $multiline_text;
close $fh;
my $spellchecker = abs_path(dirname(dirname(__FILE__)));
$ENV{spellchecker} = $spellchecker;
$ENV{PATH} =~ /^(.*)$/;
$ENV{PATH} = $1;
