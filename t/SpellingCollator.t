#!/usr/bin/env -S perl -T -w -Ilib

use strict;
use warnings;
use utf8;

use File::Temp qw/ tempfile tempdir /;
use Capture::Tiny ':all';

use Test::More;
plan tests => 57;

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
  my ($stdout, $stderr, @result) = capture {
    open my $fh, "<", \$directories;
    local *ARGV = $fh;
    CheckSpelling::SpellingCollator::main();
  };
  return ($stdout, $stderr);
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
  my ($file, $expected, $test) = @_;
  my $content = read_file($file);
  is($content, $expected, $test);
}

use_ok('CheckSpelling::SpellingCollator');

my ($fh, $early_warnings, $warning_output, $more_warnings, $counter_summary, $forbidden_patterns, $forbidden_summary, $candidates_path);

($fh, $early_warnings) = tempfile;
($fh, $warning_output) = tempfile;
($fh, $more_warnings) = tempfile;
($fh, $counter_summary) = tempfile;
($fh, $forbidden_patterns) = tempfile;
($fh, $forbidden_summary) = tempfile;
($fh, $candidates_path) = tempfile;
$ENV{'early_warnings'} = $early_warnings;
$ENV{'warning_output'} = $warning_output;
$ENV{'more_warnings'} = $more_warnings;
$ENV{'counter_summary'} = $counter_summary;
$ENV{'forbidden_path'} = $forbidden_patterns;
$ENV{'forbidden_summary'} = $forbidden_summary;
$ENV{'candidates_path'} = $candidates_path;

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
is(CheckSpelling::SpellingCollator::expect_item('bar', 1), 0, 'expect bar');
is(CheckSpelling::SpellingCollator::expect_item('foo', 1), 1, 'expect foo 1');
is(CheckSpelling::SpellingCollator::expect_item('foo', 2), 2, 'expect foo 2');
is(CheckSpelling::SpellingCollator::expect_item('fooy', 2), 2, 'expect fooy 2');
is(CheckSpelling::SpellingCollator::expect_item('foz', 2), 2, 'expect foz 2');
is($CheckSpelling::SpellingCollator::counters{'hi'}, undef, 'counters hi');
CheckSpelling::SpellingCollator::count_warning('(hi)');
is($CheckSpelling::SpellingCollator::counters{'hi'}, 1, 'counters hi counted in parentheses');
CheckSpelling::SpellingCollator::count_warning('hi');
is($CheckSpelling::SpellingCollator::counters{'hi'}, 1, 'counters hi counted');
CheckSpelling::SpellingCollator::count_warning('hello (hi)');
is($CheckSpelling::SpellingCollator::counters{'hi'}, 2, 'counters hi counted in parentheses again');
my $ignored_event = 'ignored-event';
$ENV{ignored_events} = $ignored_event;
CheckSpelling::Util::build_ignored_event_map();
is($CheckSpelling::SpellingCollator::counters{$ignored_event}, undef, 'counters ignored-event before counting');
CheckSpelling::SpellingCollator::count_warning("hello ($ignored_event)");
is($CheckSpelling::SpellingCollator::counters{$ignored_event}, undef, 'counters ignored-event not counted');
is(CheckSpelling::SpellingCollator::should_skip_warning_while_counting("hello ($ignored_event)"), 1, 'should_skip_warning_while_counting ignored');
my $countable_event = 'countable-event';
is(CheckSpelling::SpellingCollator::should_skip_warning_while_counting("hello ($countable_event)"), 0, 'should_skip_warning_while_counting not ignored');
is($CheckSpelling::SpellingCollator::counters{$countable_event}, 1, 'counted $countable_event');

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
', 'error_lines for file and nonexistent file');
check_output_file($warning_output, 'goose (animal)
hello.txt:1:1 ... 1, Warning - Skipping `hello.txt` because blah (skipped)
', 'warning_output skipped');
check_output_file($counter_summary, '{
"animal": 1
,"skipped": 1
}
', 'counter_summary animal+skipped');
check_output_file($more_warnings, '', 'more_warnings');

my $file_name='test.txt';
$directory = stage_test($file_name, '{words: 3, unrecognized: 2, unknown: 2, unique: 2}', '', ":2:3 ... 8: `something`
:3:3 ... 5: `Foo`
:4:3 ... 6: `foos`
:5:7 ... 9: `foo`
:6:3 ... 9: `fooies`
:6:3 ... 9: `fozed`
:10:4 ... 10: `something`", "xxxpaz
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
", 'output basic test collating');
is($error_lines, '', 'error lines basic test');
check_output_file($warning_output, q<test.txt:2:3 ... 8, Warning - `something` is not a recognized word (unrecognized-spelling)
>, 'warning_output');
check_output_file($counter_summary, '', 'counter_summary');
check_output_file($more_warnings, 'test.txt:10:4 ... 10, Warning - `something` is not a recognized word (unrecognized-spelling)
', 'more_warnings (overflow)');
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
(join "\n", map { ":1:1 ... 1: `$_`" } @word_variants),
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
", 'output');
is($error_lines, '', 'error_lines');
check_output_file($warning_output, q<case.txt:1:1 ... 1, Warning - `Aaa` is not a recognized word (unrecognized-spelling)
case.txt:1:1 ... 1, Warning - `aaa` is not a recognized word (unrecognized-spelling)
case.txt:1:1 ... 1, Warning - `bbb` is not a recognized word (unrecognized-spelling)
case.txt:1:1 ... 1, Warning - `Ddd` is not a recognized word (unrecognized-spelling)
case.txt:1:1 ... 1, Warning - `ddd` is not a recognized word (unrecognized-spelling)
case.txt:1:1 ... 1, Warning - `eee` is not a recognized word (unrecognized-spelling)
case.txt:1:1 ... 1, Warning - `FFF` is not a recognized word (unrecognized-spelling)
case.txt:1:1 ... 1, Warning - `Ggg` is not a recognized word (unrecognized-spelling)
case.txt:1:1 ... 1, Warning - `Jjj` is not a recognized word (unrecognized-spelling)
case.txt:1:1 ... 1, Warning - `lll` is not a recognized word (unrecognized-spelling)
>, 'warning_output');
check_output_file($counter_summary, '', 'counter_summary');
check_output_file($more_warnings, '', 'more_warnings');

fill_file($expect, q<calloc
alloc
malloc
>);

$directory = stage_test('punctuation.txt', '{words: 1000, unique: 1000}', '', ":1:1 ... 1: `calloc`
:1:1 ... 1: `calloc'd`
:1:1 ... 1: `a'calloc`
:1:1 ... 1: `malloc`
:1:1 ... 1: `malloc'd`
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
", 'output');
is($error_lines, '', 'punctuation error_lines');
check_output_file($warning_output, q<punctuation.txt:1:1 ... 1, Warning - `a'calloc` is not a recognized word (unrecognized-spelling)
>, 'warning_output');
check_output_file($counter_summary, '', 'counter_summary');
check_output_file($more_warnings, '', 'more_warnings');

$ENV{'INPUT_DISABLE_CHECKS'} = ",word-collating";

($output, $error_lines) = run_test($directory);
is($output, "a'calloc
calloc
calloc'd
malloc
malloc'd
", 'output');
$ENV{'INPUT_DISABLE_CHECKS'} = ",ignored";

my $file_names;
($fh, $file_names) = tempfile;
print $fh 'apple
pear
1/pear
2/pear';
close $fh;
fill_file($forbidden_patterns, '# please avoid starting lines with "pe" followed by a letter.
^pe.
');
$ENV{ignored_events} = 'ignored-warning';
$directory = stage_test($file_names, '{forbidden: [1], forbidden_lines: [2:1:3]}}', '', ":1:1 ... 5: `apple`
:2:1 ... 4: `pear`
:2:1 ... 3, Warning - `pea` matches a line_forbidden.patterns entry: `^pe.` (forbidden-pattern)
:2:1 ... 3, Warning - `something`. (ignored-warning)
:3:3 ... 6: `pear`
:4:3 ... 6: `pear`
", 'apple
pear');
$ENV{'check_file_names'} = $file_names;
$ENV{'unknown_file_word_limit'} = 2;
($output, $error_lines) = run_test($directory);
delete $ENV{'check_file_names'};
delete $ENV{'unknown_file_word_limit'};
check_output_file($counter_summary, '{
"check-file-path": 3
,"forbidden-pattern": 1
}
', 'counter_summary');
check_output_file($forbidden_summary, '##### please avoid starting lines with "pe" followed by a letter.
```
^pe.
```

', 'forbidden_summary');
check_output_file($warning_output, 'apple:1:1 ... 5, Warning - `apple` is not a recognized word (check-file-path)
pear:1:1 ... 4, Warning - `pear` is not a recognized word (check-file-path)
pear:1:1 ... 3, Warning - `pea` matches a line_forbidden.patterns entry: `^pe.` (forbidden-pattern)
1/pear:1:3 ... 6, Warning - `pear` is not a recognized word (check-file-path)
', 'warning_output');
truncate($forbidden_patterns, 0);

($fh, $file_names) = tempfile;
print $fh 'apple
apple
apple
pear';
close $fh;
$directory = stage_test($file_names, '{words: 3, unrecognized: 2, unknown: 2, unique: 2}', '', "
:1:1 ... 4: `apple`
:2:1 ... 4: `apple`
:3:1 ... 4: `apple`
:4:1 ... 4: `apple`
");
$ENV{'unknown_word_limit'} = 3;
($output, $error_lines) = run_test($directory);
check_output_file($warning_output, "$file_names
$file_names:1:1 ... 4, Warning - `apple` is not a recognized word (unrecognized-spelling)
", 'warning_output unrecognized-spelling');
check_output_file($more_warnings, "$file_names:2:1 ... 4, Warning - `apple` is not a recognized word (unrecognized-spelling)
$file_names:3:1 ... 4, Warning - `apple` is not a recognized word (unrecognized-spelling)
", 'more_warnings unrecognized-spelling');

delete $ENV{'unknown_word_limit'};

fill_file($candidates_path, '
# fruit
apple
');

$directory = stage_test($file_names, '{words: 3, unrecognized: 5, unknown: 8, unique: 2, candidates: [1], candidate_lines: [1:2:3]}', '', "
:1:1 ... 4: `apple`
:2:1 ... 4: `apple`
:3:1 ... 4: `apple`
:4:1 ... 4: `apple`
:5:1 ... 4: `apple`
:6:1 ... 4: `apple`
");
($output, $error_lines) = run_test($directory);
check_output_file($warning_output, "$file_names:1:2 ... 3, Notice - Line matches candidate pattern (fruit) `apple` (candidate-pattern)
$file_names:1:1 ... 1, Warning - Skipping `$file_names` because it seems to have more noise (8) than unique words (2) (total: 5 / 3). (noisy-file)
", 'warning_output with candidates');
check_output_file($more_warnings, "", 'more_warnings');

truncate($candidates_path, 0);

$ENV{'pr_title_file'} = $file_names;
$directory = stage_test($file_names, '{words: 3, unrecognized: 2, unknown: 2, unique: 2}', '', "
:1:1 ... 4: `apple`
");
($output, $error_lines) = run_test($directory);
check_output_file($warning_output, "$file_names
", 'warning_output');
check_output_file($more_warnings, "$file_names:1:1 ... 4, Warning - `apple` is not a recognized word (unrecognized-spelling-pr-title)
", 'more_warnings');

delete $ENV{'pr_title_file'};
$ENV{'pr_description_file'} = $file_names;
($output, $error_lines) = run_test($directory);
check_output_file($warning_output, "$file_names
", 'warning_output');
check_output_file($more_warnings, "$file_names:1:1 ... 4, Warning - `apple` is not a recognized word (unrecognized-spelling-pr-description)
", 'more_warnings');

my $commit_messages = tempdir();
$file_names = "$commit_messages/sha";
fill_file($file_names, 'apple
');
delete $ENV{'pr_description_file'};
$ENV{'commit_messages'} = $commit_messages;
$directory = stage_test("$commit_messages/sha", '{words: 3, unrecognized: 2, unknown: 2, unique: 2}', '', "
:1:1 ... 4: `apple`
");
($output, $error_lines) = run_test($directory);
check_output_file($warning_output, "$file_names
", 'warning_output');
check_output_file($more_warnings, "$file_names:1:1 ... 4, Warning - `apple` is not a recognized word (unrecognized-spelling-commit-message)
", 'more_warnings');

$CheckSpelling::SpellingCollator::shortest_word = 3;
is(CheckSpelling::SpellingCollator::stem_word('zeeps'), 'zeep', 'plural');
is(CheckSpelling::SpellingCollator::stem_word('zecked'), 'zeck', 'past tense');
is(CheckSpelling::SpellingCollator::stem_word('zeep'), 'zeep', 'singular');
is(CheckSpelling::SpellingCollator::stem_word('zies'), 'zies', 'shortish stem limit');
is(CheckSpelling::SpellingCollator::stem_word('zy'), 'zy', 'shortest stem limit');
is(CheckSpelling::SpellingCollator::stem_word('ked'), 'ked', 'past tense');
$CheckSpelling::SpellingCollator::shortest_word = 4;

my ($collated, $notes);
($fh, $collated) = tempfile;
print $fh '
apple (Apple, apple)
banana
Cherry
DATE
';
close $fh;
($fh, $notes) = tempfile;
print $fh '
Something `apple` (hello-world)
not a recognized word `Apple` (hello-world)
not a recognized word `Apple` (unrecognized-spelling)
is a recognized word `Apple` (unrecognized-spelling)
is a recognized word `Apple` (odd-spelling)
not a recognized word `Cherry` (unrecognized-spelling)
Something `APPLE`
Something `banana`
';
close $fh;

my ($stdout, $stderr, @result) = capture {
  CheckSpelling::SpellingCollator::collate_expect($collated, $notes);
};
is($stdout, 'Something `apple` (hello-world)
ignored because another more general variant (`apple`) is also in expect `Apple` (hello-world)
ignored because another more general variant (`apple`) is also in expect `Apple` (ignored-expect-variant)
is a recognized word `Apple` (ignored-expect-variant)
', 'collate_expect out');
is($stderr, '', 'collate_expect err');
is($result[0], 0, 'collate_expect result');
1;
