#!/usr/bin/env perl
use CheckSpelling::Util;
my $skip_pattern = CheckSpelling::Util::get_file_from_env('INPUT_NOT_UPPER_OR_LOWER_PATTERN', q{[^A-Za-z']});
while (<>) {
    chomp;
    next if /$skip_pattern/;
    print "$_\n";
}
