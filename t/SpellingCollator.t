#!/usr/bin/env -S perl -T -Ilib

use strict;
use warnings;

use File::Temp qw/ tempfile tempdir /;
use IO::Capture::Stderr;

use Test::More;
plan tests => 31;

sub fill_file {
  my ($file, $content) = @_;
  return unless $content;
  open FILE, '>:utf8', $file;
  print FILE $content;
  close FILE;
}

sub stage_test {
  my ($name, $stats, $skipped, $warnings, $unknown) = @_;
  my $directory = tempdir();
  fill_file("$directory/name", $name);
  fill_file("$directory/stats", $stats);
  fill_file("$directory/skipped", $skipped);
  fill_file("$directory/warnings", $warnings);
  fill_file("$directory/unknown", $unknown);
  truncate($ENV{'early_warnings'}, 0);
  truncate($ENV{'warning_output'}, 0);
  truncate($ENV{'more_warnings'}, 0);
  truncate($ENV{'counter_summary'}, 0);
  return $directory;
}

sub run_test {
  my ($directories) = @_;
  my $output = '';
  open(my $outputFH, '>', \$output) or die; # This shouldn't fail
  my $oldFH = select $outputFH;
  my $capture = IO::Capture::Stderr->new();
  $capture->start();
  {
    open my $fh, "<", \$directories;
    local *ARGV = $fh;
    CheckSpelling::SpellingCollator::main();
  }
  $capture->stop();
  select $oldFH;
  return ($output, (join "\n", $capture->read()));
}

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

use_ok('CheckSpelling::SpellingCollator');

my ($fh, $early_warnings, $warning_output, $more_warnings, $counter_summary);

($fh, $early_warnings) = tempfile;
($fh, $warning_output) = tempfile;
($fh, $more_warnings) = tempfile;
($fh, $counter_summary) = tempfile;
$ENV{'early_warnings'} = $early_warnings;
$ENV{'warning_output'} = $warning_output;
$ENV{'more_warnings'} = $more_warnings;
$ENV{'counter_summary'} = $counter_summary;

my $directory = stage_test('empty.txt', '', '', '', '');
run_test($directory);

my ($fd, $expect) = tempfile;
$ENV{'expect'} = $expect;
print $fd "foo
fooy
foz
";
close $fd;
CheckSpelling::SpellingCollator::load_expect($expect);
is(CheckSpelling::SpellingCollator::expect_item('bar', 1), 0);
is(CheckSpelling::SpellingCollator::expect_item('foo', 1), 1);
is(CheckSpelling::SpellingCollator::expect_item('foo', 2), 2);
is(CheckSpelling::SpellingCollator::expect_item('fooy', 2), 2);
is(CheckSpelling::SpellingCollator::expect_item('foz', 2), 2);
is($CheckSpelling::SpellingCollator::counters{'hi'}, undef);
CheckSpelling::SpellingCollator::count_warning('(hi)');
is($CheckSpelling::SpellingCollator::counters{'hi'}, 1);
CheckSpelling::SpellingCollator::count_warning('hi');
is($CheckSpelling::SpellingCollator::counters{'hi'}, 1);
CheckSpelling::SpellingCollator::count_warning('hello (hi)');
is($CheckSpelling::SpellingCollator::counters{'hi'}, 2);

$directory = stage_test("hello.txt", '', "blah (skipped)\n", '', '');
my $directories = "$directory
/dev
/dev/null
/dev/no-such-dev
";

