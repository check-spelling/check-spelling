#! -*-perl-*-

package CheckSpelling::SpellingCollator;

our $VERSION='0.1.0';
use warnings;
use File::Path qw(remove_tree);
use CheckSpelling::Util;

my %letter_map;

sub get_field {
  my ($record, $field) = @_;
  return undef unless $record =~ (/\b$field:\s*(\d+)/);
  return $1;
}

sub maybe {
  my ($next, $value) = @_;
  $next = $value unless $next && $next < $value;
  return $next;
}

my %expected = ();
sub expect_item {
  my ($item, $value) = @_;
  our %expected;
  my $next;
  if (defined $expected{$item}) {
    $next = $expected{$item};
    $next = $value if $value < $next;
  } elsif ($item =~ /^([A-Z])(.*)/) {
    $item = $1 . lc $2;
    if (defined $expected{$item}) {
      $next = $expected{$item};
      $next = maybe($next, $value + .1);
    } else {
      $item = lc $item;
      if (defined $expected{$item}) {
        $next = $expected{$item};
        $next = maybe($next, $value + .2);
      }
    }
  }
  return 0 unless defined $next;
  $expected{$item} = $next;
  return $value;
}

sub skip_item {
  my ($word) = @_;
  return 1 if expect_item($word, 1);
  my $key = lc $word;
  return 2 if expect_item($key, 2);
  if ($key =~ /.s$/) {
    if ($key =~ /ies$/) {
      $key =~ s/ies$/y/;
    } else {
      $key =~ s/s$//;
    }
  } elsif ($key =~ /^(.+[^aeiou])ed$/) {
    $key = $1;
  } elsif ($key =~ /^(.+)'[ds]$/) {
    $key = $1;
  } else {
    return 0;
  }
  return 3 if expect_item($key, 3);
  return 0;
}

sub load_expect {
  my ($expect) = @_;
  our %expected;
  %expected = ();
  if (open(EXPECT, '<:utf8', $expect)) {
    while ($word = <EXPECT>) {
      $word =~ s/\R//;
      $expected{$word} = 0;
    }
    close EXPECT;
  }
}

sub count_warning {
  my ($warning) = @_;
  our %counters;
  if ($warning =~ /\(([-\w]+)\)$/) {
    my ($code) = ($1);
    ++$counters{$code};
  }
}

