#!/usr/bin/env perl
use JSON::PP;
my $input = $ENV{INPUTS};
my %inputs;
if ($input) {
    %inputs = %{decode_json $input};
}

for my $key (keys %inputs) {
    next unless $key;
    my $val = $inputs{$key};
    next unless $val ne '';
    my $var = $key;
    if ($val =~ /^github_pat_/) {
        print STDERR "Censoring `$var` (unexpected-input-value)\n";
        next;
    }
    next if $var =~ /\s/;
    next if $var =~ /[-_](?:key|token)$/;
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

my $action_json_path = $ENV{action_yml_json};
exit unless defined $action_json_path && -f $action_json_path;
my $action_json;
open $action_json_file, '<', $action_json_path;
{
    local $/ = undef;
    $action_json = <$action_json_file>;
    close $action_json_file;
}
my %action = %{decode_json $action_json};
my %action_inputs = %{$action{inputs}};
for my $key (sort keys %action_inputs) {
    my %ref = %{$action_inputs{$key}};
    next unless defined $ref{default};
    next if defined $inputs{$key};
    my $var = $key;
    next if $var =~ /[-_](?:key|token)$/i;
    if ($var =~ s/-/_/g) {
        next if defined $inputs{$var};
    }
    my $val = $ref{default};
    next if $val eq '';
    $val =~ s/([\$])/\\$1/g;
    $val =~ s/'/'"'"'/g;
    $var = 'INPUT_'.(uc $var);
    next if defined $ENV{$var};
    print qq<export $var='$val';\n>;
}
