#! -*-perl-*-

package CheckSpelling::SpellingCollator;

our $VERSION='0.1.0';
use warnings;
use File::Path qw(remove_tree);
use CheckSpelling::Util;

my %letter_map;
my $disable_word_collating;

sub get_field {
  my ($record, $field) = @_;
  return 0 unless $record =~ (/\b$field:\s*(\d+)/);
  return $1;
}

sub get_array {
  my ($record, $field) = @_;
  return () unless $record =~ (/\b$field: \[([^\]]+)\]/);
  my $values = $1;
  return split /\s*,\s*/, $values;
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

sub log_skip_item {
  my ($item, $file, $warning, $unknown_word_limit) = @_;
  return 1 if skip_item($item);
  my $seen_count = $seen{$item};
  if (defined $seen_count) {
    if (!defined $unknown_word_limit || ($seen_count++ < $unknown_word_limit)) {
      print MORE_WARNINGS "$file$warning\n"
    } else {
      $last_seen{$item} = "$file$warning";
    }
    $seen{$item} = $seen_count;
    return 1;
  }
  $seen{$item} = 1;
  return 0;
}

sub stem_word {
  my ($key) = @_;
  our $disable_word_collating;
  return $key if $disable_word_collating;

  if ($key =~ /.s$/) {
    if ($key =~ /ies$/) {
      $key =~ s/ies$/y/;
    } else {
      $key =~ s/s$//;
    }
  } elsif ($key =~ /.[^aeiou]ed$/) {
    $key =~ s/ed$//;
  }
  return $key;
}

