#!/usr/bin/env perl
use 5.022;
use CheckSpelling::LoadEnv;

binmode STDOUT, ':utf8';

my $load_config_from_key = 'load-config-from';
my $parsed_inputs = CheckSpelling::LoadEnv::parse_inputs($load_config_from_key);

my $event_name = $ENV{GITHUB_EVENT_NAME};

if ($event_name eq 'pull_request_target') {
    CheckSpelling::LoadEnv::load_untrusted_config($parsed_inputs, $event_name);
} else {
    CheckSpelling::LoadEnv::load_trusted_config($parsed_inputs);
}

my %inputs = %{$parsed_inputs->{'inputs'}};
for my $var (sort keys %inputs) {
    CheckSpelling::LoadEnv::print_var_val($var, $inputs{$var});
}
