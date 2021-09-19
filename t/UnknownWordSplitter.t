#!/usr/bin/perl -wT -Ilib

use 5.022;
use feature 'unicode_strings';
use strict;
use warnings;
use Encode qw/decode_utf8 FB_DEFAULT/;
use Cwd 'abs_path';
use File::Basename;
use File::Temp qw/ tempfile tempdir /;

use Test::More;
plan tests => 14;

use_ok('CheckSpelling::UnknownWordSplitter');

sub read_file {
    my ($file) = @_;
    local $/ = undef;
    my ($content, $output);
    if (open $output, '<:utf8', $file) {
        $content = <$output>;
        close $output;
    }
    return $content;
}

sub check_output_file {
    my ($file, $expected) = @_;
    my $content = read_file($file);
    is($content, $expected);
}

sub sort_lines {
    my ($text) = @_;
    return join "\n", (sort (split /\n/, $text));
}

sub check_output_file_sorted_lines {
    my ($file, $expected) = @_;
    is(sort_lines(read_file($file)), sort_lines($expected));
}

my ($fh, $filename) = tempfile();
print $fh "foo
bar";
close $fh;
is(CheckSpelling::UnknownWordSplitter::file_to_re($filename), "(?:foo)|(?:bar)");
$CheckSpelling::UnknownWordSplitter::word_match = CheckSpelling::UnknownWordSplitter::valid_word();
is($CheckSpelling::UnknownWordSplitter::word_match, '(?^u:\b\w{3,}\b)');
$CheckSpelling::UnknownWordSplitter::shortest=100;
$CheckSpelling::UnknownWordSplitter::longest=0;
CheckSpelling::UnknownWordSplitter::load_dictionary($filename);
is($CheckSpelling::UnknownWordSplitter::shortest, 3);
is($CheckSpelling::UnknownWordSplitter::longest, 5);
is($CheckSpelling::UnknownWordSplitter::word_match, '(?^u:\b\w{3,5}\b)');
my $directory = tempdir();
open $fh, '>:utf8', "$directory/patterns.txt";
print $fh '# ignore-me

random-inconsequential-string
';
close $fh;
CheckSpelling::UnknownWordSplitter::init($directory);
CheckSpelling::UnknownWordSplitter::load_dictionary($filename);
open $fh, '>:utf8', $filename;
print $fh "FooBar baz Bar elf baz bar supercalifragelisticexpialidocious
FooBarBar
";
close $fh;
$CheckSpelling::UnknownWordSplitter::forbidden_re='FooBarBar';
my $output_dir=CheckSpelling::UnknownWordSplitter::split_file($filename);
$CheckSpelling::UnknownWordSplitter::forbidden_re='$^';
check_output_file("$output_dir/name", $filename);
check_output_file("$output_dir/stats", '{words: 4, unrecognized: 3, unknown: 2, unique: 2}');
check_output_file_sorted_lines("$output_dir/warnings", "line 1 cols 8-10: 'baz'
line 1 cols 20-22: 'baz'
line 1 cols 16-18: 'elf'
line 2, columns 1-9, Warning - `FooBarBar` matches a line_forbidden.patterns entry. (forbidden-pattern)
");
check_output_file("$output_dir/unknown", 'baz
elf');

$CheckSpelling::UnknownWordSplitter::patterns_re = 'i.';
$output_dir=CheckSpelling::UnknownWordSplitter::split_file($filename);
check_output_file("$output_dir/name", $filename);
check_output_file("$output_dir/stats", '{words: 7, unrecognized: 6, unknown: 5, unique: 2}');
check_output_file_sorted_lines("$output_dir/warnings", "line 1 cols 8-10: 'baz'
line 1 cols 20-22: 'baz'
line 1 cols 16-18: 'elf'");
check_output_file("$output_dir/unknown", 'baz
elf
exp
ragel
supercal');
$CheckSpelling::UnknownWordSplitter::patterns_re = '$^';
