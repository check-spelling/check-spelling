#!/usr/bin/perl -wT -Ilib

use strict;

use File::Temp qw/ tempfile tempdir /;
use Test::More;

plan tests => 4;
use_ok('CheckSpelling::Exclude');

my ($fh, $filename) = tempfile();
binmode( $fh, ":utf8" );
print $fh "# ignore
line
\\Qx.y\\E
";
close $fh;
is(CheckSpelling::Exclude::file_to_re($filename, "fallback"), "(?:line)|(?:x\\.y)");
is(CheckSpelling::Exclude::file_to_re("nonexistent", "fallback"), "fallback");

{
my $oldIn = *ARGV;
my $text = 'hello world';
open my $input, '<', \$text;
*ARGV = $input;
my $output;
open(my $outputFH, '>', \$output) or die; # This shouldn't fail
my $oldFH = select $outputFH;
CheckSpelling::Exclude::main();
*ARGV = $oldIn;
select $oldFH;
is($output, "hello world\x00");
}
