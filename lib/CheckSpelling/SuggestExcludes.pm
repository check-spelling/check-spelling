#! -*-perl-*-

package CheckSpelling::SuggestExcludes;

use 5.022;
use feature 'unicode_strings';
use CheckSpelling::Util;

my (%extensions, %files, %directories, %rooted_paths, %tailed_paths);
my @patterns;
my @not_hit_patterns;

sub get_extension {
  my ($path) = @_;
  $path =~ s!.*/!!;
  return '' unless $path =~ s/.+\././;
  return $path;
}

sub path_to_pattern {
  my ($path) = @_;
  $path =~ s/^/^\\Q/;
  $path =~ s/$/\\E\$/;
  return $path;
}

sub process_path {
  my ($path) = @_;
  our $baseline;
  my $extension = get_extension($_);
  ++$baseline->{'extensions'}{$extension} if $extension ne '';
  my @directories = split m{/}, $_;
  my $file = pop @directories;
  ++$baseline->{'files'}{$file};
  return unless @directories;
  my @path_elements;
  for my $directory (@directories) {
    ++$baseline->{'directories'}{$directory};
    push @path_elements, $directory;
    ++$baseline->{'rooted_paths'}{join '/', @path_elements};
  }
  shift @path_elements;
  while (@path_elements) {
    ++$baseline->{'tailed_paths'}{join '/', @path_elements};
    shift @path_elements;
  }
}

