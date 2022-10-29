#!/usr/bin/env perl
my $token=shift;
while (<>) {
    if (/\b(?:)$token\b/) {
        print 1;
        exit;
    }
}
