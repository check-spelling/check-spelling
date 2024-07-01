#!/usr/bin/perl -T
use CheckSpelling::Util;

$, = "\n";
print sort CheckSpelling::Util::number_biased map { chomp; $_ } <>;
print "\n";
