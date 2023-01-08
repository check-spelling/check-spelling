#! -*-perl-*-

use v5.20;

package CheckSpelling::Util;

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
  
sub read_file {
  my ($file) = @_;
  local $/ = undef;
  my ($content, $output);
  if (open $output, '<:utf8', $file) {
    $content = <$output>;
    close $output;
  }
  return $content;
}

sub calculate_delay {
  my (@lines) = @_;
  my $delay = 5;
  for my $line (@lines) {
    next unless /^retry-after:\s*(\d+)/i;
    $delay = $1 || 1;
  }
  return $delay;
}

1;
