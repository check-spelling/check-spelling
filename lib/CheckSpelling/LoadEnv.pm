#! -*-perl-*-

package CheckSpelling::LoadEnv;

use feature 'unicode_strings';
use Encode qw/decode_utf8 encode_utf8 FB_DEFAULT/;
use YAML::PP;
use JSON::PP;

my $json_canonical = JSON::PP->new->canonical([1])->utf8;

sub print_var_val {
    my ($var, $val) = @_;
    if ($var =~ /[-a-z]/) {
        print STDERR "Found improperly folded key in inputs '$var'\n";
        return;
    }
    return if $val eq '';
    print qq<export INPUT_$var='$val';\n>;
}

sub expect_array {
    my ($ref, $label) = @_;
    my $ref_kind = ref $ref;
    if ($ref eq '') {
        $ref = [];
    } elsif (ref $ref ne 'ARRAY') {
        print STDERR "'$label' should be an array (unsupported-configuration)\n";
        $ref = [];
    }
    return $ref;
}

sub expect_map {
    my ($ref, $label) = @_;
    my $ref_kind = ref $ref;
    if ($ref_kind eq '') {
        $ref = {};
    } elsif ($ref_kind ne 'HASH') {
        print STDERR "'$label' was '$ref_kind' but should be a map (unsupported-configuration)\n";
        $ref = {};
    }
    return $ref;
}

sub decode_key_val {
    my ($key, $val) = @_;
    my $ref_kind = ref $val;
    if ($ref_kind eq 'HASH') {
        $val = $json_canonical->encode($val);
    } elsif ($ref_kind eq 'ARRAY') {
        $val = join ' ', @$val;
    }
    return escape_var_val($key, $val);
}

sub array_to_map {
    my ($array_ref) = @_;
    return map { $_ => 1 } @$array_ref;
}

sub escape_var_val {
    my ($var, $val) = @_;
    $val =~ s/([\$])/\\$1/g;
    $val =~ s/'/'"'"'/g;
    $var = uc $var;
    $var =~ s/-/_/g;
    return ($var, $val);
}

sub parse_config_file {
    my ($config_data, $config_file_path) = @_;
    local $/ = undef;
    my $base_config_data = <$config_data>;
    close $config_data;
    if (wantarray) {
        my @parsed_config = eval {
            @parsed_config = decode_json($base_config_data || '[]');
        };
        if ($@) {
            print STDERR "Error decoding `$config_file_path`: $@:\n";
            return decode_json('[]');
        }
        return @parsed_config;
    }
    my $parsed_config = eval {
        decode_json($base_config_data || '{}');
    };
    if ($@) {
        print STDERR "Error decoding `$config_file_path`: $@:\n";
        return {};
    }
    return $parsed_config;
}

sub read_config_from_sha {
    my ($github_head_sha, $parsed_inputs) = @_;
    my $file = get_json_config_path($parsed_inputs);
    open (my $config_data, '-|:raw', qq!git show '$github_head_sha':'$file' 2> /dev/null || echo '{"broken":1}'!);
    return parse_config_file($config_data, "$file\@$github_head_sha");
}

sub read_config_from_file {
    my ($parsed_inputs) = @_;
    my $config_file_path = get_json_config_path($parsed_inputs);
    open my $config_data, '<:raw', $config_file_path;
    return parse_config_file($config_data, $config_file_path);
}

sub parse_inputs {
    my ($load_config_from_key) = @_;
    my $input = $ENV{INPUTS};
    my %raw_inputs;
    if ($input) {
        %raw_inputs = %{decode_json(Encode::encode_utf8($input))};
    }
    my $maybe_load_inputs_from = $raw_inputs{$load_config_from_key};

    my %inputs;
    for my $key (keys %raw_inputs) {
        next unless $key;
        my $val = $raw_inputs{$key};
        my $var = $key;
        if ($val =~ /^github_pat_/ && $key !~ /-token$|^GITHUB_TOKEN/) {
            print STDERR "Censoring `$var` (unexpected-input-value)\n";
            next;
        }
        next if $var =~ /\s/;
        next if $var =~ /[-_](?:key|token)$/;
        if ($var =~ /-/ && $raw_inputs{$var} ne '') {
            my $var_pattern = $var;
            $var_pattern =~ s/-/[-_]/g;
            my @vars = grep { /^${var_pattern}$/ && ($var ne $_) && $raw_inputs{$_} ne '' && $raw_inputs{$var} ne $raw_inputs{$_} } keys %raw_inputs;
            if (@vars) {
                print STDERR 'Found conflicting inputs for '.$var." ($raw_inputs{$var}): ".join(', ', map { "$_ ($raw_inputs{$_})" } @vars)." (migrate-underscores-to-dashes)\n";
            }
            $var =~ s/-/_/g;
        }
        ($var, $val) = escape_var_val($var, $val);
        $inputs{$var} = $val;
    }

    my $parsed_inputs = {
        maybe_load_inputs_from => $maybe_load_inputs_from,
        load_config_from_key => $load_config_from_key,
        inputs => \%inputs,
    };
    parse_action_config($parsed_inputs);
    return $parsed_inputs;
}

sub parse_action_config {
    my ($parsed_inputs) = @_;
    my $action_yml_path = $ENV{action_yml};
    return unless defined $action_yml_path;

    my $action = YAML::PP::LoadFile($action_yml_path);
    return unless defined $action->{inputs};
    my %inputs = %{$parsed_inputs->{'inputs'}};
    my %action_inputs = %{$action->{inputs}};
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
        ($var, $val) = escape_var_val($var, $val);
        next if defined $inputs{$var};
        $inputs{$var} = $val;
    }
    $parsed_inputs->{'inputs'} = \%inputs;
}