sub collate_key {
  my ($key) = @_;
  our $disable_word_collating;
  if ($disable_word_collating) {
    $char = lc substr $key, 0, 1;
  } else {
    $key = lc $key;
    $key =~ s/''+/'/g;
    $key =~ s/'[sd]$//;
    $key =~ s/^[^Ii]?'+(.*)/$1/;
    $key =~ s/(.*?)'$/$1/;
    $char = substr $key, 0, 1;
  }
  return ($key, $char);
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

sub harmonize_expect {
  our $disable_word_collating;
  our %letter_map;
  our %expected;

  for my $word (keys %expected) {
    my ($key, $char) = collate_key $word;
    my %word_map = ();
    next unless defined $letter_map{$char}{$key};
    %word_map = %{$letter_map{$char}{$key}};
    next if defined $word_map{$word};
    my $words = scalar keys %word_map;
    next if $words > 2;
    if ($word eq $key) {
      next if ($words > 1);
    }
    delete $expected{$word};
  }
}

sub group_related_words {
  our %letter_map;
  our $disable_word_collating;
  unless ($disable_word_collating) {
    # group related words
    for my $char (sort keys %letter_map) {
      for my $plural_key (sort keys(%{$letter_map{$char}})) {
        my $key = stem_word $plural_key;
        next if $key eq $plural_key;
        next unless defined $letter_map{$char}{$key};
        my %word_map = %{$letter_map{$char}{$key}};
        for $word (keys(%{$letter_map{$char}{$plural_key}})) {
          $word_map{$word} = 1;
        }
        $letter_map{$char}{$key} = \%word_map;
        delete $letter_map{$char}{$plural_key};
      }
    }
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

sub report_timing {
  my ($name, $start_time, $directory, $marker) = @_;
  my $end_time = (stat "$directory/$marker")[9];
  $name =~ s/"/\\"/g;
  print TIMING_REPORT "\"$name\", $start_time, $end_time\n";
}

sub main {
  my @directories;
  my @cleanup_directories;
  my @check_file_paths;

  my $early_warnings = CheckSpelling::Util::get_file_from_env('early_warnings', '/dev/null');
  my $warning_output = CheckSpelling::Util::get_file_from_env('warning_output', '/dev/stderr');
  my $more_warnings = CheckSpelling::Util::get_file_from_env('more_warnings', '/dev/stderr');
  my $counter_summary = CheckSpelling::Util::get_file_from_env('counter_summary', '/dev/stderr');
  my $should_exclude_file = CheckSpelling::Util::get_file_from_env('should_exclude_file', '/dev/null');
  my $unknown_word_limit = CheckSpelling::Util::get_val_from_env('unknown_word_limit', undef);
  my $candidate_summary = CheckSpelling::Util::get_file_from_env('candidate_summary', '/dev/stderr');
  my $candidate_example_limit = CheckSpelling::Util::get_file_from_env('INPUT_CANDIDATE_EXAMPLE_LIMIT', '3');
  my $disable_flags = CheckSpelling::Util::get_file_from_env('INPUT_DISABLE_CHECKS', '');
  my $disable_noisy_file = $disable_flags =~ /(?:^|,|\s)noisy-file(?:,|\s|$)/;
  our $disable_word_collating = $disable_flags =~ /(?:^|,|\s)word-collating(?:,|\s|$)/;
  my $file_list = CheckSpelling::Util::get_file_from_env('check_file_names', '');
  my $timing_report = CheckSpelling::Util::get_file_from_env('timing_report', '');
  my ($start_time, $end_time);

  open WARNING_OUTPUT, '>:utf8', $warning_output;
  open MORE_WARNINGS, '>:utf8', $more_warnings;
  open COUNTER_SUMMARY, '>:utf8', $counter_summary;
  open SHOULD_EXCLUDE, '>:utf8', $should_exclude_file;
  open CANDIDATE_SUMMARY, '>:utf8', $candidate_summary;
  if ($timing_report) {
    open TIMING_REPORT, '>:utf8', $timing_report;
    print TIMING_REPORT "file, start, finish\n";
  }

  my @candidates;
  if (defined $ENV{'candidates_path'}) {
    $ENV{'candidates_path'} =~ /(.*)/;
    if (open CANDIDATES, '<:utf8', $1) {
      my $candidate_context = '';
      while (<CANDIDATES>) {
        my $candidate = $_;
        if ($candidate =~ /^#/) {
          $candidate_context .= $candidate;
          next;
        }
        chomp $candidate;
        unless ($candidate =~ /./) {
          $candidate_context = '';
          next;
        }
        push @candidates, $candidate_context.$candidate;
        $candidate_context = '';
      }
      close CANDIDATES;
    }
  }
  my @candidate_totals = (0) x scalar @candidates;
  my @candidate_file_counts = (0) x scalar @candidates;

  my @delayed_warnings;
  our %letter_map = ();

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
    if ($timing_report) {
      $start_time = (stat "$directory/name")[9];
    }

    if (-e "$directory/skipped") {
      open SKIPPED, '<:utf8', "$directory/skipped";
      my $reason=<SKIPPED>;
      close SKIPPED;
      chomp $reason;
      push @delayed_warnings, "$file:1:1 ... 1, Warning - Skipping `$file` because $reason\n";
      print SHOULD_EXCLUDE "$file\n" unless $file eq $file_list;
      push @cleanup_directories, $directory;
      report_timing($file, $start_time, $directory, 'skipped') if ($timing_report);
      next;
    }

    # stats isn't written if all words in the file are in the dictionary
    unless (-s "$directory/stats") {
      push @directories, $directory;
      report_timing($file, $start_time, $directory, 'warnings') if ($timing_report);
      next;
    }

    if ($file eq $file_list) {
      open FILE_LIST, '<:utf8', $file_list;
      push @check_file_paths, '0 placeholder';
      for my $check_file_path (<FILE_LIST>) {
        chomp $check_file_path;
        push @check_file_paths, $check_file_path;
      }
      close FILE_LIST;
    }

    my ($words, $unrecognized, $unknown, $unique);

    {
      open STATS, '<:utf8', "$directory/stats";
      my $stats=<STATS>;
      close STATS;
      $words=get_field($stats, 'words');
      $unrecognized=get_field($stats, 'unrecognized');
      $unknown=get_field($stats, 'unknown');
      $unique=get_field($stats, 'unique');
      my @candidate_list;
      if (@candidate_totals) {
        @candidate_list=get_array($stats, 'candidates');
        my @lines=get_array($stats, 'candidate_lines');
        if (@candidate_list) {
          for (my $i=0; $i < scalar @candidate_list; $i++) {
            my $hits = $candidate_list[$i];
            if ($hits) {
              $candidate_totals[$i] += $hits;
              if ($candidate_file_counts[$i]++ < $candidate_example_limit) {
                my $pattern = (split /\n/,$candidates[$i])[-1];
                my $position = $lines[$i];
                $position =~ s/:(\d+)$/ ... $1/;
                push @delayed_warnings, "$file:$position, Notice - `Line` matches candidate pattern `$pattern` (candidate-pattern)\n";
              }
            }
          }
        }
      }
      #print STDERR "$file (unrecognized: $unrecognized; unique: $unique; unknown: $unknown, words: $words, candidates: [".join(", ", @candidate_list)."])\n";
    }

    report_timing($file, $start_time, $directory, 'unknown') if ($timing_report);
    # These heuristics are very new and need tuning/feedback
    if (
        ($unknown > $unique)
        # || ($unrecognized > $words / 2)
    ) {
      unless ($disable_noisy_file) {
        if ($file eq $file_list) {
          push @delayed_warnings, "$file:1:1 ... 1, Warning - Skipping file names because there seems to be more noise ($unknown) than unique words ($unique) (total: $unrecognized / $words). (noisy-file-list)\n"
        } else {
          push @delayed_warnings, "$file:1:1 ... 1, Warning - Skipping `$file` because there seems to be more noise ($unknown) than unique words ($unique) (total: $unrecognized / $words). (noisy-file)\n";
          print SHOULD_EXCLUDE "$file\n";
        }
        push @directories, $directory;
        next;
      }
    }
    unless (-s "$directory/unknown") {
      push @directories, $directory;
      next;
    }
    open UNKNOWN, '<:utf8', "$directory/unknown";
    for $token (<UNKNOWN>) {
      $token =~ s/\R//;
      next unless $token =~ /./;
      my ($key, $char) = collate_key $token;
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
  close TIMING_REPORT if $timing_report;

  if (@candidate_totals) {
    my @indices = sort {
      $candidate_totals[$b] <=> $candidate_totals[$a] ||
      $candidate_file_counts[$b] <=> $candidate_file_counts[$a]
    } 0 .. $#candidate_totals;
    for my $i (@indices) {
      last unless $candidate_totals[$i] > 0;
      print CANDIDATE_SUMMARY "# hit-count: $candidate_totals[$i] file-count: $candidate_file_counts[$i]\n$candidates[$i]\n\n";
    }
  }
  close CANDIDATE_SUMMARY;

  group_related_words;

  if (defined $ENV{'expect'}) {
    $ENV{'expect'} =~ /(.*)/;
    load_expect $1;
    harmonize_expect;
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

  my %last_seen;
  for my $directory (@directories) {
    next unless (-s "$directory/warnings");
    next unless open(NAME, '<:utf8', "$directory/name");
    my $file=<NAME>;
    close NAME;
    my $is_file_list = $file eq $file_list;
    open WARNINGS, '<:utf8', "$directory/warnings";
    if (!$is_file_list) {
      for $warning (<WARNINGS>) {
        chomp $warning;
        if ($warning =~ s/:(\d+):(\d+ \.\.\. \d+): '(.*)'/:$1:$2, Warning - `$3` is not a recognized word\. \(unrecognized-spelling\)/) {
          my ($line, $range, $item) = ($1, $2, $3);
          next if log_skip_item($item, $file, $warning, $unknown_word_limit);
        } else {
          if ($warning =~ /\`(.*?)\` in line\. \(token-is-substring\)/) {
            next if skip_item($1);
          }
          count_warning $warning;
        }
        print WARNING_OUTPUT "$file$warning\n";
      }
    } else {
      for $warning (<WARNINGS>) {
        chomp $warning;
        next unless $warning =~ s/^:(\d+)/:1/;
        $file = $check_file_paths[$1];
        if ($warning =~ s/:(\d+ \.\.\. \d+): '(.*)'/:$1, Warning - `$2` is not a recognized word\. \(check-file-path\)/) {
          next if skip_item($2);
        }
        print WARNING_OUTPUT "$file$warning\n";
        count_warning $warning;
      }
    }
    close WARNINGS;
  }
  close MORE_WARNINGS;

  for my $warning (@delayed_warnings) {
    count_warning $warning;
    print WARNING_OUTPUT $warning;
  }
  if (defined $unknown_word_limit) {
    for my $warned_word (sort keys %last_seen) {
      my $warning_count = $seen{$warned_word};
      next unless $warning_count >= $unknown_word_limit;
      my $warning = $last_seen{$warned_word};
      $warning =~ s/\Q. (unrecognized-spelling)\E/ -- found $warning_count times. (limited-references)\n/;
      print WARNING_OUTPUT $warning;
      count_warning $warning;
    }
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

  # display the current unknown
  for my $char (sort keys %letter_map) {
    for $key (sort CheckSpelling::Util::case_biased keys(%{$letter_map{$char}})) {
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
