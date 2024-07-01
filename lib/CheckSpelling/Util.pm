#! -*-perl-*-

use v5.20;

package CheckSpelling::Util;

use HTTP::Date;
use feature 'signatures';
no warnings qw(experimental::signatures);

our $VERSION='0.1.0';

sub get_file_from_env {
  my ($var, $fallback) = @_;
  return $fallback unless defined $ENV{$var};
  $ENV{$var} =~ /(.*)/s;
  return $1;
}

sub get_val_from_env {
  my ($var, $fallback) = @_;
  return $fallback unless defined $ENV{$var};
  $ENV{$var} =~ /^(\d+)$/;
  return $1 || $fallback;
}

sub case_biased :prototype($$) ($a, $b) {
  lc($a) cmp lc($b) || $a cmp $b;
}

sub number_biased :prototype($$) ($a, $b) {
  my ($aUnchecked, $bUnchecked) = ($a, $b);
  while ($aUnchecked ne '' && $bUnchecked ne '') {
    my ($aNumber, $bNumber);
    if ($aUnchecked =~ m/^(\d+)(.*)/) {
      $aNumber = $1;
      $aUnchecked = $2;
    }
    if ($bUnchecked =~ m/^(\d+)(.*)/) {
      $bNumber = $1;
      $bUnchecked = $2;
    }
    if (defined $aNumber && defined $bNumber) {
      return $aNumber <=> $bNumber if ($aNumber != $bNumber);
    } else {
      return $aNumber cmp $bUnchecked if defined $aNumber;
      return $aUnchecked cmp $bNumber if defined $bNumber;
      my ($aLetters, $bLetters);
      if ($aUnchecked =~ m/^(\D+)(.*)/) {
        $aLetters = $1;
        $aUnchecked = $2;
      }
      if ($bUnchecked =~ m/^(\D+)(.*)/) {
        $bLetters = $1;
        $bUnchecked = $2;
      }
      return case_biased($aLetters, $bLetters) if (defined $aLetters && defined $bLetters && !($aLetters eq $bLetters));
    }
  }
  return $aUnchecked cmp $bUnchecked;
}

sub list_with_terminator {
  my ($terminator, @list) = @_;
  return join "", map { "$_$terminator" } @list;
}

sub read_file {
  my ($name) = @_;
  local $/ = undef;
  my ($text, $file);
  if (open $file, '<:utf8', $name) {
    $text = <$file>;
    close $file;
  }
  return $text;
}

sub maybe_str2time {
  my ($time) = @_;
  $time = str2time $time;
  return $time if $time;
}

sub calculate_delay {
  my (@lines) = @_;
  my $now_stamp = time;
  my ($requested, $expires, $delay);
  for my $line (@lines) {
    if ($line =~ /^date:\s*(.*)/i) {
      $requested = maybe_str2time($1);
      next;
    }
    if ($line =~ /^expires:\s*(.*)/i) {
      $expires = maybe_str2time($1);
      next;
    }
    next unless $line =~ /^retry-after:\s*(\d+)/i;
    $delay = $1 || 1;
  }
  return $delay if defined $delay;
  if (defined $requested && defined $expires) {
    $delay = $expires - $requested;
  }
  $delay = 5 unless defined $delay && $delay > 0;

  return $delay;
}

1;
