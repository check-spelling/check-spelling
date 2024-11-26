#!/usr/bin/env -S perl -Ilib

use strict;
use warnings;

use File::Basename;
use File::Temp qw/ tempfile /;
use Test::More;
use JSON::PP;

plan tests => 3;
use_ok('CheckSpelling::Sarif');

is(CheckSpelling::Sarif::encode_low_ascii("\x05"), '\u0005');

my $tests = dirname(__FILE__);
my $base = dirname($tests);

$ENV{'CHECK_SPELLING_VERSION'} = '0.0.0';
my ($fh, $sarif_merged, $warnings);
($fh, $warnings) = tempfile();
print $fh 't/sarif/sample.txt:1:24 ... 28, Error - `meep` is not a recognized word. (unrecognized-spelling)
t/sarif/sample.txt:1:30 ... 34, Error - `meep` is not a recognized word. (unrecognized-spelling)
t/sarif/sample.txt:2:1 ... 5, Error - `meep` is not a recognized word. (unrecognized-spelling)
t/sarif/sample.txt:5:1 ... 7, Error - `mibbit` is not a recognized word. (unrecognized-spelling)
t/sarif/sample.txt:7:1 ... 7, Error - `mibbit` is not a recognized word. (unrecognized-spelling)
https://example.com/lib/CheckSpelling/Sarif.pm:3:24 ... 28, Error - `Star` is not a recognized word. (unrecognized-spelling)

';
close $fh;
$ENV{'warning_output'} = $warnings;
($fh, $sarif_merged) = tempfile();
my $sarif_generated = CheckSpelling::Sarif::main("$base/sarif.json","$tests/sarif.json", 'check-spelling/test');
print $fh $sarif_generated;
close $fh;
my $formatted_sarif;
($fh, $formatted_sarif) = tempfile();
close $fh;
`jq -M . '$sarif_merged'|perl -pe 's/^\\s*//' > '$formatted_sarif'`;

$ENV{'HOME'} =~ /^(.*)$/;
my $home = $1;
$ENV{'PATH'} = "/bin:/usr/bin:/opt/homebrew/bin";
my $expected_json;
my $formatted_sarif_json;
{
  local $/;
  open my $expected_json_file, '<', "$tests/sarif/expected.json";
  $expected_json = decode_json(<$expected_json_file>);
  close $expected_json_file;
  open my $formatted_sarif_file, '<', $formatted_sarif;
  $formatted_sarif_json = decode_json(<$formatted_sarif_file>);
  close $formatted_sarif_file;
}

is_deeply($formatted_sarif_json, $expected_json);