sub main {
  my @directories;
  my @cleanup_directories;

  my %unknown;

  my $early_warnings = CheckSpelling::Util::get_file_from_env('early_warnings', '/dev/null');
  my $warning_output = CheckSpelling::Util::get_file_from_env('warning_output', '/dev/stderr');
  my $more_warnings = CheckSpelling::Util::get_file_from_env('more_warnings', '/dev/stderr');
  my $counter_summary = CheckSpelling::Util::get_file_from_env('counter_summary', '/dev/stderr');
  my $should_exclude_file = CheckSpelling::Util::get_file_from_env('should_exclude_file', '/dev/null');

  open WARNING_OUTPUT, '>:utf8', $warning_output;
  open MORE_WARNINGS, '>:utf8', $more_warnings;
  open COUNTER_SUMMARY, '>:utf8', $counter_summary;
  open SHOULD_EXCLUDE, '>:utf8', $should_exclude_file;

  my @delayed_warnings;
  %letter_map = ();

  for my $directory (<>) {
    chomp $directory;
    next unless $directory =~ /^(.*)$/;
    $directory = $1;
    unless (-e $directory) {
      print STDERR "Could not find: $directory\n";
      next;
    }
    unless (-d $directory) {
      print STDERR "Not a directory: $directory\n";
      next;
    }

    # if there's no filename, we can't report
    next unless open(NAME, '<:utf8', "$directory/name");
    my $file=<NAME>;
    close NAME;

    if (-e "$directory/skipped") {
      open SKIPPED, '<:utf8', "$directory/skipped";
      my $reason=<SKIPPED>;
      close SKIPPED;
      chomp $reason;
      push @delayed_warnings, "$file: line 1, columns 1-1, Warning - Skipping `$file` because $reason\n";
      print SHOULD_EXCLUDE "$file\n";
      push @cleanup_directories, $directory;
      next;
    }

    # stats isn't written if all words in the file are in the dictionary
    next unless (-s "$directory/stats");

    my ($words, $unrecognized, $unknown, $unique);

    {
      open STATS, '<:utf8', "$directory/stats";
      my $stats=<STATS>;
      close STATS;
      $words=get_field($stats, 'words');
      $unrecognized=get_field($stats, 'unrecognized');
      $unknown=get_field($stats, 'unknown');
      $unique=get_field($stats, 'unique');
      #print STDERR "$file (unrecognized: $unrecognized; unique: $unique; unknown: $unknown, words: $words)\n";
    }

    # These heuristics are very new and need tuning/feedback
    if (
        ($unknown > $unique)
        # || ($unrecognized > $words / 2)
    ) {
      push @delayed_warnings, "$file: line 1, columns 1-1, Warning - Skipping `$file` because there seems to be more noise ($unknown) than unique words ($unique) (total: $unrecognized / $words). (noisy-file)\n";
      print SHOULD_EXCLUDE "$file\n";
      push @cleanup_directories, $directory;
      next;
    }
    unless (-s "$directory/unknown") {
      push @cleanup_directories, $directory;
      next;
    }
    open UNKNOWN, '<:utf8', "$directory/unknown";
    for $token (<UNKNOWN>) {
      $token =~ s/\R//;
      $token =~ s/^[^Ii]?'+(.*)/$1/;
      $token =~ s/(.*?)'+$/$1/;
      next unless $token =~ /./;
      my $key = lc $token;
      $key =~ s/''+/'/g;
      $key =~ s/'[sd]$//;
      my $char = substr $key, 0, 1;
      $letter_map{$char} = () unless defined $letter_map{$char};
      my %word_map = ();
      %word_map = %{$letter_map{$char}{$key}} if defined $letter_map{$char}{$key};
      $word_map{$token} = 1;
      $letter_map{$char}{$key} = \%word_map;
    }
    close UNKNOWN;
    push @directories, $directory;
  }
  close SHOULD_EXCLUDE;

  if (defined $ENV{'expect'}) {
    $ENV{'expect'} =~ /(.*)/;
    load_expect $1;
  }

  my %seen = ();
  our %counters;
  %counters = ();

  if (-s $early_warnings) {
    open WARNINGS, '<:utf8', $early_warnings;
    for my $warning (<WARNINGS>) {
      chomp $warning;
      count_warning $warning;
      print WARNING_OUTPUT "$warning\n";
    }
    close WARNINGS;
  }

  for my $directory (@directories) {
    next unless (-s "$directory/warnings");
    next unless open(NAME, '<:utf8', "$directory/name");
    my $file=<NAME>;
    close NAME;
    open WARNINGS, '<:utf8', "$directory/warnings";
    for $warning (<WARNINGS>) {
      chomp $warning;
      if ($warning =~ s/(line \d+) cols (\d+-\d+): '(.*)'/$1, columns $2, Warning - `$3` is not a recognized word. (unrecognized-spelling)/) {
        my ($line, $range, $item) = ($1, $2, $3);
        next if skip_item($item);
        if (defined $seen{$item}) {
          print MORE_WARNINGS "$file: $warning\n";
          next;
        }
        $seen{$item} = 1;
      } else {
        count_warning $warning;
      }
      print WARNING_OUTPUT "$file: $warning\n";
    }
    close WARNINGS;
  }
  close MORE_WARNINGS;

  for my $warning (@delayed_warnings) {
    count_warning $warning;
    print WARNING_OUTPUT $warning;
  }
  close WARNING_OUTPUT;

  if (%counters) {
    my $continue='';
    print COUNTER_SUMMARY "{\n";
    for my $code (sort keys %counters) {
      print COUNTER_SUMMARY qq<$continue"$code": $counters{$code}\n>;
      $continue=',';
    }
    print COUNTER_SUMMARY "}\n";
  }
  close COUNTER_SUMMARY;

  # group related words
  for my $char (sort keys %letter_map) {
    for my $plural_key (sort keys(%{$letter_map{$char}})) {
      my $key = $plural_key;
      if ($key =~ /.s$/) {
        if ($key =~ /ies$/) {
          $key =~ s/ies$/y/;
        } else {
          $key =~ s/s$//;
        }
      } elsif ($key =~ /.[^aeiou]ed$/) {
        $key =~ s/ed$//;
      } else {
        next;
      }
      next unless defined $letter_map{$char}{$key};
      my %word_map = %{$letter_map{$char}{$key}};
      for $word (keys(%{$letter_map{$char}{$plural_key}})) {
        $word_map{$word} = 1;
      }
      $letter_map{$char}{$key} = \%word_map;
      delete $letter_map{$char}{$plural_key};
    }
  }

  # display the current unknown
  for my $char (sort keys %letter_map) {
    for $key (sort keys(%{$letter_map{$char}})) {
      my %word_map = %{$letter_map{$char}{$key}};
      my @words = keys(%word_map);
      if (scalar(@words) > 1) {
        print $key." (".(join ", ", sort { length($a) <=> length($b) || $a cmp $b } @words).")";
      } else {
        print $words[0];
      }
      print "\n";
    }
  }
}

1;
