#!/usr/bin/env perl

my $head=$ENV{HEAD};
my $file=$ARGV[0];
open LOG, qq<git log --oneline -s --no-abbrev-commit -1 "$head" -- "$file"|>;
my $sha;
while (<LOG>) {
  s/\s.*$//;
  $sha=$_;
}
chomp $sha;
$head = $sha;
close LOG;
my $state=0;
my ($sha, $orig, $cur, $length);
open BLAME, qq<git blame -b -f -s -p "$head" -- "$file"|>;
while (<BLAME>) {
  if ($state == 0) {
    /([0-9a-f]{40,}) (\d+) (\d+)(?: (\d+)|)/;
    ($sha, $orig, $cur, $length) = ($1, $2, $3, $4);
    ++$state;
  } elsif ($state == 1) {
    if (s/^\t//) {
      $state = 0;
      if ($sha eq $head) {
        print "$head $file $cur) $_";
      }
    }
  }
}
close BLAME;
