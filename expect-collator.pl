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
  next unless $_ =~ /$pattern/;
  s/not a recognized word/ignored by check spelling because another more general variant is also in expect/;
  s/unrecognized-spelling/ignored-expect-variant/;
  print;
}
close SOURCES;
