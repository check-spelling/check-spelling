#! -*-perl-*-

package CheckSpelling::SpellingCollator;

our $VERSION='0.1.0';
use 5.022;
use utf8;
use feature 'unicode_strings';
use warnings;
use File::Path qw(remove_tree);
use CheckSpelling::Util;

my %letter_map;
my $disable_word_collating;
my $shortest_word;

my %last_seen;

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
  $item =~ s/’/'/g;
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

sub should_skip_warning {
  my ($warning) = @_;
  if ($warning =~ /\(([-\w]+)\)$/) {
    my ($code) = ($1);
    return 1 if CheckSpelling::Util::is_ignoring_event($code);
  }
  return 0;
}

sub should_skip_warning_while_counting {
  my ($warning) = @_;
  return 0 unless ($warning =~ /\(([-\w]+)\)$/);
  my ($code) = ($1);
  return 1 if CheckSpelling::Util::is_ignoring_event($code);

  our %counters;
  ++$counters{$code};
  return 0;
}

sub log_skip_item {
  my ($item, $file, $warning, $unknown_word_limit) = @_;
  return 1 if should_skip_warning $warning;
  return 1 if skip_item($item);
  our %seen;
  my $seen_count = $seen{$item};
  if (defined $seen_count) {
    if (!defined $unknown_word_limit || ($seen_count++ < $unknown_word_limit)) {
      print MORE_WARNINGS "$file$warning\n";
    } else {
      our %last_seen;
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
  our $shortest_word;
  $shortest_word = 2 unless defined $shortest_word;
  my $key_length = length $key;

  if ($key =~ /.s$/) {
    if ($key_length > ($shortest_word + 1) && $key =~ /ies$/) {
      $key =~ s/ies$/y/;
    } elsif ($key_length > $shortest_word && $key !~ /ies$/) {
      $key =~ s/s$//;
    }
  } elsif ($key_length > ($shortest_word + 1) && $key =~ /.[^aeiou]ed$/) {
    $key =~ s/ed$//;
  }
  return $key;
}

sub collate_key {
  my ($key) = @_;
  our $disable_word_collating;
  my $char;
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
    while (my $word = <EXPECT>) {
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
  return if $disable_word_collating;

  # group related words
  for my $char (sort CheckSpelling::Util::number_biased keys %letter_map) {
    for my $plural_key (sort keys(%{$letter_map{$char}})) {
      my $key = stem_word $plural_key;
      next if $key eq $plural_key;
      next unless defined $letter_map{$char}{$key};
      my %word_map = %{$letter_map{$char}{$key}};
      for my $word (keys(%{$letter_map{$char}{$plural_key}})) {
        $word_map{$word} = 1;
      }
      $letter_map{$char}{$key} = \%word_map;
      delete $letter_map{$char}{$plural_key};
    }
  }
}

sub count_warning {
  my ($warning) = @_;
  our %counters;
  if ($warning =~ /\(([-\w]+)\)$/) {
    my ($code) = ($1);
    return if CheckSpelling::Util::is_ignoring_event($code);
    ++$counters{$code};
    return $code;
  }
}

sub report_timing {
  my ($name, $start_time, $directory, $marker) = @_;
  my $end_time = (stat "$directory/$marker")[9];
  $name =~ s/"/\\"/g;
  print TIMING_REPORT "\"$name\", $start_time, $end_time\n";
}

sub get_pattern_with_context {
  my ($path) = @_;
  return unless defined $ENV{$path};
  $ENV{$path} =~ /(.*)/;
  return unless open ITEMS, '<:utf8', $1;

  my @items;
  my $context = '';
  while (<ITEMS>) {
    my $pattern = $_;
    if ($pattern =~ /^#/) {
      if ($pattern =~ /^# /) {
        $context .= $pattern;
      } else {
        $context = '';
      }
      next;
    }
    chomp $pattern;
    unless ($pattern =~ /./) {
      $context = '';
      next;
    }
    push @items, $context.$pattern;
    $context = '';
  }
  close ITEMS;
  return @items;
}

sub summarize_totals {
  my ($formatter, $path, $items, $totals, $file_counts) = @_;
  return unless @{$totals};
  return unless open my $fh, '>:utf8', $path;
  my $totals_count = scalar(@{$totals}) - 1;
  my @indices;
  if ($file_counts) {
    @indices = sort {
      $totals->[$b] <=> $totals->[$a] ||
      $file_counts->[$b] <=> $file_counts->[$a]
    } 0 .. $totals_count;
  } else {
    @indices = sort {
      $totals->[$b] <=> $totals->[$a]
    } 0 .. $totals_count;
  }
  for my $i (@indices) {
    last unless $totals->[$i] > 0;
    my $rule_with_context = $items->[$i];
    my ($description, $rule);
    if ($rule_with_context =~ /^(.*\n)([^\n]+)$/s) {
      ($description, $rule) = ($1, $2);
    } else {
      ($description, $rule) = ('', $rule_with_context);
    }
    print $fh $formatter->(
      $totals->[$i],
      ($file_counts ? " file-count: $file_counts->[$i]" : ""),
      $description,
      $rule
    );
  }
  close $fh;
}

sub get_special {
  my ($file, $special) = @_;
  return 'file-list' if $file eq $special->{'file_list'};
  return 'pr-title' if $file eq $special->{'pr_title_file'};
  return 'pr-description' if $file eq $special->{'pr_description_file'};
  return 'commit-message' if !rindex($file, $special->{'commit_messages'});
  return 'file';
}

sub main {
  my @directories;
  my @cleanup_directories;
  my @check_file_paths;

  CheckSpelling::Util::build_ignored_event_map();
  my $early_warnings = CheckSpelling::Util::get_file_from_env('early_warnings', '/dev/null');
  my $warning_output = CheckSpelling::Util::get_file_from_env('warning_output', '/dev/stderr');
  my $more_warnings = CheckSpelling::Util::get_file_from_env('more_warnings', '/dev/stderr');
  my $counter_summary = CheckSpelling::Util::get_file_from_env('counter_summary', '/dev/stderr');
  my $should_exclude_file = CheckSpelling::Util::get_file_from_env('should_exclude_file', '/dev/null');
  my $unknown_word_limit = CheckSpelling::Util::get_val_from_env('unknown_word_limit', undef);
  my $unknown_file_word_limit = CheckSpelling::Util::get_val_from_env('unknown_file_word_limit', undef);
  my $candidate_example_limit = CheckSpelling::Util::get_file_from_env('INPUT_CANDIDATE_EXAMPLE_LIMIT', '3');
  my $disable_flags = CheckSpelling::Util::get_file_from_env('INPUT_DISABLE_CHECKS', '');
  my $only_check_changed_files = CheckSpelling::Util::get_file_from_env('INPUT_ONLY_CHECK_CHANGED_FILES', '');
  my $disable_noisy_file = $disable_flags =~ /(?:^|,|\s)noisy-file(?:,|\s|$)/;
  our $disable_word_collating = $only_check_changed_files || $disable_flags =~ /(?:^|,|\s)word-collating(?:,|\s|$)/;
  our $shortest_word = CheckSpelling::Util::get_val_from_env('INPUT_SHORTEST_WORD', undef);
  my $file_list = CheckSpelling::Util::get_file_from_env('check_file_names', '');
  my $pr_title_file = CheckSpelling::Util::get_file_from_env('pr_title_file', '');
  my $pr_description_file = CheckSpelling::Util::get_file_from_env('pr_description_file', '');
  my $commit_messages = CheckSpelling::Util::get_file_from_env('commit_messages', '');
  my $timing_report = CheckSpelling::Util::get_file_from_env('timing_report', '');
  my $special = {
    'file_list' => $file_list,
    'pr_title_file' => $pr_title_file,
    'pr_description_file' => $pr_description_file,
    'commit_messages' => $commit_messages,
  };
  my ($start_time, $end_time);

  open WARNING_OUTPUT, '>:utf8', $warning_output;
  open MORE_WARNINGS, '>:utf8', $more_warnings;
  open COUNTER_SUMMARY, '>:utf8', $counter_summary;
  open SHOULD_EXCLUDE, '>:utf8', $should_exclude_file;
  if ($timing_report) {
    open TIMING_REPORT, '>:utf8', $timing_report;
    print TIMING_REPORT "file, start, finish\n";
  }

  my @candidates = get_pattern_with_context('candidates_path');
  my @candidate_totals = (0) x scalar @candidates;
  my @candidate_file_counts = (0) x scalar @candidates;

  my @forbidden = get_pattern_with_context('forbidden_path');
  my @forbidden_totals = (0) x scalar @forbidden;

  my @delayed_warnings;
  our %letter_map = ();

  my %file_map = ();

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

    $file_map{$file} = $directory;
  }

  for my $file (sort keys %file_map) {
    my $directory = $file_map{$file};
    if ($timing_report) {
      $start_time = (stat "$directory/name")[9];
    }

    if (-e "$directory/skipped") {
      open SKIPPED, '<:utf8', "$directory/skipped";
      my $reason=<SKIPPED>;
      close SKIPPED;
      chomp $reason;
      push @delayed_warnings, "$file:1:1 ... 1, Warning - Skipping `$file` because $reason\n";
      print SHOULD_EXCLUDE "$file\n";
      push @cleanup_directories, $directory;
      report_timing($file, $start_time, $directory, 'skipped') if ($timing_report);
      next;
    }

    # stats isn't written if there was nothing interesting in the file
    unless (-s "$directory/stats") {
      report_timing($file, $start_time, $directory, 'warnings') if ($timing_report);
      push @directories, $directory;
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
                my $wrapped = CheckSpelling::Util::truncate_with_ellipsis(CheckSpelling::Util::wrap_in_backticks($pattern), 99);
                my $candidate_label = '';
                if ($candidates[$i] =~ /^#\s+(\S.+)/) {
                  $candidate_label = " ($1)";
                }
                push @delayed_warnings, "$file:$position, Notice - Line matches candidate pattern$candidate_label $wrapped (candidate-pattern)\n";
              }
            }
          }
        }
      }
      if (@forbidden_totals) {
        my @forbidden_list=get_array($stats, 'forbidden');
        my @lines=get_array($stats, 'forbidden_lines');
        if (@forbidden_list) {
          for (my $i=0; $i < scalar @forbidden_list; $i++) {
            my $hits = $forbidden_list[$i];
            if ($hits) {
              $forbidden_totals[$i] += $hits;
            }
          }
        }
      }
      #print STDERR "$file (unrecognized: $unrecognized; unique: $unique; unknown: $unknown, words: $words, candidates: [".join(", ", @candidate_list)."])\n";
    }

    report_timing($file, $start_time, $directory, 'unknown') if ($timing_report);
    my $kind = get_special($file, $special);
    # These heuristics are very new and need tuning/feedback
    if (
        ($unknown > $unique)
        # || ($unrecognized > $words / 2)
    ) {
      unless ($disable_noisy_file) {
        if ($kind eq 'file') {
          print SHOULD_EXCLUDE "$file\n";
        }
        my $warning = "noisy-$kind";
        count_warning $warning;
        push @delayed_warnings, "$file:1:1 ... 1, Warning - Skipping `$file` because it seems to have more noise ($unknown) than unique words ($unique) (total: $unrecognized / $words). ($warning)\n";
        push @cleanup_directories, $directory;
        next;
      }
    }
    push @directories, $directory;
    unless ($kind =~ /^file/ && -s "$directory/unknown") {
      next;
    }
    open UNKNOWN, '<:utf8', "$directory/unknown";
    for my $token (<UNKNOWN>) {
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
  }
  close SHOULD_EXCLUDE;
  close TIMING_REPORT if $timing_report;

  summarize_totals(
    sub {
      my ($hits, $files, $context, $pattern) = @_;
      return "# hit-count: $hits$files\n$context$pattern\n\n",
    },
    CheckSpelling::Util::get_file_from_env('candidate_summary', '/dev/stderr'),
    \@candidates,
    \@candidate_totals,
    \@candidate_file_counts,
  );

  summarize_totals(
    sub {
      my (undef, undef, $context, $pattern) = @_;
      $context =~ s/^# //gm;
      chomp $context;
      my $details;
      if ($context =~ /^(.*?)$(.*)/ms) {
        ($context, $details) = ($1, $2);
        $details = "\n$details" if $details;
      }
      $context = 'Pattern' unless $context;
      return "##### $context$details\n```\n$pattern\n```\n\n";
    },
    CheckSpelling::Util::get_file_from_env('forbidden_summary', '/dev/stderr'),
    \@forbidden,
    \@forbidden_totals,
  );

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
      next if should_skip_warning_while_counting $warning;
      print WARNING_OUTPUT "$warning\n";
    }
    close WARNINGS;
  }

  our %last_seen;
  my %unknown_file_word_count;
  for my $directory (@directories) {
    next unless (-s "$directory/warnings");
    next unless open(NAME, '<:utf8', "$directory/name");
    my $file=<NAME>;
    close NAME;
    my $kind = get_special($file, $special);
    open WARNINGS, '<:utf8', "$directory/warnings";
    if ($kind ne 'file-list') {
      for my $warning (<WARNINGS>) {
        my $code;
        chomp $warning;
        if ($warning =~ m/:(\d+):(\d+ \.\.\. \d+): `(.*)`/) {
          my ($line, $range, $item) = ($1, $2, $3);
          my $wrapped = CheckSpelling::Util::wrap_in_backticks($item);
          my $reason = 'unrecognized-spelling';
          $reason .= "-$kind" unless $kind eq 'file';
          $warning =~ s/:\d+:\d+ \.\.\. \d+: `.*`/:$line:$range, Warning - $wrapped is not a recognized word ($reason)/;
          next if log_skip_item($item, $file, $warning, $unknown_word_limit);
          count_warning $warning if $kind ne 'file';
          $code = $reason;
        } else {
          if ($warning =~ /\`(.*?)\` in line \(token-is-substring\)/) {
            next if skip_item($1);
          }
          $code = count_warning $warning;
        }
        next if should_skip_warning $warning, $code;
        print WARNING_OUTPUT "$file$warning\n";
      }
    } else {
      for my $warning (<WARNINGS>) {
        chomp $warning;
        next unless $warning =~ s/^:(\d+)/:1/;
        $file = $check_file_paths[$1];
        if ($warning =~ m/:(\d+ \.\.\. \d+): `(.*)`/) {
          my ($range, $item) = ($1, $2);
          my $wrapped = CheckSpelling::Util::wrap_in_backticks($item);
          $warning =~ s/:\d+ \.\.\. \d+: `.*`/:$range, Warning - $wrapped is not a recognized word (check-file-path)/;
          next if skip_item($item);
          if (defined $unknown_file_word_limit) {
            next if ++$unknown_file_word_count{$item} > $unknown_file_word_limit;
          }
        }
        next if should_skip_warning_while_counting $warning;
        print WARNING_OUTPUT "$file$warning\n";
      }
    }
    close WARNINGS;
  }
  close MORE_WARNINGS;

  for my $warning (@delayed_warnings) {
    next if should_skip_warning_while_counting $warning;
    print WARNING_OUTPUT $warning;
  }
  if (defined $unknown_word_limit) {
    for my $warned_word (sort keys %last_seen) {
      my $warning_count = $seen{$warned_word} || 0;
      next unless $warning_count >= $unknown_word_limit;
      my $warning = $last_seen{$warned_word};
      $warning =~ s/\Q (unrecognized-spelling)\E/ -- found $warning_count times (limited-references)\n/;
      next if should_skip_warning_while_counting $warning;
      print WARNING_OUTPUT $warning;
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
    for my $key (sort CheckSpelling::Util::case_biased keys(%{$letter_map{$char}})) {
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

sub collate_expect {
  my ($collated, $notes) = @_;
  my %word_map;
  my %has_canonical;
  open EXPECT, '<', $collated;
  while (<EXPECT>) {
    chomp;
    next unless /(.*) \((.*)\)/;
    my ($key, $list) = ($1, $2);
    for my $variant (split /, /, $list) {
      if ($variant eq $key) {
        $has_canonical{$key} = 1;
      } else {
        $word_map{$variant} = $key;
      }
    }
  }
  close EXPECT;
  my $pattern = '`('.join('|', map { quotemeta($_) } keys %word_map).')`';
  open SOURCES, '<', $notes;
  while (<SOURCES>) {
    if ($_ =~ /$pattern/) {
      my $match = $1;
      my $canonical_match = $word_map{$match};
      my $print = 0;
      my $wrapped = CheckSpelling::Util::wrap_in_backticks($canonical_match);
      if (defined $has_canonical{$canonical_match}) {
        $print = 1 if s/not a recognized word/ignored because another more general variant ($wrapped) is also in expect/;
        $print = 1 if s/unrecognized-spelling/ignored-expect-variant/;
      } else {
        $print = 1 if s/is not a recognized word/should be replaced by the more general variant ($wrapped)/;
        $print = 1 if s/unrecognized-spelling/update-expect-variant/;
      }
      next unless $print;
    } else {
      next unless /\(((?:\w+-)+\w+)\)$/;
      next if $1 eq 'unrecognized-spelling';
    }
    print;
  }
  close SOURCES;
  return 0;
}

1;
