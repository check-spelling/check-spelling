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
plan tests => 27;

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
Mooprh
BROADDEPlay

bar";
close $fh;
is(CheckSpelling::UnknownWordSplitter::file_to_re($filename), "(?:foo)|(?:Mooprh)|(?:BROADDEPlay)|(?:bar)");
$CheckSpelling::UnknownWordSplitter::word_match = CheckSpelling::UnknownWordSplitter::valid_word();
is($CheckSpelling::UnknownWordSplitter::word_match, '(?^u:\b\w{3,}\b)');
$CheckSpelling::UnknownWordSplitter::shortest=100;
$CheckSpelling::UnknownWordSplitter::longest=0;
CheckSpelling::UnknownWordSplitter::load_dictionary($filename);
is(scalar %CheckSpelling::UnknownWordSplitter::dictionary, 4);
is($CheckSpelling::UnknownWordSplitter::shortest, 3);
is($CheckSpelling::UnknownWordSplitter::longest, 13);
is($CheckSpelling::UnknownWordSplitter::word_match, '(?^u:\b\w{3,13}\b)');
$ENV{'INPUT_LONGEST_WORD'} = 5;
$ENV{'INPUT_SHORTEST_WORD'} = '';
CheckSpelling::UnknownWordSplitter::load_dictionary($filename);
is(scalar %CheckSpelling::UnknownWordSplitter::dictionary, 4);
is($CheckSpelling::UnknownWordSplitter::word_match, '(?^u:\b\w{3,5}\b)');
my $directory = tempdir();
open $fh, '>:utf8', "$directory/words";
print $fh 'bar
foo
';
close $fh;
open $fh, '>:utf8', "$directory/patterns.txt";
print $fh '# ignore-me

random-inconsequential-string
';
close $fh;
%CheckSpelling::UnknownWordSplitter::dictionary = ();
my $output_directory;
open(my $outputFH, '>', \$output_directory) or die; # This shouldn't fail
my $oldFH = select $outputFH;
CheckSpelling::UnknownWordSplitter::main($directory, ($filename));
select $oldFH;
ok($output_directory =~ /.*\n/);
chomp($output_directory);
ok(-d $output_directory);
check_output_file("$output_directory/name", $filename);
check_output_file("$output_directory/stats", '{words: 2, unrecognized: 1, unknown: 1, unique: 2}');
check_output_file("$output_directory/unknown", 'Play');
check_output_file("$output_directory/warnings", "line 3 cols 8-11: 'Play'
");
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

$CheckSpelling::UnknownWordSplitter::largest_file = 1;
$output_dir=CheckSpelling::UnknownWordSplitter::split_file($filename);
$CheckSpelling::UnknownWordSplitter::forbidden_re='$^';
check_output_file("$output_dir/name", $filename);
check_output_file("$output_dir/stats", undef);
check_output_file("$output_dir/skipped", "size `72` exceeds limit `1`. (large-file)
");
$CheckSpelling::UnknownWordSplitter::largest_file = 1000000;
$CheckSpelling::UnknownWordSplitter::patterns_re = 'i.';
$ENV{'INPUT_LONGEST_WORD'} = 8;
CheckSpelling::UnknownWordSplitter::load_dictionary($filename);
is(scalar %CheckSpelling::UnknownWordSplitter::dictionary, 1);
$output_dir=CheckSpelling::UnknownWordSplitter::split_file($filename);
check_output_file("$output_dir/name", $filename);
check_output_file("$output_dir/stats", '{words: 0, unrecognized: 13, unknown: 8, unique: 0}');
check_output_file_sorted_lines("$output_dir/warnings", "line 1 cols 1-3: 'Foo'
line 1 cols 12-14: 'Bar'
line 1 cols 16-18: 'elf'
line 1 cols 20-22: 'baz'
line 1 cols 24-26: 'bar'
line 1 cols 4-6: 'Bar'
line 1 cols 8-10: 'baz'
line 2 cols 1-3: 'Foo'
line 2 cols 4-6: 'Bar'
line 2 cols 7-9: 'Bar'
");
check_output_file("$output_dir/unknown", 'Bar
Foo
bar
baz
elf
exp
ragel
supercal');
$CheckSpelling::UnknownWordSplitter::patterns_re = '$^';
