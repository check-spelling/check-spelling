#! -*-perl-*-

package CheckSpelling::Sarif;

our $VERSION='0.1.0';

use JSON::PP;
use Hash::Merge qw( merge );

sub encode_low_ascii {
    $_ = shift;
    s/([\x{0}-\x{9}\x{0b}\x{1f}#%])/"\\u".sprintf("%04x",ord($1))/eg;
    return $_;
}

sub url_encode {
    $_ = shift;
    s<([^-!#\$&'()*+,/:;=?\@\[\]A-Za-z0-9_.~])><"%".sprintf("%02x",ord($1))>eg;
    return $_;
}

sub double_slash_escape {
    $_ = shift;
    s/(["()\]\\])/\\\\$1/g;
    return $_;
}
sub parse_warnings {
    my ($warnings) = @_;
    my @results;
    open WARNINGS, '<', $warnings || print STDERR "Could not open $warnings\n";
    while (<WARNINGS>) {
        next if m{^https://};
        next unless m{^(.+):(\d+):(\d+) \.\.\. (\d+),\s(Error|Warning|Notice)\s-\s(.+\s\((.+)\))$};
        my ($file, $line, $column, $endColumn, $severity, $message, $code) = ($1, $2, $3, $4, $5, $6, $7);
        # single-slash-escape `"` and `\`
        $message =~ s/(["\\])/\\$1/g;
        $message = encode_low_ascii $message;
        # double-slash-escape `"`, `(`, `)`, `]`
        $message = double_slash_escape $message;
        # encode `message` and `file` to protect against low ascii`
        $file = url_encode $file;
        # hack to make the first `...` identifier a link (that goes nowhere, but is probably blue and underlined) in GitHub's sarif view
        $message =~ s/(^|[^\\])\`([^`]+[^`\\])\`/${1}[${2}](#security-tab)/;
        # replace '`' with `\`+`"` because GitHub's SARIF parser doesn't like them
        $message =~ s/\`/\\"/g;
        my $result_json = qq<{"ruleId": "$code", "ruleIndex": 0,"message": { "text": "$message" }, "locations": [ { "physicalLocation": { "artifactLocation": { "uri": "$file", "uriBaseId": "%SRCROOT%" }, "region": { "startLine": $line, "startColumn": $column, "endColumn": $endColumn } } } ] }>;
        my $result = decode_json $result_json;
        push @results, $result;
    }
    close WARNINGS;
    return @results;
}

sub read_sarif_file {
    my ($file) = @_;
    my $template;
    open TEMPLATE, '<', $file || print STDERR "Could not open sarif template ($file)\n";
    {
        local $/ = undef;
        $template = <TEMPLATE>;
    }
    close TEMPLATE;
    return $template;
}

sub get_runs_from_sarif {
    my ($sarif_json) = @_;
    my %runs_view;
    return %runs_view unless $sarif_json->{'runs'};
    my @sarif_json_runs=@{$sarif_json->{'runs'}};
    foreach my $sarif_json_run (@sarif_json_runs) {
        my %sarif_json_run_hash=%{$sarif_json_run};
        next unless defined $sarif_json_run_hash{'tool'};

        my %sarif_json_run_tool_hash = %{$sarif_json_run_hash{'tool'}};
        next unless defined $sarif_json_run_tool_hash{'driver'};

        my %sarif_json_run_tool_driver_hash = %{$sarif_json_run_tool_hash{'driver'}};
        next unless defined $sarif_json_run_tool_driver_hash{'name'} &&
            defined $sarif_json_run_tool_driver_hash{'rules'};

        my $driver_name = $sarif_json_run_tool_driver_hash{'name'};
        my @sarif_json_run_tool_driver_rules = @{$sarif_json_run_tool_driver_hash{'rules'}};
        my %driver_view;
        for my $driver_rule (@sarif_json_run_tool_driver_rules) {
            next unless defined $driver_rule->{'id'};
            $driver_view{$driver_rule->{'id'}} = $driver_rule;
        }
        $runs_view{$sarif_json_run_tool_driver_hash{'name'}} = \%driver_view;
    }
    return %runs_view;
}

sub main {
    my ($sarif_template_file, $sarif_template_overlay_file) = @_;
    unless (-f $sarif_template_file) {
        warn "Could not find sarif template";
        return '';
    }

    my $sarif_template = read_sarif_file $sarif_template_file;
    die "sarif template is empty" unless $sarif_template;

    my $json = JSON::PP->new->utf8->pretty->sort_by(sub { $JSON::PP::a cmp $JSON::PP::b });
    my $sarif_json = $json->decode($sarif_template);

    if (defined $sarif_template_overlay_file) {
        my $merger = Hash::Merge->new();
        my $merge_behaviors = $merger->{'behaviors'}->{$merger->get_behavior()};
        my $merge_arrays = $merge_behaviors->{'ARRAY'}->{'ARRAY'};

        $merge_behaviors->{'ARRAY'}->{'ARRAY'} = sub {
            return $merge_arrays->(@_) if ref($_[0][0]).ref($_[1][0]);
            return [@{$_[1]}];
        };

        if (-s $sarif_template_overlay_file) {
            my $sarif_template_overlay = read_sarif_file $sarif_template_overlay_file;
            my %runs_base = get_runs_from_sarif($sarif_json);

            my $sarif_template_hash = $json->decode($sarif_template_overlay);
            my %runs_overlay = get_runs_from_sarif($sarif_template_hash);
            for my $run_id (keys %runs_overlay) {
                if (defined $runs_base{$run_id}) {
                    my $run_base_hash = $runs_base{$run_id};
                    my $run_overlay_hash = $runs_overlay{$run_id};
                    for my $overlay_id (keys %$run_overlay_hash) {
                        $run_base_hash->{$overlay_id} = $merger->merge(
                            $run_overlay_hash->{$overlay_id},
                            $run_base_hash->{$overlay_id}
                        );
                    }
                } else {
                    $runs_base{$run_id} = $runs_overlay{$run_id};
                }
            }
            #$sarif_json->
            my @sarif_json_runs = @{$sarif_json->{'runs'}};
            foreach my $sarif_json_run (@sarif_json_runs) {
                my %sarif_json_run_hash=%{$sarif_json_run};
                next unless defined $sarif_json_run_hash{'tool'};

                my %sarif_json_run_tool_hash = %{$sarif_json_run_hash{'tool'}};
                next unless defined $sarif_json_run_tool_hash{'driver'};

                my %sarif_json_run_tool_driver_hash = %{$sarif_json_run_tool_hash{'driver'}};
                my $driver_name = $sarif_json_run_tool_driver_hash{'name'};
                next unless defined $driver_name &&
                    defined $sarif_json_run_tool_driver_hash{'rules'};

                my $driver_view_hash = $runs_base{$driver_name};
                next unless defined $driver_view_hash;

                my @sarif_json_run_tool_driver_rules = @{$sarif_json_run_tool_driver_hash{'rules'}};
                for my $driver_rule_number (0 .. scalar @sarif_json_run_tool_driver_rules) {
                    my $driver_rule = $sarif_json_run_tool_driver_rules[$driver_rule_number];
                    my $driver_rule_id = $driver_rule->{'id'};
                    next unless defined $driver_rule_id &&
                        defined $driver_view_hash->{$driver_rule_id};
                    $sarif_json_run_tool_driver_hash{'rules'}[$driver_rule_number] = $merger->merge($driver_view_hash->{$driver_rule_id}, $driver_rule);
                }
            }
            delete $sarif_template_hash->{'runs'};
            $sarif_json = $merger->merge($sarif_json, $sarif_template_hash);
        }
    }

    my %sarif = %{$sarif_json};

    $sarif{'runs'}[0]{'tool'}{'driver'}{'version'} = $ENV{CHECK_SPELLING_VERSION};

    my @results = parse_warnings $ENV{warning_output};
    if (@results) {
        $sarif{'runs'}[0]{'results'} = \@results;
    }

    return encode_json \%sarif;
}

1;