sub get_supported_key_list {
    my @supported_key_list = qw(
        check_extra_dictionaries
        check_file_names
        dictionary_source_prefixes
        dictionary_url
        dictionary_version
        extra_dictionaries
        extra_dictionary_limit
        errors
        notices
        longest_word
        lower-pattern
        punctuation-pattern
        upper-pattern
        ignore-pattern
        lower-pattern
        not-lower-pattern
        not-upper-or-lower-pattern
        punctuation-pattern
        upper-pattern
        warnings
    );
    return \@supported_key_list;
}

sub get_json_config_path {
    my ($parsed_inputs) = @_;
    my $config = $ENV{INPUT_CONFIG} || $parsed_inputs->{'inputs'}{'CONFIG'} || '.github/actions/spelling';
    return "$config/config.json";
}

sub read_project_config {
    my ($parsed_inputs) = @_;
    return read_config_from_file($parsed_inputs);
}

sub load_untrusted_config {
    my ($parsed_inputs, $event_name) = @_;
    my $maybe_load_inputs_from = $parsed_inputs->{'maybe_load_inputs_from'};
    my $load_config_from_key = $parsed_inputs->{'load_config_from_key'};

    my %supported_keys = array_to_map(get_supported_key_list);

    return unless defined $maybe_load_inputs_from;
    $maybe_load_inputs_from = decode_json $maybe_load_inputs_from unless ref $maybe_load_inputs_from eq 'HASH';

    $maybe_load_inputs_from = expect_map($maybe_load_inputs_from, $load_config_from_key);
    my %load_config_from = %$maybe_load_inputs_from;
    my $use_pr_base_keys = 'pr-base-keys';
    my $trust_pr_keys = 'pr-trusted-keys';
    my $use_pr_base_key = expect_array($load_config_from{$use_pr_base_keys}, "$load_config_from_key->$use_pr_base_keys");
    my $trust_pr_key = expect_array($load_config_from{$trust_pr_keys}, "$load_config_from_key->$use_pr_base_keys");
    my @use_pr_base_key_list = @$use_pr_base_key;
    my @trust_pr_key_list = @$trust_pr_key;
    my %use_pr_base_key_map = array_to_map $use_pr_base_key if (defined $use_pr_base_key);
    my %trust_pr_key_map = array_to_map $trust_pr_key if (defined $trust_pr_key);
    delete $use_pr_base_key_map{''};
    delete $trust_pr_key_map{''};
    for my $key (keys %trust_pr_key_map) {
        if (defined $use_pr_base_key_map{$key}) {
            delete $trust_pr_key_map{$key};
            print STDERR "'$key' found in both $use_pr_base_keys and $trust_pr_keys of $load_config_from_key (unsupported-configuration)\n";
        }
        unless (defined $supported_keys{$key}) {
            delete $trust_pr_key_map{$key};
            print STDERR "'$key' cannot be set in $trust_pr_keys of $load_config_from_key (unsupported-configuration)\n";
        }
    }
    return unless %use_pr_base_key_map or %trust_pr_key_map;
    if (%use_pr_base_key_map) {
        print STDERR "... need to read base file\n";
    }

    if (%trust_pr_key_map) {
        my ($maybe_dangerous, $local_config);
        if (defined $event_name && $event_name eq 'pull_request_target') {
            ($maybe_dangerous, $local_config) = (' (dangerous)', 'attacker');
        } else {
            ($maybe_dangerous, $local_config) = ('', 'local');
        }

        print STDERR "... will read live file$maybe_dangerous\n";
        my %dangerous_config = %{read_project_config($parsed_inputs)};
        for my $key (sort keys %dangerous_config) {
            if (defined $trust_pr_key_map{$key}) {
                my $val = $dangerous_config{$key};
                ($key, $val) = decode_key_val($key, $val);
                print STDERR "Trusting '$key': '$val'\n";
                $parsed_inputs->{'inputs'}{$key} = $val;
            } else {
                print STDERR "Ignoring '$key' from $local_config config\n";
            }
        }
    }

    return unless %use_pr_base_key_map;

    my $github_event_path = $ENV{GITHUB_EVENT_PATH};
    open my $github_event_file, '<:raw', $github_event_path;
    local $/ = undef;
    my $github_event_data = <$github_event_file>;
    close $github_event_file;
    my $github_event;
    {
        local $@;
        eval {
            $github_event = decode_json ($github_event_data || '{}');
        };
        if ($@) {
            print STDERR "cat $github_event_path:\n";
            print STDERR `cat "$github_event_path"`;
            print STDERR "\n===TEAR===\n";
            die "::error ::decode_json failed on $github_event_path: $@\n";
        }
    }
    my $github_head_sha;
    $github_head_sha = $github_event->{'pull_request'}->{'base'}->{'sha'} if ($github_event->{'pull_request'} && $github_event->{'pull_request'}->{'base'});

    my %base_config = %{read_config_from_sha($github_head_sha, $parsed_inputs)};
    for my $key (sort keys %base_config) {
        if (defined $use_pr_base_key_map{$key}) {
            my ($var, $val);
            $val = $base_config{$key};
            ($var, $val) = decode_key_val($key, $val);
            print STDERR "Using '$key': '$val'\n";
            $parsed_inputs->{'inputs'}{$var} = $val;
        } else {
            print STDERR "Ignoring '$key' from base config\n";
        }
    }
}

sub load_trusted_config {
    my ($parsed_inputs) = @_;
    my %project_config = %{read_project_config($parsed_inputs)};
    for my $key (keys %project_config) {
        my ($var, $val) = decode_key_val($key, $project_config{$key});
        $parsed_inputs->{'inputs'}{$var} = $val;
    }
}

1;
