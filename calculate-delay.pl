#!/usr/bin/env perl
my $delay = 5;
while (<>) {
    next unless /^retry-after:\s*(\d+)/i;
    $delay = $1 || 1;
};
print $delay;
