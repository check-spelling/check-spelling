#!/usr/bin/env -S perl -T -Ilib

use warnings;
use CheckSpelling::Util;
use CheckSpelling::Severities;

my ($warnings_file) = @ARGV;
$warnings_file =~ /(.*)/;
$warnings_file = $1;
my ($warnings_file_out) = "$warnings_file.out";

sub events_to_regular_expression {
  my ($events_list) = @_;
  my $events = join '|', @{$events_list};
  $events =~ s/[^-a-z]+/|/g;
  $events =~ s/^\||\|$//g;
  $events =~ s/^$/\$^/;
  return $events;
}

my $GITHUB_SERVER_URL = CheckSpelling::Util::get_file_from_env('GITHUB_SERVER_URL');
my $GITHUB_REPOSITORY = CheckSpelling::Util::get_file_from_env('GITHUB_REPOSITORY');
my $commit_messages = CheckSpelling::Util::get_file_from_env('commit_messages');
my $pr_details_path = CheckSpelling::Util::get_file_from_env('pr_details_path');
my $synthetic_base = CheckSpelling::Util::get_file_from_env('synthetic_base');
my $spellchecker = CheckSpelling::Util::get_file_from_env('spellchecker');
my $severity_level_file = CheckSpelling::Util::get_file_from_env('severity_level');
my $severity_list_file = CheckSpelling::Util::get_file_from_env('severity_list');
my $severities = CheckSpelling::Severities::get_severities("$spellchecker/sarif.json");

my $severity_map = 'silence-warning';
my %severity_map;

$severity_map{ignore} = [];
$severity_map{notice} = [];
$severity_map{warning} = [];
$severity_map{error} = [];


while (my($id, $s) = each %{$severities}) {
  my @list = @{$severity_map{$s}};
  push @list, $id;
  $severity_map{$s} = \@list;
}

while (my($s, $ids) = each %{$severity_map}) {
  my $pattern = events_to_regular_expression($ids);
  $severity_map{$s} = $pattern;
}

my $ignored_pattern = events_to_regular_expression($severity_map{ignore});
my $errors_pattern = events_to_regular_expression($severity_map{error});
my $notices_pattern = events_to_regular_expression($severity_map{notice});
my $warnings_pattern = events_to_regular_expression($severity_map{warning});

open my $severity_list, '>', $severity_list_file;
print $severity_list "
INPUT_IGNORED='$ignored_pattern'
INPUT_NOTICES='$notices_pattern'
INPUT_WARNINGS='$warnings_pattern'
INPUT_ERRORS='$errors_pattern'
";
close $severity_list;

my $warnings_in;
my $warnings_out;

open $warnings_in, '<', $warnings_file;
$warnings_file_out = "$warnings_file.tmp";
open $warnings_out, '>', $warnings_file_out;
my ($has_notice, $has_warning, $has_error) = (0, 0, 0);

while (<$warnings_in>) {
  if (defined $commit_messages) {
    s<^$commit_messages/([0-9a-f]+)\.message><$GITHUB_SERVER_URL/$GITHUB_REPOSITORY/commit/$1#>;
  }
  if (defined $pr_details_path) {
    s<^$synthetic_base/pull-request/(\d+)/(?:description|summary).txt><$GITHUB_SERVER_URL/$GITHUB_REPOSITORY/pull/$1#>;
  }
  if (/\((?:$ignored_pattern)\)$/) {
    $_ = "" if m{(^(?:.*?):(?:\d+):(?:\d+) \.\.\. (?:\d+),)\s(?:Error|Notice|Warning)(\s-\s.+\s\(.*\))};
  }
  if (/\((?:$errors_pattern)\)$/) {
    s{(^(?:.*?):(?:\d+):(?:\d+) \.\.\. (?:\d+),)\s(?:Notice|Warning)(\s-\s.+\s\(.*\))}{$1 Error$2};
    $has_error = 1;
  }
  if (/\((?:$notices_pattern)\)$/) {
    s{(^(?:.*?):(?:\d+):(?:\d+) \.\.\. (?:\d+),)\s(?:Error|Warning)(\s-\s.+\s\(.*\))}{$1 Notice$2};
    $has_notice = 1;
  }
  if (/\((?:$warnings_pattern)\)$/) {
    s{(^(?:.*?):(?:\d+):(?:\d+) \.\.\. (?:\d+),)\s(?:Error|Notice)(\s-\s.+\s\(.*\))}{$1 Warning$2};
    $has_warning = 1;
  }
  print $warnings_out $_;
}
close($warnings_in);
close($warnings_out);
rename($warnings_file_out, $warnings_file);
open my $severity_level, '>', $severity_level_file;
if ($has_error) {
  print $severity_level 'error';
} elsif ($has_warning) {
  print $severity_level 'warning';
} elsif ($has_notice) {
  print $severity_level 'notice';
}
close $severity_level;
