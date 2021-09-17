#!/usr/bin/perl -wT -Ilib

use strict;

use File::Temp qw/ tempfile tempdir /;
use File::Basename;
use Test::More;
plan tests => 7;
use_ok('CheckSpelling::DictionaryCoverage');

my $name = '/dev/null';
my $object = CheckSpelling::DictionaryCoverage::entry($name);
isa_ok($object->{'handle'}, 'GLOB');
is($object->{'name'}, $name);
is($object->{'word'}, 0);
is($object->{'covered'}, 0);

my ($fh, $filename, $dict);
($fh, $dict) = tempfile();
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
is($output, "2 [$dict](test:case) (3) covers 2 of them
");
my ($fh2, $one_match) = tempfile();
print $fh2 'not
this
those
words
';
close $fh2;
my ($fh3, $no_match) = tempfile();
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
$ENV{'aliases'}="s{suggest:}{".dirname($dict)."/};s{other:}{".dirname($one_match)."/};s{ignore:}{".dirname($no_match)."/}";
CheckSpelling::DictionaryCoverage::main($filename, @files);
select $oldFH;
my $one_match_name = basename $one_match;
my $dict_name = basename $dict;
is($output2, "1 [other:$one_match_name]($one_match) (4) covers 1 of them
2 [suggest:$dict_name]($dict) (3) covers 2 of them
");
