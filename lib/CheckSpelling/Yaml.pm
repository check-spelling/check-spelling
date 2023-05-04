#! -*-perl-*-

package CheckSpelling::Yaml;

our $VERSION='0.1.0';
use CheckSpelling::Util;

sub report {
  my ($file, $start_line, $start_pos, $end, $message) = @_;
  print "$file:$start_line:$start_pos ... $end, $message\n";
  exit;
}

sub check_yaml_key_value {
  my ($key, $value, $message) = @_;
  my ($state, $gh_yaml_mode) = (0, '');
  my @nests;
  my ($start_line, $start_pod, $end);

  while (<>) {
    if (/^(\s*)#/) {
      $end += length $_ if ($state == 3);
      next;
    }
    if ($state == 0) {
      next unless /^(\s*)\S+\s*:/;
      my $spaces = $1;
      my $len = length $spaces;
      while (scalar @nests && $len < $nests[$#nests]) {
        pop @nests;
      }
      push @nests, $len if (! scalar @nests || $len > $nests[$#nests]);
      if (/^\s*($key)\s*:\s*([|>][-+]?|\$\{\{.*|(?:"\s*|)$value)\s*$/) {
        $gh_yaml_mode = $2;
        ($start_line, $start_pos, $end) = ($., $-[1] + 1, $+[2] + 1);
        report($ARGV, $start_line, $start_pos, $end, $message) if ($gh_yaml_mode =~ /$value|\$\{\{/);
        $state = 1;
      }
    } elsif ($state == 1) {
      if (/^\s*(?:#.*|)$/) {
        $end += length $_;
        continue;
      }
      /^(\s*)(\S.*?)\s*$/;
      my ($spaces, $v) = ($1, $2);
      $len = length $spaces;
      if (scalar @nests && $len > $nests[$#nests] && $v =~ /$value/) {
        $end += $len + length $v;
        report($ARGV, $start_line, $start_pos, $end, $message);
      }
      pop @nests;
      $state = 0;
    }
  }
}

1;
