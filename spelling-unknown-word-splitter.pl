#!/bin/sh
#! -*-perl-*-
eval 'exec perl -x -T -w $0 ${1+"$@"}'
  if 0;
# ~/bin/w
# Search for potentially misspelled words
# Output is:
# misspellled
# woord (WOORD, Woord, woord, woord's)

use File::Basename;
use Cwd 'abs_path';
use File::Temp qw/ tempfile tempdir /;

my $dirname = dirname(abs_path(__FILE__));

# skip files that don't exist (including dangling symlinks)
if (scalar @ARGV) {
  @ARGV = grep {-r || $_ eq '-'} @ARGV;
  unless (scalar @ARGV) {
    print STDERR "None of the provided files are readable\n";
    exit 0;
  }
}

my $patterns_re = '^$';
if (open(PATTERNS, '<', "$dirname/patterns.txt")) {
  my @patterns;
  local $/=undef;
  local $file=<PATTERNS>;
  close PATTERNS;
  for (split /\R/, $file) {
    next if /^#/;
    chomp;
    next unless s/^(.+)/(?:$1)/;
    push @patterns, $_;
  }
  $patterns_re = join "|", @patterns if scalar @patterns;
}

# load dictionary
my $dict = "$dirname/words";
$dict = '/usr/share/dict/words' unless -e $dict;
open(DICT, '<', $dict);
my %dictionary=();
while ($word = <DICT>) {
  chomp $word;
  $dictionary{$word}=1;
}
close DICT;

# read all input
my ($last_file, $temp_dir, $words, $unrecognized) = ('', '', 0, 0);
my %unique;
my %unique_unrecognized;
my @reports;

sub report_stats() {
  if ($unrecognized) {
    open(STATS, '>', "$temp_dir/stats");
      print STATS "{words: $words, unrecognized: $unrecognized, unknown: ".(keys %unique_unrecognized).", unique: ".(keys %unique)."}";
    close STATS;
    open(UNKNOWN, '>', "$temp_dir/unknown");
      print UNKNOWN join "\n", sort keys %unique_unrecognized;
    close UNKNOWN;
    close WARNINGS;
  }
}

while (<<>>) {
  if ($last_file ne $ARGV) {
    $. = 1;
    $last_file = $ARGV;
    report_stats();

    $temp_dir = tempdir();
    push @reports, "$temp_dir\n";
    open(NAME, '>', "$temp_dir/name");
      print NAME $last_file;
    close NAME;
    ($words, $unrecognized) = (0, 0);
    %unique = ();
    %unique_unrecognized = ();
    open(WARNINGS, '>', "$temp_dir/warnings");
  }
  next unless /./;
  my $raw_line = $_;
  # hook for custom line based text exclusions:
  s/$patterns_re/ /g;
  # This is to make it easier to deal w/ rules:
  s/^/ /;
  while (s/([^\\])\\[rtn]/$1 /g) {}
  # https://www.fileformat.info/info/unicode/char/2019/
  my $rsqm = "\xE2\x80\x99";
  s/$rsqm/'/g;
  s/[^a-zA-Z']+/ /g;
  while (s/([A-Z]{2,})([A-Z][a-z]{2,})/ $1 $2 /g) {}
  while (s/([a-z']+)([A-Z])/$1 $2/g) {}
  my %unrecognized_line_items = ();
  for my $token (split /\s+/, $_) {
    $token =~ s/^(?:'|$rsqm)+//g;
    $token =~ s/(?:'|$rsqm)+s?$//g;
    my $raw_token = $token;
    $token =~ s/^[^Ii]?'+(.*)/$1/;
    $token =~ s/(.*?)'+$/$1/;
    next unless $token =~ /.../;
    if (defined $dictionary{$token}) {
      ++$words;
      $unique{$token}=1;
      next;
    }
    my $key = lc $token;
    $key =~ s/''+/'/g;
    $key =~ s/'[sd]$//;
    if (defined $dictionary{$key}) {
      ++$words;
      $unique{$key}=1;
      next;
    }
    ++$unrecognized;
    $unique_unrecognized{$raw_token}=1;
    $unrecognized_line_items{$raw_token}=1;
  }
  for my $token (keys %unrecognized_line_items) {
    $token =~ s/'/(?:'|$rsqm)+/g;
    while ($raw_line =~ /\b($token)\b/g) {
      my ($begin, $end, $match) = ($-[0] + 1, $+[0] + 1, $1);
      next unless $match =~ /./;
      print WARNINGS "line $. cols $begin-$end: '$match'\n";
    }
  }
}
report_stats();
print join '', @reports;
