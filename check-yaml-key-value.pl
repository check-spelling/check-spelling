#!/usr/bin/env perl
my ($key, $value) = (quotemeta($ENV{KEY}), quotemeta($ENV{VALUE}));
my ($state, $gh_yaml_mode) = (0, '');
my @nests;
my ($start_line, $start_pod, $end);
sub report {
    print "$ARGV:$start_line:$start_pos ... $end, $ENV{MESSAGE}\n";
    exit;
}
while (<>) {
    if (/^(\s*)#/) {
        $end += length $_ if ($state == 3);
        next;
    }
    if ($state == 0) {
        next unless /^(\s*)\S+\s*:/;
        my $spaces = $1;
        my $len = length $spaces;
        while (scalar @nests && $len < $nests[$#nests]) {
            pop @nests;
        }
        push @nests, $len if (! scalar @nests || $len > $nests[$#nests]);
        if (/^\s*($key)\s*:\s*([|>][-+]?|\$\{\{.*|(?:"\s*|)$value)\s*$/) {
            $gh_yaml_mode = $2;
            ($start_line, $start_pos, $end) = ($., $-[1] + 1, $+[2] + 1);
            report() if ($gh_yaml_mode =~ /$value|\$\{\{/);
            $state = 1;
        }
    } elsif ($state == 1) {
        if (/^\s*(?:#.*|)$/) {
            $end += length $_;
            continue;
        }
        /^(\s*)(\S.*?)\s*$/;
        my ($spaces, $v) = ($1, $2);
        $len = length $spaces;
        if (scalar @nests && $len > $nests[$#nests] && $v =~ /$value/) {
            $end += $len + length $v;
            report();
        }
        pop @nests;
        $state = 0;
    }
}
