#!/usr/bin/env -S perl

use warnings;

my ($collated, $notes) = @ARGV;
my @words;
open EXPECT, '<', $collated;
while (<EXPECT>) {
  chomp;
  next unless /(.*) \((.*)\)/;
  my ($key, $list) = ($1, $2);
  my @variants = split /, /, $list;
  @variants = grep { $_ ne $key } @variants;
  push @words, @variants;
}
close EXPECT;
my $pattern = '\`(?:'.join('|', map { quotemeta($_) } @words).')`';
open SOURCES, '<', $notes;
while (<SOURCES>) {
  if ($_ =~ /$pattern/) {
    $print = 0;
    $print = 1 if s/not a recognized word/ignored by check spelling because another more general variant is also in expect/;
    $print = 1 if s/unrecognized-spelling/ignored-expect-variant/;
    next unless $print;
  } else {
    next unless /\(((?:\w+-)+\w+)\)$/;
    next if $1 eq 'unrecognized-spelling';
  }
  print;
}
close SOURCES;
