#!/usr/bin/env perl
use JSON::PP;
my @expect_files = split /\n/, $ENV{expect_files};
my @excludes_files = split /\n/, $ENV{excludes_files};
my $new_expect_file = $ENV{new_expect_file};
my $excludes_file = $ENV{excludes_file};
my $spelling_config = $ENV{spelling_config};
$config{"excludes_file"} = $excludes_file;
$config{"new_expect_file"} = $new_expect_file;
$config{"spelling_config"} = $spelling_config;
$config{"expect_files"} = \@expect_files;
$config{"excludes_files"} = \@excludes_files;
print encode_json \%config;
