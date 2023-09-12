#!/usr/bin/env perl

use CheckSpelling::Util;
use CheckSpelling::Yaml;

my $key = CheckSpelling::Util::get_file_from_env('KEY', undef);
my $value = CheckSpelling::Util::get_file_from_env('VALUE', undef);
my $message = CheckSpelling::Util::get_file_from_env('MESSAGE', '');
exit unless $key && $value;
CheckSpelling::Yaml::check_yaml_key_value(
  quotemeta($key),
  quotemeta($value),
  $message
);
