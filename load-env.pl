#!/usr/bin/env perl
use JSON::PP;
my $input = $ENV{INPUTS};
my %inputs = %{decode_json $input};
for my $key (keys %inputs) {
    next unless $key;
    my $val = $inputs{$key};
    next unless $val;
    my $var = $key;
    next if $var =~ /[-\s]/;
    $val =~ s/([\$'])/\\$1/g;
    $var = uc $var;
    print qq<export INPUT_$var='$val';\n>;
}
