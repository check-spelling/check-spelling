#!/usr/bin/env -S perl -T -Ilib

use strict;
use warnings;

use File::Temp qw/ tempfile tempdir /;
use Test::More;

plan tests => 5;
use_ok('CheckSpelling::Exclude');

my ($fh, $filename) = tempfile();
binmode( $fh, ":utf8" );
print $fh '# ignore
line
\Qx.y\E
';
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

{
my ($exclude_file, $only_file);
($fh, $exclude_file) = tempfile();
binmode( $fh, ":utf8" );
print $fh '# ignore
^excluded
';
close $fh;
$ENV{'exclude_file'}=$exclude_file;
($fh, $only_file) = tempfile();
binmode( $fh, ":utf8" );
print $fh '# ignore
txt$
';
close $fh;
$ENV{'only_file'}=$only_file;
my $oldIn = *ARGV;
my $text = '
excluded.txt
included.txt
ignored.md
';
$text =~ s/\n/\0/g;
open my $input, '<', \$text;
*ARGV = $input;
my $output;
open(my $outputFH, '>', \$output) or die; # This shouldn't fail
my $oldFH = select $outputFH;
CheckSpelling::Exclude::main();
*ARGV = $oldIn;
select $oldFH;
is($output, "included.txt\x00");
}
