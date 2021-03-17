#!/bin/sh
#! -*-perl-*-
eval 'exec perl -x -T -w $0 ${1+"$@"}'
  if 0;

die 'Please set $tokens_file' unless defined $ENV{tokens_file};
my $tokens_file=$ENV{tokens_file};
unless (open(TOKENS, '<', $tokens_file)) {
  print STDERR "$0 could not read $tokens_file\n";
  exit 0;
}

my $tokens;
{
  local $/= undef;
  $tokens = <TOKENS>;
}

my @token_list = split (/\s+/, $tokens);
exit 0 unless @token_list;

my @lower_list = grep /^[a-z]/, @token_list;
my @title_list = grep /^[A-Z][a-z]/, @token_list;
my @upper_list = grep /^[^a-z]+[a-z]?$/, @token_list;

my @re_list = ();
if (@upper_list) {
  my $upper_tokens = join '|', @upper_list;
  push @re_list, "(?:\\b|(?<=[a-z]))($upper_tokens)(?:\\b|(?=[A-Z][a-z]))";
}
if (@title_list) {
  my $title_tokens = join '|', @title_list;
  push @re_list, "(?:\\b|(?<=[a-z])|(?<=[A-Z]{2}))($title_tokens)(?:\\b|(?=[A-Z]))";
}
if (@lower_list) {
  my $lower_tokens = join '|', @lower_list;
  push @re_list, "(?:\\b|(?<=[A-Z]{2}))($lower_tokens)(?:\\b|(?![a-z]))";
}

my $re = join '|', @re_list;
my $rsqm = "\xE2\x80\x99";
$re =~ s/'/(?:'|$rsqm){1,3}/g;

my $blame=defined $ENV{with_blame};

my $previous='';
my $first_line=0;
while (<>) {
  my $line;
  if ($blame) {
    next if /^ /;
    next unless s/^[0-9a-f^]+\s+(.*?)\s(\d+)\) //;
    ($ARGV, $line) = ($1, $2);
  } else {
    if ($previous ne $ARGV) {
      $previous=$ARGV;
      $first_line = $. - 1;
    }
    $line = $. - $first_line;
  }
  next unless $_ =~ /$re/;
  while (/$re/g) {
    my ($start, $token) = (1 + length $`, $1 || $2 || $3);
    my $stop = $start + (length $token) - 1;
    print "$ARGV: line $line, columns $start-$stop, Warning - '$token' is not a recognized word. (unrecognized-spelling)\n";
  }
}
