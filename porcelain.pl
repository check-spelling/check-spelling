#!/bin/sh
#! -*-perl-*-
eval 'exec perl -x -T -w $0 ${1+"$@"}'
  if 0;

my $head=$ENV{HEAD};
my $file=$ARGV[0];
delete @ENV{qw(IFS CDPATH ENV BASH_ENV)};
$ENV{'PATH'}='/usr/local/bin:/usr/bin:/bin';
open LOG, '-|', 'git', 'log', '--oneline', '-s', '--no-abbrev-commit', '-1', $head, '--', $file;
my $sha;
while (<LOG>) {
  s/\s.*$//;
  $sha=$_;
}
chomp $sha;
$head = $sha;
close LOG;
my $state=0;
my ($orig, $cur, $length);
open BLAME, '-|', 'git', 'blame', '-b', '-f', '-s', '-p', $head, '--', $file;
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
