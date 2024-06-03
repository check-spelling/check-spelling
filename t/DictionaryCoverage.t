#!/usr/bin/env -S perl -T -Ilib

use strict;
use warnings;

use File::Copy;
use File::Temp qw/ tempfile tempdir /;
use File::Basename;
use Test::More;
use Capture::Tiny ':all';
plan tests => 12;
use_ok('CheckSpelling::DictionaryCoverage');

my $name = '/dev/null';
my $object = CheckSpelling::DictionaryCoverage::entry($name);
isa_ok($object->{'handle'}, 'GLOB');
is($object->{'name'}, $name, 'object->name');
is($object->{'word'}, 0, 'object->word');
is($object->{'covered'}, 0, 'object->covered');

my $dictionary_dir = tempdir( CLEANUP => 1);

my ($fh, $filename, $dict);
($fh, $dict) = tempfile(DIR => $dictionary_dir);
print $fh 'does
this
what
';
close $fh;
my $output;
open(my $outputFH, '>', \$output) or die; # This shouldn't fail
my $oldFH = select $outputFH;
($fh, $filename) = tempfile();
print $fh 'this
what
';
close $fh;
$ENV{'aliases'}="s{$dict}{test:case}";
$ENV{'extra_dictionaries'} = $dict;
my @files = grep{/.*/} glob($dict);
CheckSpelling::DictionaryCoverage::main($filename, @files);
select $oldFH;
is($output, "2-3-2-$dict [$dict](test:case) (3) covers 2 of them (2 uniquely)
", 'covers uniquely 2-3');

my ($fh2, $one_match) = tempfile(DIR => $dictionary_dir);
print $fh2 'not
this
those
words
';
close $fh2;
my ($fh3, $no_match) = tempfile(DIR => $dictionary_dir);
close $fh3;
close $outputFH;
my $output2;
open(my $outputFH2, '>', \$output2) or die;
$oldFH = select $outputFH2;
unshift @files, $no_match, $one_match;
my ($suggest, $other, $ignore) = ('suggest:'.basename($dict), 'other:'.basename($one_match), 'ignore:'.basename($no_match));
$ENV{'extra_dictionaries'} = "
$suggest
$other
$ignore
";
my $one_match_name = basename $one_match;
my $dict_name = basename $dict;
my $no_name = basename $no_match;
open my $suggest_link_fh, '>', "$dictionary_dir/.$dict_name";
print $suggest_link_fh "suggest:$dict_name";
close $suggest_link_fh;
open my $one_link_fh, '>', "$dictionary_dir/.$one_match_name";
print $one_link_fh "other:$one_match_name";
close $one_link_fh;
open my $no_link_fh, '>', "$dictionary_dir/.$no_name";
print $no_link_fh "no:$no_name";
close $no_link_fh;

$ENV{'aliases'}="s{suggest:}{$dictionary_dir/};s{other:}{$dictionary_dir/};s{ignore:}{$dictionary_dir/}";
CheckSpelling::DictionaryCoverage::main($filename, @files);
select $oldFH;
is($output2, "1-4-0-other:$one_match_name [other:$one_match_name]($one_match) (4) covers 1 of them
2-3-1-suggest:$dict_name [suggest:$dict_name]($dict) (3) covers 2 of them (1 uniquely)
", 'covers uniquely 1-4');

($fh, $filename) = tempfile();
close $fh;
my ($stdout, $stderr, @result);
($stdout, $stderr, @result) = capture { CheckSpelling::DictionaryCoverage::main($filename, "no-such-file"); };
is($stderr, "Couldn't open dictionary \`no-such-file\` (dictionary-not-found)
", 'dictionary-not-found');

($stdout, $stderr, @result) = capture { CheckSpelling::DictionaryCoverage::main("/dev/no-such-file", ()); };
is($stderr, 'Could not read /dev/no-such-file
', 'no-such-file');

($stdout, $stderr, @result) = capture { CheckSpelling::DictionaryCoverage::main($filename, "/dev/no-such-file.dic"); };
my $dictionary_coverage = $stderr;
if ($dictionary_coverage =~ /hunspell-unavailable/) {
is($dictionary_coverage, 'Could not load Text::Hunspell for `/dev/no-such-file.dic` (hunspell-unavailable)
', 'no-such-file');
} else {
is($dictionary_coverage, "Couldn't open dictionary `/dev/no-such-file.dic` (dictionary-not-found)
", 'no-such-file');
}
($fh, $filename) = tempfile();
print $fh 'world
hello
try
worked
something
';
close $fh;
($stdout, $stderr, @result) = capture { CheckSpelling::DictionaryCoverage::main($filename, 't/sample.dic'); };
$dictionary_coverage = $stderr;
if ($dictionary_coverage =~ /hunspell-unavailable/) {
  is($dictionary_coverage, 'Could not load Text::Hunspell for `t/sample.dic` (hunspell-unavailable)
', 'hunspell-unavailable')
} else {
  is($dictionary_coverage, '', 'coverage for .dic');
}
copy('t/sample.dic', 't/sample2.dic');
($stdout, $stderr, @result) = capture { CheckSpelling::DictionaryCoverage::main($filename, 't/sample2.dic'); };
$dictionary_coverage = $stderr;
if ($dictionary_coverage =~ /hunspell-unavailable/) {
  is($dictionary_coverage, 'Could not load Text::Hunspell for `t/sample2.dic` (hunspell-unavailable)
', 'hunspell-unavailable')
} else {
  is($dictionary_coverage, 'error: t/sample2.aff: cannot open
error: t/sample2.aff: cannot open
', 'coverage for .dic');
}
