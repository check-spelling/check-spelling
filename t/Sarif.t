#!/usr/bin/env -S perl -T -Ilib

use strict;
use warnings;

use File::Basename;
use File::Temp qw/ tempfile /;
use Test::More;

plan tests => 3;
use_ok('CheckSpelling::Sarif');

is(CheckSpelling::Sarif::encode_low_ascii("\x05"), '\u0005');

my $tests = dirname(__FILE__);
my $base = dirname($tests);

$ENV{'CHECK_SPELLING_VERSION'} = '0.0.0';
my ($fh, $sarif_merged, $warnings);
($fh, $warnings) = tempfile();
print $fh 'lib/CheckSpelling/Sarif.pm:3:24 ... 29, Error - `Sarif` is not a recognized word. (unrecognized-spelling)
https://example.com/lib/CheckSpelling/Sarif.pm:3:24 ... 28, Error - `Star` is not a recognized word. (unrecognized-spelling)

';
close $fh;
$ENV{'warning_output'} = $warnings;
($fh, $sarif_merged) = tempfile();
print $fh CheckSpelling::Sarif::main("$base/sarif.json","$tests/sarif.json");
close $fh;
$ENV{'PATH'} = '/bin';
if (-e '/opt/homebrew/bin/go') {
    $ENV{'PATH'} .= ':/opt/homebrew/bin';
}

my $go_bin_output=`go env GOPATH`;
my $jd_output = '';
# if go isn't available, we'll skip this...
if ($go_bin_output) {
    $go_bin_output =~ /(.*)/;
    my $go_bin = $1;
    $ENV{'PATH'} = "/bin:$go_bin/bin";
    my $jd_output = `jd -set '$sarif_merged' '$tests/sarif.json.expected'`;
}
is($jd_output, '');
