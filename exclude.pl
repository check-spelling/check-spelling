#!/usr/bin/perl
# This script takes null delimited files as input
# it drops paths that match the listed exclusions
# output is null delimited to match input
use File::Basename;
my $dirname = dirname(__FILE__);
my $exclude_file = $dirname.'/excludes.txt';
my @excludes;

if (-e $exclude_file) {
  open EXCLUDES, '<', $exclude_file;
  while (<EXCLUDES>) {
    s/^\s*(.*)\s*$/$1/;
    push @excludes, $_;
  }
}
$/="\0";
my $exclude = scalar @excludes ? join "|", @excludes : '^$';
while (<>) {
  chomp;
  next if m{$exclude};
  print "$_$/";
}
