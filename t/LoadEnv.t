#!/usr/bin/env -S perl -w -Ilib

use strict;
use warnings;
use utf8;
use File::Temp qw/ tempfile tempdir /;
use Capture::Tiny ':all';

use Test::More;

plan tests => 79;
use_ok('CheckSpelling::LoadEnv');

{
    my ($k, $v) = CheckSpelling::LoadEnv::escape_var_val("test", "case");
    is($k, 'TEST', 'basic key');
    is($v, 'case', 'basic value');

    ($k, $v) = CheckSpelling::LoadEnv::escape_var_val("test-ing", q<ev"c$a's\\e
me>);
    is($k, 'TEST_ING', 'dashed key');
    is($v, q<ev"c\$a'"'"'s\e>."\n".'me', 'evil value');
}

my ($stdout, $stderr, @result) = capture {
    return CheckSpelling::LoadEnv::print_var_val('HELLO', 'world');
};
is($stdout, q<export INPUT_HELLO='world';
>, 'proper print_var_val out');
is($stderr, '', 'proper print_var_val err');
is(@result, 1, 'proper print_var_val result');

($stdout, $stderr, @result) = capture {
    return CheckSpelling::LoadEnv::print_var_val('hello', 'world');
};
is($stdout, '', 'improper print_var_val out');
is($stderr, "Found improperly folded key in inputs 'hello'\n", 'improper print_var_val err');
is(@result, 0, 'improper print_var_val result');

($stdout, $stderr, @result) = capture {
    return CheckSpelling::LoadEnv::print_var_val('HELLO', '');
};
is($stdout, '', 'empty print_var_val out');
is($stderr, '', 'empty print_var_val err');
is(@result, 0, 'empty print_var_val result');

($stdout, $stderr, @result) = capture {
    return CheckSpelling::LoadEnv::expect_array('', 'empty');
};
is($stdout, '', 'empty expect_array out');
is($stderr, '', 'empty expect_array err');
is(@{$result[0]}, 0, 'empty expect_array result');

($stdout, $stderr, @result) = capture {
    return CheckSpelling::LoadEnv::expect_array([1, 2], 'series');
};
is($stdout, '', 'expect_array out');
is($stderr, '', 'expect_array err');
is(join (',', @{$result[0]}), '1,2', 'expect_array result');

($stdout, $stderr, @result) = capture {
    return CheckSpelling::LoadEnv::expect_array(\'hello', 'world');
};
is($stdout, '', 'bad expect_array out');
is($stderr, q<'world' should be an array (unsupported-configuration)
>, 'bad expect_array err');
is(@{$result[0]}, 0, 'bad expect_array result');

($stdout, $stderr, @result) = capture {
    return CheckSpelling::LoadEnv::expect_map('', 'empty');
};
is($stdout, '', 'empty expect_map out');
is($stderr, '', 'empty expect_map err');
is(%{$result[0]}, 0, 'empty expect_map result');

($stdout, $stderr, @result) = capture {
    return CheckSpelling::LoadEnv::expect_map({ 1 => 2}, 'map');
};
is($stdout, '', 'expect_map out');
is($stderr, '', 'expect_map err');
is(join (',', %{$result[0]}), '1,2', 'expect_map result');

($stdout, $stderr, @result) = capture {
    return CheckSpelling::LoadEnv::expect_map(\'hello', 'bad map');
};
is($stdout, '', 'bad expect_map out');
is($stderr, q<'bad map' was 'SCALAR' but should be a map (unsupported-configuration)
>, 'bad expect_map err');
is(%{$result[0]}, 0, 'bad expect_map result');

my %mapped = CheckSpelling::LoadEnv::array_to_map([1,2]);
is($mapped{1}, 1, 'array_to_map index 1');
is($mapped{2}, 1, 'array_to_map index 2');
is(scalar keys %mapped, 2, 'array_to_map length');

my $json = '{"hello":"world"}';
open my $fh, '<', \$json;
my $parsed = CheckSpelling::LoadEnv::parse_config_file($fh, 'json string');
is($parsed->{'hello'}, 'world', 'parse config file');