sub quote_regex {
  my ($pattern) = @_;
  $pattern =~ s/([\\\[{(.?+*])/\\$1/g;
  return $pattern;
}

sub maybe_quote_regex {
  my ($i) = @_;
  return ($i eq quote_regex($i)) ? $i : "\\Q$i\\E";
}

sub build_patterns {
  my ($template, $key, $use_threshold, $suggest_threshold) = @_;
  our ($baseline, $totals);
  return unless defined $baseline->{$key} && defined $totals->{$key};
  my %hash_baseline = %{$baseline->{$key}};
  my %hash_totals = %{$totals->{$key}};
  our @patterns;
  my @results;
  my $joined_patterns = '\$^';
  for my $i (keys %hash_baseline) {
    next if $i =~ /$joined_patterns/;
    my ($hits, $total) = ($hash_baseline{$i}, $hash_totals{$i});
    next if $hits == 1 || $total == 0;
    my $ratio = $hits / $total;
    next if $ratio < $suggest_threshold;
    my $entry = $template;
    my $value = maybe_quote_regex($i);
    $entry =~ s/\n/$value/;
    if ($ratio == 1) {
      push @results, $value;
      $joined_patterns .= '|'.quote_regex($i);
    } elsif ($ratio < 1) {
      my $decimal = sprintf("%.2f", $ratio * 100);
      $entry = "(?:|\$^ $decimal\% - excluded $hits/$total)$entry";
      if ($ratio >= $use_threshold) {
        push @results, $value;
        $joined_patterns .= '|'.quote_regex($i);
      } else {
        $entry = "#$entry";
      }
    }
    push @patterns, $entry;
  }
  return @results;
}

sub set_up_counters {
  my ($ref) = @_;
  for my $key (qw(extensions files directories rooted_paths tailed_paths)) {
    $ref->{$key} = ();
  }
}

sub score_patterns {
  # Each pattern is recorded as ($data):
  #   hit count (number)
  #   pattern (string for regex)
  #   files covered (array of string)
  #
  # %scores is a map from a hit count to an array of $data
  #
  my @excluded = @_;
  our @patterns;
  my %scores;
  for my $pattern (@patterns) {
    my @hits;
    $pattern =~ s/\\Q(.*?)\\E/quote_regex($1)/eg;
    for my $path (@excluded) {
      if ($path =~ /$pattern/) {
        push @hits, $path;
      }
    }
    my $hit_count = scalar @hits;
    # naive data structure
    my @data = ($hit_count, $pattern, \@hits);
    my @entries = defined $scores{$hit_count} ? @{$scores{$hit_count}} : ();
    push @entries, \@data;
    $scores{$hit_count} = \@entries;
  }
  if (defined $scores{0}) {
    our @not_hit_patterns = map { $_[0] } (@{$scores{0}})
  }
  my %generally_covered_paths;
  my @selected_patterns;
  while (%scores) {
    my @ordered_scores = (sort { $b <=> $a } keys %scores);
    my $top_score = shift @ordered_scores;
    my @top_scoring = (sort { length($a->[1]) <=> length($b->[1])} @{$scores{$top_score}});

    my $selected_pattern = pop @top_scoring;
    if (@top_scoring) {
      $scores{$top_score} = \@top_scoring;
    } else {
      delete $scores{$top_score};
    }
    my $current_hit_count = $top_score;
    my @remaining_paths;
    if (%generally_covered_paths) {
      for my $path (@{$selected_pattern->[2]}) {
        if (defined $generally_covered_paths{$path}) {
          --$current_hit_count;
        } else {
          push @remaining_paths, $path;
        }
      }
      $selected_pattern->[0] = $current_hit_count;
      $selected_pattern->[2] = \@remaining_paths;
    } else {
      @remaining_paths = @{$selected_pattern->[2]};
    }
    next unless $current_hit_count;
    if ($current_hit_count == $top_score ||
        (!@top_scoring &&
         (!@ordered_scores ||
          ($current_hit_count > @{$scores{$ordered_scores[0]}[0]})[0]))) {
      push @selected_patterns, $selected_pattern->[1];
      for my $path (@remaining_paths) {
        $generally_covered_paths{$path} = 1;
      }
    } else {
      # we're not the best, so we'll move our object to where it should be now and revisit it later
      unless (defined $scores{$current_hit_count}) {
        $scores{$current_hit_count} = [];
      }
      push @{$scores{$current_hit_count}}, $selected_pattern;
    }
  }

  return @selected_patterns;
}

sub main {
  my ($file_list, $should_exclude_file, $current_exclude_patterns) = @_;
  open FILES, '<', $file_list;
  our @patterns = ();
  our $baseline = {};
  set_up_counters($baseline);
  my (%paths, @excluded);
  {
    local $/ = "\0";
    while (<FILES>) {
      chomp;
      $paths{$_} = 1;
      process_path $_;
    }
    close FILES;
  }
  our $totals = $baseline;
  $baseline = {};
  set_up_counters($baseline);

  open EXCLUDES, '<', $should_exclude_file;
  while (<EXCLUDES>) {
    chomp;
    push @excluded, $_;
    process_path $_;
  }
  close EXCLUDES;

  my @current_patterns;
  open CURRENT_EXCLUDES, '<', $current_exclude_patterns;
  while (<CURRENT_EXCLUDES>) {
    chomp;
    next unless /./;
    next if /^#/;
    push @current_patterns, $_;
  }
  close CURRENT_EXCLUDES;

  build_patterns("[^/]\n\$", 'extensions', .87, .81);
  build_patterns("(?:^|/)\n\$", 'files', .87, .81);
  build_patterns("^\n/", 'rooted_paths', .87, .81);
  build_patterns("/\n/[^/]+\$", 'tailed_paths', .87, .81);

  push (@patterns, @current_patterns);
  @patterns = score_patterns(@excluded);
  my @drop_patterns;
  if (@current_patterns) {
    my %positive_patterns = map { $_ => 1 } @patterns;
    our @not_hit_patterns;
    my %zero_patterns = map { $_ => 1 } @not_hit_patterns;
    for my $pattern (@current_patterns) {
      push @drop_patterns, $pattern unless defined $positive_patterns{$pattern} || defined $zero_patterns{$pattern};
    }
  }

  my $test = '(?:'.join('|', @patterns).')' if @patterns;
  for my $file (@excluded) {
    next if $test && $file =~ /$test/;
    push @patterns, '^'.maybe_quote_regex($file).'$';
  }

  @patterns = sort CheckSpelling::Util::case_biased @patterns;
  return (\@patterns, \@drop_patterns);
}

1;
