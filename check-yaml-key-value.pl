#!/usr/bin/env perl

use CheckSpelling::Util;
use CheckSpelling::Yaml;

my $key = CheckSpelling::Util::get_file_from_env('KEY', undef);
my $value = CheckSpelling::Util::get_file_from_env('VALUE', undef);
my $message = CheckSpelling::Util::get_file_from_env('MESSAGE', '');
my $report_match = CheckSpelling::Util::get_file_from_env('REPORT_MATCHING_YAML', '');
exit unless $key && $value;
CheckSpelling::Yaml::check_yaml_key_value(
  quotemeta($key),
  quotemeta($value),
  $message,
  $report_match,
);
