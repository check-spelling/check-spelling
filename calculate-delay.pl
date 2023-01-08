#!/usr/bin/env perl

use CheckSpelling::Util;

my @lines;
while (<>) {
    push @lines;
}
print CheckSpelling::Util::calculate_delay(@lines);
