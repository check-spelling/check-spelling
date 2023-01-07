#!/usr/bin/env perl
use JSON::PP;

my $prefixes=$ENV{INPUT_DICTIONARY_SOURCE_PREFIXES};
my %prefix_map;
if ($prefixes) {
    %prefix_map=%{decode_json $prefixes};
}

my $dictionary_alias_pattern=$ENV{dictionary_alias_pattern};
$/=undef;
my $json=<>;
my $decoded=decode_json $json;
my @suggested_dictionaries=@{$decoded};
for my $suggested_dictionary_ref (@suggested_dictionaries) {
    my %suggested_dictionary = %{$suggested_dictionary_ref};
    for my $dict (keys %suggested_dictionary) {
        my $suggested_dictionary_ref = $suggested_dictionary{$dict};
        my @suggested_dictionary_array = @{$suggested_dictionary_ref};
        my ($covers, $total, $uniq) = @suggested_dictionary_array;
        my $url = $dict;
        for my $key (keys %prefix_map) {
            $url =~ s<$key:><$prefix_map{$key}>;
        }
        my $unique = '';
        if ($uniq) {
            $unique = " ($uniq uniquely)";
        }
        print "[$dict]($url) ($total) covers $covers of them$unique\n";
    }

}
