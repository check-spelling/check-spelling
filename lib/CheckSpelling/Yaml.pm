#! -*-perl-*-

package CheckSpelling::Yaml;

our $VERSION='0.1.0';
use CheckSpelling::Util;

sub report {
  my ($file, $start_line, $start_pos, $end, $message) = @_;
  print "$file:$start_line:$start_pos ... $end, $message\n";
  exit;
}

sub get_yaml_value {
  my ($file, $path) = @_;
  my @path_split = split /\./, $path;
  my $level = 0;
  my @prefixes;
  open $yaml, '<', $file || return '';
  my @result;
  my $line_result;
  my $mode;
  my $last;
  while (<$yaml>) {
    chomp;
    next if /^\s*#/;
    if (/^(\s*)(\S.*)/) {
      my ($prefix, $remainder) = ($1, $2);
      while ($level && length $prefix < length $prefixes[$level - 1]) {
        delete $prefixes[$level--];
      }
      if (@result && $level < scalar @path_split) {
        $last = 1;
        break;
      }
      last if $last;
      if (!$level || length $prefix > length $prefixes[$level - 1]) {
        if ($level == scalar @path_split) {
          push @result, $remainder;
        } else {
          my $next = $path_split[$level];
          if ($remainder =~ /$next:(.*)$/) {
            $prefixes[$level++] = $prefix;
            if ($level == scalar @path_split) {
              $mode = $1;
              if ($mode =~ /\s*([-+>|]+)\s*$/) {
                $mode = $1;
              } elsif ($mode =~ /\s*(\S.*?)\s*$/) {
                my $value = $1;
                $value =~ s/^'(.*)'$/$1/;
                $line_result = $value;
                last;
              }
            }
          }
        }
      }
    } elsif (/^\s*$/ && @result) {
      push @result, '';
    }
  }
  close $yaml;
  return $line_result unless @result;
  $mode =~ /([-+])/;
  my $newlines = $1;
  $mode =~ /([|>]?)/;
  $mode = $1;
  my $suffix;
  if ($newlines eq '') {
    $suffix = "\n";
  }
  unless ($newlines eq '+') {
    pop @result while (@result[$#result] eq '');
  }
  if ($mode eq '') {
    return (join ' ', @result).$suffix;
  }
  if ($mode eq '|') {
    return (join "\n", @result).$suffix;
  }
  if ($mode eq '>') {
    my @output;
    my $tentative;
    while (@result) {
      my $line = shift @result;
      if ($line eq '') {
        push @output, $tentative;
        $tentative = '';
      } else {
        $tentative .= $line;
      }
    }
    push @output, $tentative;
    return (join "\n", @output).$suffix;
  }
  return (join ' ? ', @result).$suffix;
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
