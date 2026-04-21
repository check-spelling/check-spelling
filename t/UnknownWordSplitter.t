#!/usr/bin/env -S perl -T -w -Ilib

use 5.022;
use feature 'unicode_strings';
use strict;
use warnings;
use utf8;
binmode STDOUT, ':utf8';
binmode STDERR, ':utf8';

use Encode qw/decode_utf8 FB_DEFAULT/;
use Cwd 'abs_path';
use File::Basename;
use File::Temp qw/ tempfile tempdir /;
use Capture::Tiny ':all';

use Test::More;

my $builder = Test::More->builder;
binmode $builder->output,         ":utf8";
binmode $builder->failure_output, ":utf8";
binmode $builder->todo_output,    ":utf8";

plan tests => 66;

use_ok('CheckSpelling::UnknownWordSplitter');
use_ok('CheckSpelling::Exclude');

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
    my ($file, $expected, $test) = @_;
    my $content = read_file($file);
    is($content, $expected, $test);
}

sub sort_lines {
    my ($text) = @_;
    return join "\n", (sort (split /\n/, $text));
}

sub check_output_file_sorted_lines {
    my ($file, $expected, $test) = @_;
    is(sort_lines(read_file($file)), sort_lines($expected), 'sorted: '.($test || '...'));
}