my $bad_json = '{"key": ["a" "b"]}';
open $fh, '<', \$bad_json;
($stdout, $stderr, @result) = capture {
    CheckSpelling::LoadEnv::parse_config_file($fh, 'bad json');
};
is($stdout, '', 'parse bad json (out)');
like($stderr, qr{, or \] expected while parsing array}, 'parse bad json (err)');
is(scalar @{$result[0]}, 0, 'parse bad json (result)');

my $not_json = '';
open $fh, '<', \$not_json;
my $ref = CheckSpelling::LoadEnv::parse_config_file($fh, 'empty string');
is(ref $ref, 'HASH', 'parse_config_file fallback is ref');
is(keys %{$ref}, 0, 'parse_config_file fallback has no entries');

$ENV{INPUTS} = '{"hello":"world", "ignore-pattern":""}';
$ENV{action_yml} = 'action.yml';
my $load_config_from_key = 'load-config-from';
my $parsed_inputs = CheckSpelling::LoadEnv::parse_inputs($load_config_from_key);
my $maybe_load_inputs_from = $parsed_inputs->{'maybe_load_inputs_from'};
my $load_config_from = $parsed_inputs->{'load_config_from_key'};
my $inputs = $parsed_inputs->{'inputs'};

is($inputs->{'IGNORE_PATTERN'}, '', 'ignore pattern (empty value should suppress fallback)');

