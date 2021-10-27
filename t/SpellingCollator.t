#!/usr/bin/perl -wT -Ilib

use strict;

use File::Temp qw/ tempfile tempdir /;
use IO::Capture::Stderr;

use Test::More;
plan tests => 19;

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

my $directory = tempdir();
my $directories = "$directory
/dev
/dev/null
/dev/no-such-dev
";

sub fill_file {
  my ($file, $content) = @_;
  open FILE, '>:utf8', $file;
  print FILE $content;
  close FILE;
}

fill_file("$directory/name", "hello.txt");
fill_file("$directory/skipped", "blah (skipped)\n");
my ($fh, $early_warnings, $warning_output, $more_warnings, $counter_summary);
($fh, $early_warnings) = tempfile;
($fh, $warning_output) = tempfile;
($fh, $more_warnings) = tempfile;
($fh, $counter_summary) = tempfile;
$ENV{'early_warnings'} = $early_warnings;
fill_file($early_warnings, "goose (animal)\n");
$ENV{'warning_output'} = $warning_output;
$ENV{'more_warnings'} = $more_warnings;
$ENV{'counter_summary'} = $counter_summary;
my $output;
open $fh, "<", \$directories;
my $capture = IO::Capture::Stderr->new();

$capture->start();
{
  local *ARGV = $fh;
  CheckSpelling::SpellingCollator::main();
}
$capture->stop();
my @error_lines = $capture->read();
my $error_lines = join "\n", @error_lines;
is($error_lines, 'Not a directory: /dev/null

Could not find: /dev/no-such-dev
');
check_output_file($warning_output, 'goose (animal)
hello.txt: line 1, columns 1-1, Warning - Skipping `hello.txt` because blah (skipped)
');
check_output_file($counter_summary, '{
"animal": 1
,"skipped": 1
}
');
check_output_file($more_warnings, '');

my $file_name='test.txt';
fill_file("$directory/name", $file_name);
fill_file("$directory/stats", '{words: 3, unrecognized: 2, unknown: 2, unique: 2}');
fill_file("$directory/warnings", "line 2 cols 3-8: 'something'
line 3 cols 3-5: 'Foo'
line 4 cols 3-6: 'foos'
line 5 cols 7-9: 'foo'
line 6 cols 3-9: 'fooies'
line 6 cols 3-9: 'fozed'
line 10 cols 4-10: 'something'");
fill_file("$directory/unknown", "xxxpaz
xxxpazs
jjjjjy
jjjjjies
nnnnnnnnns
hhhhed
hhhh
");
truncate($early_warnings, 0);
truncate($warning_output, 0);
truncate($more_warnings, 0);
truncate($counter_summary, 0);
unlink("$directory/skipped");
open $fh, "<", \$directories;
open(my $outputFH, '>', \$output) or die; # This shouldn't fail
my $oldFH = select $outputFH;
$capture->start();
{
  local *ARGV = $fh;
  CheckSpelling::SpellingCollator::main();
}
$capture->stop();
select $oldFH;
is($output, "hhhh (hhhh, hhhhed)
jjjjjy (jjjjjy, jjjjjies)
nnnnnnnnns
xxxpaz (xxxpaz, xxxpazs)
");
@error_lines = $capture->read();
$error_lines = join "\n", @error_lines;
is($error_lines, 'Not a directory: /dev/null

Could not find: /dev/no-such-dev
');
check_output_file($warning_output, "$file_name: line 2, columns 3-8, Warning - `something` is not a recognized word. (unrecognized-spelling)
");
check_output_file($counter_summary, '');
check_output_file($more_warnings, 'test.txt: line 10, columns 4-10, Warning - `something` is not a recognized word. (unrecognized-spelling)
');