$ENV{splitter_timeout} = 300000;
my ($fh, $filename) = tempfile();
print $fh "foo
Moprh
BROADDEPlay
mm
bar";
close $fh;
is(CheckSpelling::Exclude::file_to_re($filename), "(?:foo)|(?:Moprh)|(?:BROADDEPlay)|(?:mm)|(?:bar)", 'file_to_re');
$CheckSpelling::UnknownWordSplitter::word_match = CheckSpelling::UnknownWordSplitter::valid_word();
is($CheckSpelling::UnknownWordSplitter::word_match, q<(?^u:\b(?:\w|'){3,}\b)>, 'word_match');
$CheckSpelling::UnknownWordSplitter::shortest=100;
$CheckSpelling::UnknownWordSplitter::longest="";
CheckSpelling::UnknownWordSplitter::load_dictionary($filename);
is(scalar %CheckSpelling::UnknownWordSplitter::dictionary, 5, 'load dictionary with shortest=100');
is($CheckSpelling::UnknownWordSplitter::shortest, 3, 'calculate shortest');
is($CheckSpelling::UnknownWordSplitter::longest, 13, 'calculate longest');
is($CheckSpelling::UnknownWordSplitter::word_match, q<(?^u:\b(?:[A-Z]|[a-z]|'){3,13}\b)>, 'word_match');
$ENV{'INPUT_LONGEST_WORD'} = 5;
$ENV{'INPUT_SHORTEST_WORD'} = '';
$ENV{'INPUT_CHECK_HOMOGLYPHS'} = 1;
$ENV{'homoglyph_list_path'} = '.github/actions/spelling/homoglyph.list';
CheckSpelling::UnknownWordSplitter::load_dictionary($filename);
is(scalar %CheckSpelling::UnknownWordSplitter::dictionary, 5, 'load dictionary with longest=5');
is($CheckSpelling::UnknownWordSplitter::word_match, '(?^u:\b(?:[A-Z]|[a-z]|\'){3,5}\b)', 'word_match');
open $fh, ">>:utf8", $filename;
my $moprh_homoglyph = "Mo\x{3c1}rh";
print $fh "
$moprh_homoglyph
";
close $fh;
my $directory = tempdir();
open $fh, '>:utf8', "$directory/words";
print $fh 'bar
foo
Moprh
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

# other
\bdonut\b

\ba b c d e f\b
';
close $fh;
%CheckSpelling::UnknownWordSplitter::dictionary = ();
my $output_directory;
open(my $outputFH, '>', \$output_directory) or die; # This shouldn't fail
my $oldFH = select $outputFH;
CheckSpelling::UnknownWordSplitter::main($directory, ($filename));
select $oldFH;
ok($output_directory =~ /.*\n/, 'output directory');
chomp($output_directory);
ok(-d $output_directory, 'output directory exists');
check_output_file("$output_directory/name", $filename, 'name');
check_output_file("$output_directory/stats", '{words: 3, unrecognized: 1, unknown: 1, unique: 3}', 'stats');
check_output_file("$output_directory/unknown", 'Play
', 'unknown');
check_output_file("$output_directory/warnings", ":3:8 ... 12: `Play`
:6:1 ... 6, Error - `$moprh_homoglyph` should probably be `Moprh` (homoglyph-word)
", 'warnings');
open $fh, '>:utf8', $filename;
print $fh ("bar "x1000)."\n\n";
close $fh;
$output_dir=CheckSpelling::UnknownWordSplitter::split_file($filename);
check_output_file("$output_dir/skipped", 'average line width (4001) exceeds the threshold (1000) (minified-file)
', 'minified-file');
open $fh, '>:utf8', $filename;
print $fh '
bar\uFF37oprh; bar! Moprh
';
close $fh;
$output_dir=CheckSpelling::UnknownWordSplitter::split_file($filename);
check_output_file("$output_dir/name", $filename, 'name');
check_output_file("$output_dir/stats", '{words: 3, unrecognized: 1, unknown: 1, unique: 2}', 'stats');
check_output_file_sorted_lines("$output_dir/warnings", ":2:10 ... 14: `oprh`");
open $fh, '>:utf8', $filename;
print $fh "FooBar baz Bar elf baz bar supercalifragelisticexpialidocious
FooBarBar
";
close $fh;
$CheckSpelling::UnknownWordSplitter::forbidden_re='FooBarBar';
$output_dir=CheckSpelling::UnknownWordSplitter::split_file($filename);
$CheckSpelling::UnknownWordSplitter::forbidden_re='$^';
check_output_file("$output_dir/name", $filename, 'name');
check_output_file("$output_dir/stats", '{words: 7, unrecognized: 3, unknown: 2, unique: 2}', 'stats');
check_output_file_sorted_lines("$output_dir/warnings", ":1:8 ... 11: `baz`
:1:20 ... 23: `baz`
:1:16 ... 19: `elf`
:2:1 ... 10, Warning - `FooBarBar` matches a line_forbidden.patterns entry (forbidden-pattern)
", 'forbidden-pattern');
check_output_file("$output_dir/unknown", 'baz
elf
', 'unknown');

$CheckSpelling::UnknownWordSplitter::largest_file = 1;
$output_dir=CheckSpelling::UnknownWordSplitter::split_file($filename);
$CheckSpelling::UnknownWordSplitter::forbidden_re='$^';
check_output_file("$output_dir/name", $filename, 'name');
check_output_file("$output_dir/stats", undef, 'stats');
check_output_file("$output_dir/skipped", "size `72` exceeds limit `1` (large-file)
", 'skipped: large-file');
$CheckSpelling::UnknownWordSplitter::largest_file = 1000000;
$CheckSpelling::UnknownWordSplitter::patterns_re = 'i.';
$ENV{'INPUT_LONGEST_WORD'} = 8;
CheckSpelling::UnknownWordSplitter::load_dictionary($filename);
is(scalar %CheckSpelling::UnknownWordSplitter::dictionary, 1, 'dictionary count');
$output_dir=CheckSpelling::UnknownWordSplitter::split_file($filename);
check_output_file("$output_dir/name", $filename, 'name');
check_output_file("$output_dir/stats", '{words: 0, unrecognized: 13, unknown: 8, unique: 0}', 'stats');
check_output_file_sorted_lines("$output_dir/warnings", ":1:1 ... 4: `Foo`
:1:12 ... 15: `Bar`
:1:16 ... 19: `elf`
:1:20 ... 23: `baz`
:1:24 ... 27: `bar`
:1:28 ... 36: `supercal`
:1:38 ... 43: `ragel`
:1:4 ... 7: `Bar`
:1:48 ... 51: `exp`
:1:8 ... 11: `baz`
:2:1 ... 4: `Foo`
:2:4 ... 7: `Bar`
:2:7 ... 10: `Bar`
", 'warnings');
check_output_file("$output_dir/unknown", 'Bar
bar
baz
elf
exp
Foo
ragel
supercal
', 'unknown');
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
my ($stdout, $stderr, @result) = capture { CheckSpelling::UnknownWordSplitter::init($dirname); };
is($stdout, '', 'duplicate-pattern output');
is($stderr, $dirname.'/forbidden.txt:9:1 ... 9, Warning - duplicate pattern: `\bdonut\b` (duplicate-pattern)'."\n", 'duplicate-pattern warning');
is(@result, 1, 'duplicate-pattern result');
($fh, $filename) = tempfile();
print $fh "banana cherry a b c d e f
cherry fruit fruit egg
fruit donut grape donut banana
egg \xE2\x80\x99ham
grape
";
close $fh;
$output_dir=CheckSpelling::UnknownWordSplitter::split_file($filename);
check_output_file("$output_dir/name", $filename, 'name');
check_output_file("$output_dir/stats", '{words: 13, unrecognized: 1, unknown: 1, unique: 6, forbidden: [2,1,1], forbidden_lines: [3:7:12,2:7:20,1:15:26]}', 'stats');
check_output_file_sorted_lines("$output_dir/warnings", ":1:15 ... 26, Warning - `a b c d e f` matches a line_forbidden.patterns entry: `\\ba b c d e f\\b` (forbidden-pattern)
:2:7 ... 20, Warning - ` fruit fruit ` matches a line_forbidden.patterns rule: Flag duplicated \"words\" - `\\s([A-Z]{3,}|[A-Z][a-z]{2,}|[a-z]{3,})\\s\\g{-1}\\s` (forbidden-pattern)
:3:19 ... 24, Warning - `donut` matches a line_forbidden.patterns rule: forbidden - `\\bdonut\\b` (forbidden-pattern)
:3:7 ... 12, Warning - `donut` matches a line_forbidden.patterns rule: forbidden - `\\bdonut\\b` (forbidden-pattern)
:4:6 ... 9: `ham`
", 'warnings');
check_output_file("$output_dir/unknown", 'ham
', 'unknown');
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
ok($output_directory =~ /.*\n/, 'output directory');
chomp($output_directory);
ok(-d $output_directory, 'output directory exists');
check_output_file("$output_directory/stats", '{words: 13, unrecognized: 1, unknown: 1, unique: 6, candidates: [0,1], candidate_lines: [0,4:6:9], forbidden: [0,0,0], forbidden_lines: [0,0,0]}', 'stats');
check_output_file_sorted_lines("$output_directory/warnings", ":4:6 ... 9: `ham`
", 'warnings');
check_output_file("$output_directory/unknown", 'ham
', 'unknown');

$dirname = tempdir();
($fh, $filename) = tempfile();
close $fh;
$ENV{PATH}='/usr/bin';
$ENV{INPUT_USE_MAGIC_FILE}=1;
CheckSpelling::UnknownWordSplitter::init($dirname);
$output_dir=CheckSpelling::UnknownWordSplitter::split_file($filename);
check_output_file("$output_dir/skipped", "it appears to be a binary file (`inode/x-empty`) (binary-file)
", 'inode/x-empty');

$dirname = tempdir();
($fh, $filename) = tempfile();
print $fh "\x00"x5;
close $fh;
CheckSpelling::UnknownWordSplitter::init($dirname);
$CheckSpelling::UnknownWordSplitter::INPUT_LARGEST_FILE = 0;
$CheckSpelling::UnknownWordSplitter::INPUT_LARGEST_FILE = undef;
$output_dir=CheckSpelling::UnknownWordSplitter::split_file($filename);
check_output_file("$output_dir/skipped", "it appears to be a binary file (`application/octet-stream`) (binary-file)
", "skipped application/octet-stream");

my $hunspell_dictionary_path = tempdir();
$ENV{'hunspell_dictionary_path'} = $hunspell_dictionary_path;
open $fh, '>', "$hunspell_dictionary_path/test.dic";
close $fh;
open $fh, '>', "$hunspell_dictionary_path/test.aff";
close $fh;

$dirname = tempdir();
open $fh, '>:encoding(UTF-8)', "$directory/words";
print $fh "bar
fo'od
gunz
";
close $fh;
$ENV{'dict'} = "$directory/words";

sub init_maybe_hunspell_unavailable {
    my ($stdout, $stderr, @result) = capture { CheckSpelling::UnknownWordSplitter::init($dirname); };
    $stderr =~ s/^\QCould not load Text::Hunspell for dictionaries (hunspell-unavailable)\E\n$//;
    return ($stdout, $stderr, @result);
}

($stdout, $stderr, @result) = init_maybe_hunspell_unavailable();
is($stdout, '', 'hunspell out');
is($stderr, '', 'hunspell err');
is(@result, 1, 'hunspell result');
delete $ENV{'dict'};
($fh, $filename) = tempfile();
print $fh "bar
gunz
foad
fooo'd
fo'od
fa'ad
p-u-z-z-l-e
piece
";
close $fh;
$CheckSpelling::UnknownWordSplitter::ignore_next_line_pattern = 'p-u-z-z-l-e';
$output_dir=CheckSpelling::UnknownWordSplitter::split_file($filename);
$CheckSpelling::UnknownWordSplitter::ignore_next_line_pattern = '';
is(-e "$output_dir/skipped", undef, 'not skipped');
check_output_file("$output_dir/unknown", "fa'ad
foad
fooo'd
", 'unknown');
check_output_file("$output_dir/warnings", ":3:1 ... 5: `foad`
:4:1 ... 7: `fooo'd`
:6:1 ... 6: `fa'ad`
", 'warnings');
$dirname = tempdir();
($fh, $filename) = tempfile();
print $fh "\x05"x5;
close $fh;
($stdout, $stderr, @result) = init_maybe_hunspell_unavailable();
is($stdout, '', 'hunspell out');
is($stderr, '', 'hunspell err');
is(@result, 1, 'hunspell result');
$output_dir=CheckSpelling::UnknownWordSplitter::split_file($filename);
is(-e "$output_dir/skipped", undef, 'not skipped');
$dirname = tempdir();
($fh, $filename) = tempfile();
print $fh "\x05"x512;
close $fh;
($stdout, $stderr, @result) = init_maybe_hunspell_unavailable();
is($stdout, '', 'hunspell out');
is($stderr, '', 'hunspell err');
is(@result, 1, 'hunspell result');
$output_dir=CheckSpelling::UnknownWordSplitter::split_file($filename);

check_output_file("$output_dir/skipped", 'file only has a single line (single-line-file)
', 'single-line-file');

$ENV{INPUT_USE_MAGIC_FILE}='';

sub test_invalid_quantifiers {
  ($fh, $filename) = tempfile();
  print $fh ".{1,}*";
  close $fh;
  my $output = join "\n", CheckSpelling::UnknownWordSplitter::file_to_list($filename);
  is($output, '(?:\$^ - skipped because bad-regex)', 'bad-regex');
}

($stdout, $stderr, @result) = capture { test_invalid_quantifiers };
is($stderr, "Nested quantifiers in regex; marked by <-- HERE in m/.{1,}* <-- HERE / at $filename line 1 (bad-regex)
", 'nested quanitifiers bad-regex');
open $fh, '>:utf8', $filename;
for (my $i = 0; $i < 1000; $i++) {
    print $fh "bar$i\r";
}
close $fh;
$output_dir=CheckSpelling::UnknownWordSplitter::split_file($filename);
check_output_file("$output_dir/skipped", undef, 'not skipped');
open $fh, '>:utf8', $filename;
my $long_line = 'bar 'x250;
for (my $i = 0; $i < 10; $i++) {
    print $fh "$long_line$i\r";
}
close $fh;
$output_dir=CheckSpelling::UnknownWordSplitter::split_file($filename);
check_output_file("$output_dir/skipped", 'average line width (1002) exceeds the threshold (1000) (minified-file)
', 'minified-file');
open $fh, '>:utf8', $filename;
print $fh "======= ==== === a ==== ======\r\n"x127;
print $fh "======= wrnog === a ==== ======\r\n";
close $fh;
$output_dir=CheckSpelling::UnknownWordSplitter::split_file($filename);
check_output_file("$output_dir/warnings", ":128:9 ... 14: `wrnog`
", 'not minified');

SKIP: {
    skip 'could not find an expired artifact', 3 unless eval { symlink("",""); 1 };
    ($fh, $filename) = tempfile();
    close $fh;
    unlink($filename);
    symlink("/etc/hosts", $filename);
    $output_dir=CheckSpelling::UnknownWordSplitter::split_file($filename);
    is(read_file("$output_dir/skipped"), 'symbolic link points outside repository (out-of-bounds-symbolic-link)
', 'out-of-bounds-symbolic-link');
}
