#!/usr/bin/env perl
my $pattern=q!(\s*)!.quotemeta($ENV{KEY}).q!\s*:\s*[-+|>]?\s*(?:|(?:\g{-1}\s*[^\n]+\n)*\g{-1}\s+)\s*!.quotemeta($ENV{VALUE}).q<\b>;
my $break=$/;
$/=undef;
my $file=<>;
for ($file =~ /$pattern/) {
    my ($start, $end) = ($-[0]+1, $+[0]+1);
    my $prefix = substr($file, 0, $start);
    my $lines = ($prefix =~ s/$break//g) + 1;
    my $lead = substr($file, $start, $end);
    $lead =~ /\S/;
    my $lead_count = $-[0] + 1;
    $end = $end - $start;
    $start = $lead_count;
    print "$ARGV:$lines:$start ... $end, $ENV{MESSAGE}\n";
}
