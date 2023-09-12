#!/usr/bin/env perl
use JSON::PP;
my $input = $ENV{INPUTS};
exit unless $input;
my %inputs = %{decode_json $input};
for my $key (keys %inputs) {
    next unless $key;
    my $val = $inputs{$key};
    next unless $val;
    my $var = $key;
    next if $var =~ /\s/;
    if ($var =~ /-/ && $inputs{$var} ne '') {
        my $var_pattern = $var;
        $var_pattern =~ s/-/[-_]/g;
        my @vars = grep { /^${var_pattern}$/ && ($var ne $_) && $inputs{$_} ne '' && $inputs{$var} ne $inputs{$_} } keys %inputs;
        print STDERR 'Found conflicting inputs for '.$var." ($inputs{$var}): ".join(', ', map { "$_ ($inputs{$_})" } @vars)." (migrate-underscores-to-dashes)\n" if (@vars);
        $var =~ s/-/_/g;
    }
    $val =~ s/([\$])/\\$1/g;
    $val =~ s/'/'"'"'/g;
    $var = uc $var;
    print qq<export INPUT_$var='$val';\n>;
}
