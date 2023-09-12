#!/usr/bin/env perl

use CheckSpelling::Util;
use CheckSpelling::Yaml;

my ($file, $path) = @ARGV;
exit unless $file && $path;
print CheckSpelling::Yaml::get_yaml_value(
  $file,
  $path
);
