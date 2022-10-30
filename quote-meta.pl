#!/usr/bin/env perl
my $value = shift;
my $quoted = quotemeta($value);
$quoted =~ s{(\\+)([-.:])}{$1$1$2}g;
print $quoted;
