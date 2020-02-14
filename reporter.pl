#!/usr/bin/env perl

die 'Please set $tokens' unless defined $ENV{tokens};
my $tokens=$ENV{tokens};
exit 0 unless $tokens =~ /\w/;
$tokens=~ s/\s+/|/g;
my $re = "\\b($tokens)\\b";
my $blame=defined $ENV{with_blame};

my $previous='';
my $first_line=0;
while (<>) {
  my $line;
  if ($blame) {
    next if /^ /;
    s/^[0-9a-f^]+\s+(.*?)\s(\d+)\) //;
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
    my ($start, $token) = (1 + length $`, $1);
    my $stop = $start + (length $token) - 1;
    print "$ARGV: line $line, columns $start-$stop, Warning - '$token' is not a recognized word. (unrecognized-spelling)\n";
  }
}
