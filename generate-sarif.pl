#!/usr/bin/env perl

use JSON::PP;

sub encode_low_ascii {
    $_ = shift;
    s/([\x{0}-\x{9}\x{0b}\x{1f}#])/"\\u".sprintf("%04x",ord($1))/eg;
    return $_;
}

sub parse_warnings {
    my ($warnings) = @_;
    my @results;
    open WARNINGS, '<', $warnings;
    while (<WARNINGS>) {
        next if m{^https://};
        next unless m{^(.+):(\d+):(\d+) \.\.\. (\d+),\s(Error|Warning|Notice)\s-\s(.+\s\((.+)\))$};
        my ($file, $line, $column, $endColumn, $severity, $message, $code) = ($1, $2, $3, $4, $5, $6, $7);
        # single-slash-escape `"` and `\`
        $message =~ s/(["\\])/\\$1/g;
        # double-slash-escape `"`, `(`, `)`, `]`
        $message =~ s/(["()\]])/\\\\$1/g;
        # encode `message` and `file` to protect against low ascii`
        $message = encode_low_ascii $message;
        $file = encode_low_ascii $file;
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

my $sarif_template_file = "$ENV{spellchecker}/sarif.json";
die "Could not find sarif template" unless -f $sarif_template_file;
my $sarif_template;
open TEMPLATE, '<', $sarif_template_file || print STDERR "Could not open sarif template\n";
{
    local $/ = undef;
    $sarif_template = <TEMPLATE>;
}
close TEMPLATE;
die "sarif template is empty" unless $sarif_template;

my %sarif = %{decode_json $sarif_template};
$sarif{'runs'}[0]{'tool'}{'driver'}{'version'} = $ENV{CHECK_SPELLING_VERSION};

my @results = parse_warnings $ENV{warning_output};
if (@results) {
    $sarif{'runs'}[0]{'results'} = \@results;
}

print encode_json \%sarif;
