#! -*-perl-*-

package CheckSpelling::Util;

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

1;
