#!/usr/bin/env -S perl -T -Ilib

use 5.022;
use feature 'unicode_strings';
use strict;
use warnings;
use Encode qw/decode_utf8 FB_DEFAULT/;
use Cwd 'abs_path';
use File::Basename;
use File::Temp qw/ tempfile tempdir /;
use Capture::Tiny ':all';

use Test::More;
plan tests => 44;

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
is($CheckSpelling::UnknownWordSplitter::word_match, '(?^u:\b(?:\w){3,}\b)');
$CheckSpelling::UnknownWordSplitter::shortest=100;
$CheckSpelling::UnknownWordSplitter::longest="";
CheckSpelling::UnknownWordSplitter::load_dictionary($filename);
is(scalar %CheckSpelling::UnknownWordSplitter::dictionary, 4);
is($CheckSpelling::UnknownWordSplitter::shortest, 3);
is($CheckSpelling::UnknownWordSplitter::longest, 13);
is($CheckSpelling::UnknownWordSplitter::word_match, '(?^u:\b(?:\w){3,13}\b)');
$ENV{'INPUT_LONGEST_WORD'} = 5;
$ENV{'INPUT_SHORTEST_WORD'} = '';
CheckSpelling::UnknownWordSplitter::load_dictionary($filename);
is(scalar %CheckSpelling::UnknownWordSplitter::dictionary, 4);
is($CheckSpelling::UnknownWordSplitter::word_match, '(?^u:\b(?:\w){3,5}\b)');
my $directory = tempdir();
open $fh, '>:utf8', "$directory/words";
print $fh 'bar
foo
';
close $fh;
my $output_dir;
my $dirname = tempdir();
CheckSpelling::UnknownWordSplitter::init($dirname);

open $fh, '>', "$dirname/forbidden.txt";
print $fh '# forbidden
# donut
\bdonut\b

