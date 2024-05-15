#!/usr/bin/env perl
use YAML::PP qw/Load/;
use JSON::PP;

$/ = undef;
my $content = <>;
my $res = YAML::PP::Load($content);
print encode_json($res)