like($inputs->{'DICTIONARY_URL'}, qr{https://}, 'dictionary url');
is($maybe_load_inputs_from, undef, 'maybe_load_inputs_from');
is($load_config_from, $load_config_from_key, 'load_config_from_key');
like((join ", ", (sort keys %{$inputs})), qr{CHECK_EXTRA_DICTIONARIES.*, HELLO, .*WARNINGS}, 'inputs');
is(CheckSpelling::LoadEnv::get_json_config_path($parsed_inputs), '.github/actions/spelling/config.json', 'json_config_path');

$ENV{INPUT_CONFIG} = 't/load-event';
is($inputs->{'NEW'}, undef, 'pre-merged');
CheckSpelling::LoadEnv::load_trusted_config($parsed_inputs);
$inputs = $parsed_inputs->{'inputs'};
like($inputs->{'DICTIONARY_URL'}, qr{https://}, 'dictionary url');
is($inputs->{'NEW'}, 'world', 'merged');

sub clear {
    my ($inputs) = @_;
    for $a (qw( NEW BASE NEXT TRUSTED FAR )) {
        delete $inputs->{$a};
    }
}

clear($inputs);
is($inputs->{'NEW'}, undef, 'pre-merged');
$parsed_inputs->{'maybe_load_inputs_from'} = {
    'pr-base-keys' => ['base','next'],
    'pr-trusted-keys' => ['untrustworthy','warnings']
};

my $sandbox = tempdir;
$ENV{'sandbox'} = $sandbox;
my $email = 'user@example.com';
my $sandbox_config = "$sandbox/config";
mkdir $sandbox_config;
`
cp t/load-event/config.json '$sandbox/config';
git -c init.defaultBranch=main init '$sandbox';
git -C '$sandbox' add config/config.json;
git -C '$sandbox' -c user.name=example -c user.email='$email' commit -m 'add config';
`;

sub get_sha {
    my $sha = `git -C "$sandbox" rev-parse HEAD`;
    chomp $sha;
    return $sha;
}

my $base_sha = get_sha;
$email = 'other@example.com';
`
cp t/load-event-untrusted/config.json '$sandbox/config';
git -C '$sandbox' add config/config.json;
git -C '$sandbox' -c user.name=other -c user.email='$email' commit -m 'change config';
`;
my $head_sha = get_sha;

my ($fd, $github_event_file) = tempfile;
$ENV{GITHUB_EVENT_PATH} = $github_event_file;
print $fd qq<{
    "pull_request": {
        "base": {
            "sha": "$base_sha"
        },
        "head": {
            "sha": "$head_sha"
        }
    }
}
>;
close $fd;
$ENV{PATH} = '/usr/bin:/bin';
like($inputs->{'WARNINGS'}, qr {^(?:(?!otherwise).)+$}, 'pre untrusted_config');
$ENV{INPUT_CONFIG} = 'config';
chdir $sandbox;

($stdout, $stderr, @result) = capture {
    CheckSpelling::LoadEnv::load_untrusted_config($parsed_inputs, 'pull_request_target');
};
is($stdout, '', 'load_untrusted_config pull_request_target out');
is($stderr, q<'untrustworthy' cannot be set in pr-trusted-keys of load-config-from (unsupported-configuration)
... need to read base file
... will read live file (dangerous)
Ignoring 'base' from attacker config
Ignoring 'new' from attacker config
Ignoring 'next' from attacker config
Ignoring 'untrustworthy' from attacker config
Trusting 'WARNINGS': 'otherwise'
Using 'base': 'level'
Ignoring 'far' from base config
Ignoring 'new' from base config
Using 'next': 'time'
Ignoring 'trusted' from base config
>, 'load_untrusted_config pull_request_target err');
is($result[0], '', 'load_untrusted_config pull_request_target result');

$inputs = $parsed_inputs->{'inputs'};
is($inputs->{'WARNINGS'}, 'otherwise', 'untrusted_config pull_request_target warnings');
is($inputs->{'NEW'}, undef, 'untrusted_config pull_request_target new');
is($inputs->{'BASE'}, 'level', 'untrusted_config pull_request_target base');
is($inputs->{'NEXT'}, 'time', 'untrusted_config pull_request_target next');
is($inputs->{'UNTRUSTWORTHY'}, undef, 'untrusted_config pull_request_target untrustworthy');
is($inputs->{'WARNINGS'}, 'otherwise', 'untrusted_config pull_request_target warnings');
is($inputs->{'FAR'}, undef, 'untrusted_config pull_request_target far');

($stdout, $stderr, @result) = capture {
    CheckSpelling::LoadEnv::load_untrusted_config($parsed_inputs, 'pull_request');
};
is($stdout, '', 'load_untrusted_config pull_request out');
is($stderr, q<'untrustworthy' cannot be set in pr-trusted-keys of load-config-from (unsupported-configuration)
... need to read base file
... will read live file
Ignoring 'base' from local config
Ignoring 'new' from local config
Ignoring 'next' from local config
Ignoring 'untrustworthy' from local config
Trusting 'WARNINGS': 'otherwise'
Using 'base': 'level'
Ignoring 'far' from base config
Ignoring 'new' from base config
Using 'next': 'time'
Ignoring 'trusted' from base config
>, 'load_untrusted_config pull_request err');
is($result[0], '', 'load_untrusted_config pull_request result');

$inputs = $parsed_inputs->{'inputs'};
is($inputs->{'WARNINGS'}, 'otherwise', 'untrusted_config pull_request warnings');
is($inputs->{'NEW'}, undef, 'untrusted_config pull_request new');
is($inputs->{'BASE'}, 'level', 'untrusted_config pull_request base');
is($inputs->{'NEXT'}, 'time', 'untrusted_config pull_request next');
is($inputs->{'UNTRUSTWORTHY'}, undef, 'untrusted_config pull_request untrustworthy');
is($inputs->{'WARNINGS'}, 'otherwise', 'untrusted_config pull_request warnings');
is($inputs->{'FAR'}, undef, 'untrusted_config pull_request far');
CheckSpelling::LoadEnv::load_trusted_config($parsed_inputs);
$inputs = $parsed_inputs->{'inputs'};
is($inputs->{'WARNINGS'}, 'otherwise', 'trusted_config warnings');
is($inputs->{'NEW'}, 'world', 'trusted_config new');
is($inputs->{'BASE'}, 'level', 'trusted_config level');
is($inputs->{'NEXT'}, 'time', 'trusted_config next');
is($inputs->{'UNTRUSTWORTHY'}, 'origin', 'trusted_config untrustworthy');
is($inputs->{'WARNINGS'}, 'otherwise', 'trusted_config warnings');
is($inputs->{'FAR'}, undef, 'trusted_config far');
