#!/usr/bin/env -S perl -T

use warnings;
use File::Basename;
use CheckSpelling::Exclude;

my $dirname = dirname(__FILE__);
my $exclude_file = $dirname.'/excludes.txt';
my $only_file = $dirname.'/only.txt';
$ENV{'exclude_file'} = $exclude_file if -e $exclude_file;
$ENV{'only_file'} = $only_file if -e $only_file;
CheckSpelling::Exclude::main();
