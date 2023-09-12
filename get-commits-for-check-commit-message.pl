#!/usr/bin/env perl
while (<>) {
    unless ($state) {
        next unless /\bcheck.commit.messages\s*:/;
        $state = 1;
    }
    if ($state == 1) {
        if (/\bcommits\b|\$\{\{/ && ! /^\^/) {
            s/\s.*//;
            print;
        }
        if (/:/) {
            $state = 0;
        }
    }
}
