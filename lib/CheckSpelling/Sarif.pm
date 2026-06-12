#! -*-perl-*-

package CheckSpelling::Sarif;

our $VERSION='0.1.0';
our $flatten=0;

use utf8;

use File::Basename;
use File::Spec;
use Digest::SHA qw($errmsg);
use JSON::PP;
use Hash::Merge qw( merge );
use CheckSpelling::Util;
use CheckSpelling::GitSources;

sub encode_low_ascii {
    $_ = shift;
    s/([\x{0}-\x{9}\x{0b}\x{1f}#%])/"\\u".sprintf("%04x",ord($1))/eg;
    return $_;
}

sub url_encode {
    $_ = shift;
    s<([^-!\$&'()*+,/:;=?\@A-Za-z0-9_.~])><"%".sprintf("%02x",ord($1))>eg;
    return $_;
}

sub double_slash_escape {
    $_ = shift;
    s/(["()\[\]\\])/\\\\$1/g;
    return $_;
}

sub fingerprintLocations {
    my ($locations, $encoded_files_ref, $line_hashes_ref, $hashes_needed_for_files_ref, $message, $hashed_message) = @_;
    my @locations_json = ();
    my @fingerprints = ();
    for my $location (@$locations) {
        my $encoded_file = $location->{uri};
        my $line = $location->{startLine};
        my $column = $location->{startColumn};
        my $endColumn = $location->{endColumn};
        my $partialFingerprint = '';
        my $file = $encoded_files_ref->{$encoded_file};
        if (defined $line_hashes_ref->{$file}) {
            my $line_hash = $line_hashes_ref->{$file}{$line};
            if (defined $line_hash) {
                my @instances = sort keys %{$hashes_needed_for_files_ref->{$file}{$line}{$hashed_message}};
                my $hit = scalar @instances;
                while (--$hit > 0) {
                    last if $instances[$hit] == $column;
                }
                $partialFingerprint = Digest::SHA::sha1_base64("$line_hash:$message:$hit");
            }
        }
        push @fingerprints, $partialFingerprint;
        my $startColumn = $column ? qq<, "startColumn": $column> : '';
        $endColumn = $endColumn ? qq<, "endColumn": $endColumn> : '';
        $line = 1 unless $line;
        my $json_fragment = qq<{ "physicalLocation": { "artifactLocation": { "uri": "$encoded_file", "uriBaseId": "%SRCROOT%" }, "region": { "startLine": $line$startColumn$endColumn } } }>;
        push @locations_json, $json_fragment;
    }
    return { locations_json => \@locations_json, fingerprints => \@fingerprints };
}

sub hashFiles {
    my ($hashes_needed_for_files_ref, $line_hashes_ref, $directoryToRepo_ref, $used_hashes_ref) = @_;
    for my $file (sort keys %$hashes_needed_for_files_ref) {
        $line_hashes_ref->{$file} = ();
        unless (-e $file) {
            delete $hashes_needed_for_files_ref->{$file};
            next;
        }
        my @lines = sort (keys %{$hashes_needed_for_files_ref->{$file}});
        unless (defined $directoryToRepo_ref->{dirname($file)}) {
            my ($parsed_file, $git_base_dir, $prefix, $remote_url, $rev, $branch) = CheckSpelling::GitSources::git_source_and_rev($file);
        }
        open $file_fh, '<', $file;
        my $line = shift @lines;
        $line = 2 if $line == 1;
        my $buffer = '';
        while (<$file_fh>) {
            if ($line == $.) {
                my $sample = substr $buffer, -100, 100;
                my $hash = Digest::SHA::sha1_base64($sample);
                for (; $line == $.; $line = shift @lines) {
                    my $hit = $used_hashes_ref->{$hash}++;
                    $hash = "$hash:$hit" if $hit;
                    $line_hashes_ref->{$file}{$line} = $hash;
                    last unless @lines;
                }
            }
            $buffer .= $_;
            $buffer =~ s/\s+/ /g;
            $buffer = substr $buffer, -100, 100;
        }
        close $file_fh;
    }
}

sub addToHashesNeededForFiles {
    my ($file, $line, $column, $message, $hashes_needed_for_files_ref) = @_;
    my $hashed_message = Digest::SHA::sha1_base64($message);
    $hashes_needed_for_files_ref->{$file} = () unless defined $hashes_needed_for_files_ref->{$file};
    $hashes_needed_for_files_ref->{$file}{$line} = () unless defined $hashes_needed_for_files_ref->{$file}{$line};
    $hashes_needed_for_files_ref->{$file}{$line}{$hashed_message} = () unless defined $hashes_needed_for_files_ref->{$file}{$line}{$hashed_message};
    $hashes_needed_for_files_ref->{$file}{$line}{$hashed_message}{$column} = '1';
}

sub encode_message {
    my ($message) = @_;

    # slash escape `"` and `\`
    $message =~ s/(["\\])/\\$1/g;
    # escape '*'/`_` for markdown
    # encode `message` to protect against low ascii`
    $message = encode_low_ascii $message;
    # double-slash-escape `"`, `(`, `)`, `]`
    $message = double_slash_escape $message;
    my $doubled_slash = '\\\\';
    $message =~ s/([*])(.*?)([*])/$doubled_slash$1$2$doubled_slash$3/g;
    $message =~ s/([_])(.*?)([_])/$doubled_slash$1$2$doubled_slash$3/g;
    # hack to make the first `...` identifier a link (that goes nowhere, but is probably blue and underlined) in GitHub's SARIF view
    if ($message =~ /(`{2,})/) {
        my $backticks = $1;
        while ($message =~ /($backticks`+)(?=[`].*?\g{-1})/gs) {
            $backticks = $1 if length($1) > length($backticks);
        }
        $message =~ s/(^|[^\\])$backticks(.+?)$backticks/${1}[${2}](#security-tab)/;
    } else {
        $message =~ s/(^|[^\\])\`((?:[^`\\]|\\(?!`))+)\`/${1}[${2}](#security-tab)/;
    }

    # replace '`' with `\`+`'` because GitHub's SARIF parser doesn't like them
    $message =~ s/\`/'/g;
    return $message;
}

sub parse_warnings {
    my ($warnings) = @_;
    our $flatten;
    our %directoryToRepo;
    our $provenanceInsertion;
    our %provenanceStringToIndex;
    our %directoryToProvenanceInsertion;
    my @results;
    unless (open WARNINGS, '<', $warnings) {
        print STDERR "Could not open $warnings\n";
        return [];
    }
    my $rules = ();
    my %encoded_files = ();
    my %hashes_needed_for_files = ();
    while (<WARNINGS>) {
        next if m{^https://};
        next unless m{^(.+):(\d+):(\d+) \.\.\. (\d+),\s(Error|Warning|Notice)\s-\s(.+\s\((.+)\))$};
        my ($file, $line, $column, $endColumn, $severity, $message, $code) = ($1, $2, $3, $4, $5, $6, $7);
        my $directory = dirname($file);
        unless (defined $directoryToProvenanceInsertion{$directory}) {
            my $provenanceString = collectVersionControlProvenance($file);
            if ($provenanceString) {
                if (defined $provenanceStringToIndex{$provenanceString}) {
                    $directoryToProvenanceInsertion{$directory} = $provenanceStringToIndex{$provenanceString};
                } else {
                    $provenanceStringToIndex{$provenanceString} = $provenanceInsertion;
                    $directoryToProvenanceInsertion{$directory} = $provenanceInsertion;
                    ++$provenanceInsertion;
                }
            }
        }
        # encode `file` to protect against low ascii`
        my $encoded_file = url_encode $file;
        $encoded_files{$encoded_file} = $file;

        $message = encode_message($message);

        unless (defined $rules->{$code}) {
            $rules->{$code} = {};
        }
        my $rule = $rules->{$code};
        unless (defined $rule->{$message}) {
            $rule->{$message} = [];
        }
        addToHashesNeededForFiles($file, $line, $column, $message, \%hashes_needed_for_files);
        my $locations = $rule->{$message};
        my $physicalLocation = {
            'uri' => $encoded_file,
            'startLine' => $line,
            'startColumn' => $column,
            'endColumn' => $endColumn,
        };
        push @$locations, $physicalLocation;
        $rule->{$message} = $locations;
    }
    my %line_hashes = ();
    my %used_hashes = ();
    hashFiles(\%hashes_needed_for_files, \%line_hashes, \%directoryToRepo, \%used_hashes);
    for my $code (sort keys %{$rules}) {
        my $rule = $rules->{$code};
        for my $message (sort keys %{$rule}) {
            my $hashed_message = Digest::SHA::sha1_base64($message);
            my $locations = $rule->{$message};
            my $fingerprintResults = fingerprintLocations($locations, \%encoded_files, \%line_hashes, \%hashes_needed_for_files, $message, $hashed_message);
            my @locations_json = @{$fingerprintResults->{locations_json}};
            my @fingerprints = @{$fingerprintResults->{fingerprints}};
            if ($flatten) {
                my $locations_json_flat = join ',', @locations_json;
                my $partialFingerprints;
                my $partialFingerprint = (sort @fingerprints)[0];
                if ($partialFingerprint ne '') {
                    $partialFingerprints = qq<"partialFingerprints": { "cs0" : "$partialFingerprint" },>;
                }
                $message =~ s/\s\\\\\([^()]+?\\\)$//g;
                my $result_json = qq<{"ruleId": "$code", $partialFingerprints "message": { "text": "$message" }, "locations": [ $locations_json_flat ] }>;
                my $result = decode_json $result_json;
                push @results, $result;
            } else {
                my $limit = scalar @locations_json;
                for (my $i = 0; $i < $limit; ++$i) {
                    my $locations_json_flat = $locations_json[$i];
                    my $partialFingerprints = '';
                    my $partialFingerprint = $fingerprints[$i];
                    if ($partialFingerprint ne '') {
                        $partialFingerprints = qq<"partialFingerprints": { "cs0" : "$partialFingerprint" },>;
                    }
                    $message =~ s/\s\\\\\([^()]+?\\\)$//g;
                    my $result_json = qq<{"ruleId": "$code", $partialFingerprints "message": { "text": "$message" }, "locations": [ $locations_json_flat ] }>;
                    my $result = eval {
                        decode_json $result_json;
                    };
                    if ($@) {
                        print STDERR "$@";
                        print STDERR "$result_json\n";
                    } else {
                        push @results, $result;
                    }
                }
            }
        }
    }
    close WARNINGS;
    return \@results;
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

sub collectVersionControlProvenance {
    my ($file) = @_;
    my ($parsed_file, $git_base_dir, $prefix, $remote_url, $rev, $branch) = CheckSpelling::GitSources::git_source_and_rev($file);
    return '' unless $remote_url;
    my $base = substr $parsed_file, 0, length($file);
    my $provenance = [$remote_url, $rev, $branch, $git_base_dir];
    return JSON::PP::encode_json($provenance);
}

sub generateVersionControlProvenance {
    my ($versionControlProvenanceList, $run) = @_;
    my %provenance;
    sub buildVersionControlProvenance {
        my $d = $_;
        my ($remote_url, $rev, $branch, $git_base_dir) = @{JSON::PP::decode_json($d)};
        my $dir = $git_base_dir eq '.' ? '%SRCROOT%' : "DIR_$provenanceStringToIndex{$d}";
        my $mappedTo = {
            "uriBaseId" => $dir
        };
        my $versionControlProvenance = {
            "mappedTo" => $mappedTo
        };
        $versionControlProvenance->{"revisionId"} = $rev if defined $rev;
        $versionControlProvenance->{"branch"} = $branch if defined $branch;
        $versionControlProvenance->{"repositoryUri"} = $remote_url if defined $remote_url;
        return $versionControlProvenance;
    }
    @provenanceList = map(buildVersionControlProvenance,@$versionControlProvenanceList);
    $run->{"versionControlProvenance"} = \@provenanceList;
}

my $provenanceInsertion = 0;
my %provenanceStringToIndex = ();
my %directoryToProvenanceInsertion = ();

sub main {
    my ($sarif_template_file, $sarif_template_overlay_file, $category) = @_;
    unless (-f $sarif_template_file) {
        warn "Could not find SARIF template";
        return '';
    }

    $ENV{GITHUB_SERVER_URL} = '' unless defined $ENV{GITHUB_SERVER_URL};
    $ENV{GITHUB_REPOSITORY} = '' unless defined $ENV{GITHUB_REPOSITORY};
    my $sarif_template = CheckSpelling::Util::read_file $sarif_template_file;
    die "sarif template is empty" unless $sarif_template;

    my $json = JSON::PP->new->utf8->pretty->sort_by(sub { $JSON::PP::a cmp $JSON::PP::b });
    my $sarif_json = $json->decode($sarif_template);

    if (defined $sarif_template_overlay_file && -s $sarif_template_overlay_file) {
        my $merger = Hash::Merge->new();
        my $merge_behaviors = $merger->{'behaviors'}->{$merger->get_behavior()};
        my $merge_arrays = $merge_behaviors->{'ARRAY'}->{'ARRAY'};

        $merge_behaviors->{'ARRAY'}->{'ARRAY'} = sub {
            return $merge_arrays->(@_) if ref($_[0][0]).ref($_[1][0]);
            return [@{$_[1]}];
        };

        my $sarif_template_overlay = CheckSpelling::Util::read_file $sarif_template_overlay_file;
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
    {
        my @sarif_json_runs = @{$sarif_json->{'runs'}};
        foreach my $sarif_json_run (@sarif_json_runs) {
            my %sarif_json_run_automationDetails;
            $sarif_json_run_automationDetails{id} = $category;
            $sarif_json_run->{'automationDetails'} = \%sarif_json_run_automationDetails;
        }
    }

    my %sarif = %{$sarif_json};

    $sarif{'runs'}[0]{'tool'}{'driver'}{'version'} = $ENV{CHECK_SPELLING_VERSION};
    my $report_suffix = CheckSpelling::Util::get_file_from_env('INPUT_REPORT_TITLE_SUFFIX', '');
    if ($report_suffix ne '') {
        $report_suffix =~ s/^\s+|\s+$//g;
        $report_suffix =~ s/\s+/-/g;
        $sarif{'runs'}[0]{'tool'}{'driver'}{'name'} .= "-$report_suffix";
    }

    my $results = parse_warnings $ENV{warning_output};
    if ($results) {
        $sarif{'runs'}[0]{'results'} = $results;
        our %provenanceStringToIndex;
        my @provenanceList = keys %provenanceStringToIndex;
        generateVersionControlProvenance(\@provenanceList, $sarif{'runs'}[0]);
        my %codes;
        for my $result_ref (@$results) {
            my %result = %{$result_ref};
            $codes{$result{'ruleId'}} = 1;
        }
        my $rules_ref = $sarif{'runs'}[0]{'tool'}{'driver'}{'rules'};
        my @rules = @{$rules_ref};
        my $missing_rule_definition_id = 'missing-rule-definition';
        my ($missing_rule_definition_ref) = grep { $_->{'id'} eq $missing_rule_definition_id } @rules;
        @rules = grep { defined $codes{$_->{'id'}} } @rules;
        my $code_index = 0;
        my %defined_codes = map { $_->{'id'} => $code_index++ } @rules;
        my @missing_codes = grep { !defined $defined_codes{$_}} keys %codes;
        my $missing_rule_definition_index;
        if (@missing_codes) {
            push @rules, $missing_rule_definition_ref;
            $missing_rule_definition_index = $defined_codes{$missing_rule_definition_id} = $code_index++;
            my $spellchecker = $ENV{spellchecker} || dirname(dirname(dirname(__FILE__)));
            my %hashes_needed_for_files = ();
            my %line_hashes = ();
            my %used_hashes = ();
            our %directoryToRepo;
            for my $missing_code (@missing_codes) {
                my $message = "No rule definition for `$missing_code`";
                my $code_locations = `find '$spellchecker' -name '.git*' -prune -o \\( -name '*.sh' -o -name '*.pl' -o -name '*.pm' \\) -type f -print0|xargs -0 grep -n '$missing_code' | perl -pe 's<^\./><>'`;
                my @locations;
                for my $line (split /\n/, $code_locations) {
                    chomp $line;
                    my ($file, $lineno, $code) = $line =~ /^(.+?):(\d+):(.+)$/;
                    next unless defined $file;
                    $code =~ /^(.*?)\b$missing_code\b/;
                    my $startColumn = length($1) + 1;
                    my $endColumn = length($1) + length($missing_code) + 1;
                    my $location = {
                        'uri' => url_encode($file),
                        'startLine' => $lineno,
                        'startColumn' => $startColumn,
                        'endColumn' => $endColumn,
                    };
                    my $relative = File::Spec->abs2rel($file, $spellchecker);
                    print STDERR "::notice title=${missing_rule_definition_id}::$relative:$lineno:$startColumn ... $endColumn, Notice - $message ($missing_rule_definition_id)\n";
                    push @locations, $location;
                    my $encoded_file = url_encode $file;
                    $encoded_files{$encoded_file} = $file;
                    addToHashesNeededForFiles($file, $lineno, $startColumn, $message, \%hashes_needed_for_files);
                }
                hashFiles(\%hashes_needed_for_files, \%line_hashes, \%directoryToRepo, \%used_hashes);
                my $fingerprintResults = fingerprintLocations(\@locations, \%encoded_files, \%encoded_files, \%line_hashes, $message, Digest::SHA::sha1_base64($message));
                my @locations_json = @{$fingerprintResults->{locations_json}};
                my @fingerprints = @{$fingerprintResults->{fingerprints}};
                my $locations_json_flat = join ',', @locations_json;
                my $partialFingerprints = '';
                my $locations = $locations_json_flat ? qq<, "locations": [ $locations_json_flat ]> : '';
                my $result_json = qq<{"ruleId": "$missing_rule_definition_id", $partialFingerprints "message": { "text": "$message" }$locations }>;
                my $result = decode_json $result_json;
                push @{$results}, $result;
            }
        }
        $sarif{'runs'}[0]{'tool'}{'driver'}{'rules'} = \@rules;
        for my $result_index (0 .. scalar @{$results}) {
            my $result = $results->[$result_index];
            my $ruleId = $result->{'ruleId'};
            next if defined $ruleId && defined $defined_codes{$ruleId};
            $result->{'ruleId'} = $missing_rule_definition_id;
        }
    }

    return JSON::PP->new->canonical([1])->utf8->encode(\%sarif);
}

1;
