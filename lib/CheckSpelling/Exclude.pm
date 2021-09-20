#! -*-perl-*-

package CheckSpelling::Exclude;

our $VERSION='0.1.0';
use CheckSpelling::Util;

# This script takes null delimited files as input
# it drops paths that match the listed exclusions
# output is null delimited to match input

sub file_to_re {
  my ($file, $fallback) = @_;
  my @items;
  if (defined $file && -e $file) {
    open FILE, '<:utf8', $file;
    local $/=undef;
    my $file=<FILE>;
    for (split /\R/, $file) {
      next if /^#/;
      s/^\s*(.*)\s*$/(?:$1)/;
      s/\\Q(.*?)\\E/quotemeta($1)/eg;
      push @items, $_;
    }
  }
  my $pattern = scalar @items ? join "|", @items : $fallback;
  return $pattern;
}

sub main {
  my $exclude_file = CheckSpelling::Util::get_file_from_env('exclude_file', undef);
  my $only_file = CheckSpelling::Util::get_file_from_env('only_file', undef);

  my $exclude = file_to_re($exclude_file, '^$');
  my $only = file_to_re($only_file, '.');

  $/="\0";
  while (<>) {
    chomp;
    next if m{$exclude};
    next unless m{$only};
    print "$_$/";
  }
}

1;
