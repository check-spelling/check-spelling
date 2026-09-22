#!/usr/bin/env perl
my $new_state = 0;
my $no_such_file = "Could not open file (no-such-file)";
my $in_summary = 0;

print q<
# Tests
>;

sub test_header {
  print '
test|result
-|-
';
}

test_header();
while (<>) {
  if ($in_summary) {
    test_header() if /^--/;
  }
  if (m<t/.*\.t \.+ \w*$|^---|^\s*Failed test:|^\s*Non-zero exit status:|\([W]stat>) {
    $new_state = 1;
  }
  next unless ($new_state || $state);
  last if /^--+(?: --+){3}/;
  $state = $new_state;
  next unless /\w/;
  next if $last_line eq $_;
  next if /\Q$no_such_file\E/;
  if (/^Files=\d+, Tests=\d+,/) {
    if ($in_summary) {
      $in_summary=0;
      print "\n";
      test_header();
    }
    next;
  }
  next if /^(?:Reading database from |Devel::Cover: merging data)/;
  $last_line = $_;
  s/ \.+ ok/|✅/ || s/ \.+ /|/;
  s/^\s+(.*):\s*/... $1|/;
  s,^# (Looks like.*[^.]|Failed \d+/\d+ subtests)\.$,... $1|⚠️,;
  next if m/^#/;
  s/\s+(\([Ww]stat)/|❌ $1/ unless /\|/;
  s/All tests successful\./&nbsp;|\nAll tests|✅/;
  s/Result: PASS/Result|✅/;
  s/Result: FAIL/Result|❌/;
  s/\.($)/|😳$1/ if / at .* line \d+\./ && !/\|/;
  if (s/^(Test Summary Report)/\n## $1/) {
    $in_summary = 1;
  }
  print;
}
