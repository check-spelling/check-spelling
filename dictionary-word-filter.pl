#!/usr/bin/env perl
while (<>) {
    next unless /^[A-Za-z']+$/;
    print;
}
