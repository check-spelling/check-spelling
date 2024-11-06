#!/usr/bin/env perl
use 5.022;
use feature 'unicode_strings';
use Encode qw/decode_utf8 FB_DEFAULT/;
use YAML::PP qw/Load/;
use JSON::PP;

binmode STDIN;
binmode STDOUT, ':utf8';

$/ = undef;
my $content = <>;
my $res = YAML::PP::Load($content);
print encode_json($res)