# Flag duplicated "words"
\s([A-Z]{3,}|[A-Z][a-z]{2,}|[a-z]{3,})\s\g{-1}\s
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
check_output_file("$output_directory/unknown", 'Play
');
check_output_file("$output_directory/warnings", ":3:8 ... 12: 'Play'
");
open $fh, '>:utf8', $filename;
print $fh ("bar "x1000)."\n";
close $fh;
$output_dir=CheckSpelling::UnknownWordSplitter::split_file($filename);
check_output_file("$output_dir/skipped", 'average line width (4001) exceeds the threshold (1000). (minified-file)
');
open $fh, '>:utf8', $filename;
print $fh "FooBar baz Bar elf baz bar supercalifragelisticexpialidocious
FooBarBar
";
close $fh;
$CheckSpelling::UnknownWordSplitter::forbidden_re='FooBarBar';
$output_dir=CheckSpelling::UnknownWordSplitter::split_file($filename);
$CheckSpelling::UnknownWordSplitter::forbidden_re='$^';
check_output_file("$output_dir/name", $filename);
check_output_file("$output_dir/stats", '{words: 4, unrecognized: 3, unknown: 2, unique: 2}');
check_output_file_sorted_lines("$output_dir/warnings", ":1:8 ... 11: 'baz'
:1:20 ... 23: 'baz'
:1:16 ... 19: 'elf'
:2:1 ... 10, Warning - `FooBarBar` matches a line_forbidden.patterns entry. (forbidden-pattern)
");
check_output_file("$output_dir/unknown", 'baz
elf
');

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
check_output_file_sorted_lines("$output_dir/warnings", ":1:1 ... 4: 'Foo'
:1:12 ... 15: 'Bar'
:1:16 ... 19: 'elf'
:1:20 ... 23: 'baz'
:1:24 ... 27: 'bar'
:1:28 ... 36: 'supercal'
:1:38 ... 43: 'ragel'
:1:4 ... 7: 'Bar'
:1:48 ... 51: 'exp'
:1:8 ... 11: 'baz'
:2:1 ... 4: 'Foo'
:2:4 ... 7: 'Bar'
:2:7 ... 10: 'Bar'
");
check_output_file("$output_dir/unknown", 'Bar
bar
baz
elf
exp
Foo
ragel
supercal
');
$CheckSpelling::UnknownWordSplitter::patterns_re = '$^';

close $fh;
open $fh, '>', "$dirname/words";
print $fh 'apple
banana
cherry
donut
egg
fruit
grape
';
close $fh;
CheckSpelling::UnknownWordSplitter::init($dirname);
($fh, $filename) = tempfile();
print $fh "banana cherry
cherry fruit fruit egg
fruit donut grape donut banana
egg \xE2\x80\x99ham
grape
";
close $fh;
$output_dir=CheckSpelling::UnknownWordSplitter::split_file($filename);
check_output_file("$output_dir/name", $filename);
check_output_file("$output_dir/stats", '{words: 9, unrecognized: 1, unknown: 1, unique: 5, forbidden: [2,1], forbidden_lines: [3:7:12,2:7:20]}');
check_output_file_sorted_lines("$output_dir/warnings", ":2:7 ... 20, Warning - ` fruit fruit ` matches a line_forbidden.patterns entry: `\\s([A-Z]{3,}|[A-Z][a-z]{2,}|[a-z]{3,})\\s\\g{-1}\\s`. (forbidden-pattern)
:3:19 ... 24, Warning - `donut` matches a line_forbidden.patterns entry: `\\bdonut\\b`. (forbidden-pattern)
:3:7 ... 12, Warning - `donut` matches a line_forbidden.patterns entry: `\\bdonut\\b`. (forbidden-pattern)
:4:6 ... 9: 'ham'
");
check_output_file("$output_dir/unknown", 'ham
');
open $fh, '>', "$dirname/candidates.txt";
print $fh '# grape
grape

# pig
ham

';
close $fh;
unlink("$dirname/forbidden.txt");
CheckSpelling::UnknownWordSplitter::init($dirname);
open($outputFH, '>', \$output_directory) or die; # This shouldn't fail
$oldFH = select $outputFH;
CheckSpelling::UnknownWordSplitter::main($directory, ($filename));
select $oldFH;
ok($output_directory =~ /.*\n/);
chomp($output_directory);
ok(-d $output_directory);
check_output_file("$output_directory/stats", '{words: 13, unrecognized: 1, unknown: 1, unique: 6, candidates: [0,1], candidate_lines: [0,4:6:9], forbidden: [0,0], forbidden_lines: [0,0]}');
check_output_file_sorted_lines("$output_directory/warnings", ":4:6 ... 9: 'ham'
");
check_output_file("$output_directory/unknown", 'ham
');

$dirname = tempdir();
($fh, $filename) = tempfile();
close $fh;
$ENV{PATH}='/usr/bin';
$ENV{INPUT_USE_MAGIC_FILE}=1;
CheckSpelling::UnknownWordSplitter::init($dirname);
$output_dir=CheckSpelling::UnknownWordSplitter::split_file($filename);
check_output_file("$output_dir/skipped", "appears to be a binary file ('inode/x-empty'). (binary-file)
");

$dirname = tempdir();
($fh, $filename) = tempfile();
print $fh "\x00"x5;
close $fh;
CheckSpelling::UnknownWordSplitter::init($dirname);
$CheckSpelling::UnknownWordSplitter::INPUT_LARGEST_FILE = 0;
$CheckSpelling::UnknownWordSplitter::INPUT_LARGEST_FILE = undef;
$output_dir=CheckSpelling::UnknownWordSplitter::split_file($filename);
check_output_file("$output_dir/skipped", "appears to be a binary file ('application/octet-stream'). (binary-file)
");

my $hunspell_dictionary_path = tempdir();
$ENV{'hunspell_dictionary_path'} = $hunspell_dictionary_path;
open $fh, '>', "$hunspell_dictionary_path/test.dic";
close $fh;
open $fh, '>', "$hunspell_dictionary_path/test.aff";
close $fh;

$dirname = tempdir();
($fh, $filename) = tempfile();
print $fh "\x05"x5;
close $fh;
CheckSpelling::UnknownWordSplitter::init($dirname);
$output_dir=CheckSpelling::UnknownWordSplitter::split_file($filename);
is(-e "$output_dir/skipped", undef);

$ENV{INPUT_USE_MAGIC_FILE}='';

sub test_invalid_quantifiers {
  ($fh, $filename) = tempfile();
  print $fh ".{1,}*";
  close $fh;
  my $output = join "\n", CheckSpelling::UnknownWordSplitter::file_to_list($filename);
  is($output, '');
}

my ($stdout, $stderr, @result) = capture { test_invalid_quantifiers };
is($stderr, "Nested quantifiers in regex; marked by <-- HERE in m/.{1,}* <-- HERE / at $filename line 1 (bad-regular-expression)
");
open $fh, '>:utf8', $filename;
for (my $i = 0; $i < 1000; $i++) {
    print $fh "bar$i\r";
}
close $fh;
$output_dir=CheckSpelling::UnknownWordSplitter::split_file($filename);
check_output_file("$output_dir/skipped", undef);
open $fh, '>:utf8', $filename;
my $long_line = 'bar 'x250;
for (my $i = 0; $i < 10; $i++) {
    print $fh "$long_line$i\r";
}
close $fh;
$output_dir=CheckSpelling::UnknownWordSplitter::split_file($filename);
check_output_file("$output_dir/skipped", 'average line width (1002) exceeds the threshold (1000). (minified-file)
');
open $fh, '>:utf8', $filename;