fill_file($early_warnings, "goose (animal)\n");
my ($output, $error_lines) = run_test($directories);
is($error_lines, 'Not a directory: /dev/null

Could not find: /dev/no-such-dev
');
check_output_file($warning_output, 'goose (animal)
hello.txt:1:1 ... 1, Warning - Skipping `hello.txt` because blah (skipped)
');
check_output_file($counter_summary, '{
"animal": 1
,"skipped": 1
}
');
check_output_file($more_warnings, '');

my $file_name='test.txt';
$directory = stage_test($file_name, '{words: 3, unrecognized: 2, unknown: 2, unique: 2}', '', ":2:3 ... 8: 'something'
:3:3 ... 5: 'Foo'
:4:3 ... 6: 'foos'
:5:7 ... 9: 'foo'
:6:3 ... 9: 'fooies'
:6:3 ... 9: 'fozed'
:10:4 ... 10: 'something'", "xxxpaz
xxxpazs
jjjjjy
jjjjjies
nnnnnnnnns
hhhhed
hhhh
");
($output, $error_lines) = run_test($directory);
is($output, "hhhh (hhhh, hhhhed)
jjjjjy (jjjjjy, jjjjjies)
nnnnnnnnns
xxxpaz (xxxpaz, xxxpazs)
");
is($error_lines, '');
check_output_file($warning_output, q<test.txt:2:3 ... 8, Warning - `something` is not a recognized word. (unrecognized-spelling)
>);
check_output_file($counter_summary, '');
check_output_file($more_warnings, 'test.txt:10:4 ... 10, Warning - `something` is not a recognized word. (unrecognized-spelling)
');
fill_file($expect, "
AAA
Bbb
ccc
DDD
Eee
Fff
GGG
Hhh
iii
");
my @word_variants=qw(AAA
Aaa
aaa
BBB
Bbb
bbb
CCC
Ccc
ccc
Ddd
ddd
Eee
eee
FFF
GGG
Ggg
HHH
Hhh
III
Iii
Jjj
lll
);
$directory = stage_test('case.txt', '{words: 1000, unique: 1000}', '',
(join "\n", map { ":1:1 ... 1: '$_'" } @word_variants),
(join "\n", @word_variants));
($output, $error_lines) = run_test($directory);
is($output, "aaa (AAA, Aaa, aaa)
bbb (BBB, Bbb, bbb)
ccc (CCC, Ccc, ccc)
ddd (Ddd, ddd)
eee (Eee, eee)
FFF
ggg (GGG, Ggg)
hhh (HHH, Hhh)
iii (III, Iii)
Jjj
lll
");
is($error_lines, '');
check_output_file($warning_output, q<case.txt:1:1 ... 1, Warning - `Aaa` is not a recognized word. (unrecognized-spelling)
case.txt:1:1 ... 1, Warning - `aaa` is not a recognized word. (unrecognized-spelling)
case.txt:1:1 ... 1, Warning - `bbb` is not a recognized word. (unrecognized-spelling)
case.txt:1:1 ... 1, Warning - `Ddd` is not a recognized word. (unrecognized-spelling)
case.txt:1:1 ... 1, Warning - `ddd` is not a recognized word. (unrecognized-spelling)
case.txt:1:1 ... 1, Warning - `eee` is not a recognized word. (unrecognized-spelling)
case.txt:1:1 ... 1, Warning - `FFF` is not a recognized word. (unrecognized-spelling)
case.txt:1:1 ... 1, Warning - `Ggg` is not a recognized word. (unrecognized-spelling)
case.txt:1:1 ... 1, Warning - `Jjj` is not a recognized word. (unrecognized-spelling)
case.txt:1:1 ... 1, Warning - `lll` is not a recognized word. (unrecognized-spelling)
>);
check_output_file($counter_summary, '');
check_output_file($more_warnings, '');

fill_file($expect, q<calloc
alloc
malloc
>);

$directory = stage_test('punctuation.txt', '{words: 1000, unique: 1000}', '', ":1:1 ... 1: 'calloc'
:1:1 ... 1: 'calloc'd'
:1:1 ... 1: 'a'calloc'
:1:1 ... 1: 'malloc'
:1:1 ... 1: 'malloc'd'
", q<
calloc
calloc'd
a'calloc
malloc
malloc'd
>);
($output, $error_lines) = run_test($directory);
is($output, "calloc (calloc, a'calloc, calloc'd)
malloc (malloc, malloc'd)
");
is($error_lines, '');
check_output_file($warning_output, q<punctuation.txt:1:1 ... 1, Warning - `a'calloc` is not a recognized word. (unrecognized-spelling)
>);
check_output_file($counter_summary, '');
check_output_file($more_warnings, '');

my $file_names;
($fh, $file_names) = tempfile;
print $fh 'apple
pear';
close $fh;
$directory = stage_test($file_names, '{}', '', ":1:1 ... 5: 'apple'
:2:1 ... 4: 'pear'
:2:1 ... 3, Warning - `pea` matches a line_forbidden.patterns entry: `^pe.`. (forbidden-pattern)
", 'apple
pear');
$ENV{'check_file_names'} = $file_names;
($output, $error_lines) = run_test($directory);
delete $ENV{'check_file_names'};
check_output_file($counter_summary, '{
"check-file-path": 2
,"forbidden-pattern": 1
}
');
check_output_file($warning_output, 'apple:1:1 ... 5, Warning - `apple` is not a recognized word. (check-file-path)
pear:1:1 ... 4, Warning - `pear` is not a recognized word. (check-file-path)
pear:1:1 ... 3, Warning - `pea` matches a line_forbidden.patterns entry: `^pe.`. (forbidden-pattern)
');
