#!/usr/bin/env perl
use File::Temp qw/ tempfile tempdir /;

use CheckSpelling::Util;

unless (eval 'use URI::Escape; 1') {
    eval 'use URI::Escape::XS qw/uri_escape/';
}

my $budget = CheckSpelling::Util::get_val_from_env("summary_budget", "");
print STDERR "Summary Tables budget: $budget\n";
my $summary_tables = tempdir();
my $table;
my @tables;

my $url_base = "$ENV{GITHUB_SERVER_URL}/$ENV{GITHUB_REPOSITORY}/blame";
my $rev = $ENV{GITHUB_HEAD_REF} || $ENV{GITHUB_SHA};

while (<>) {
    next unless m{^(.+):(\d+):(\d+) \.\.\. (\d+),\s(Error|Warning|Notice)\s-\s(.+)\s\(([-a-z]+)\)$};
    my ($file, $line, $column, $endColumn, $severity, $message, $code) = ($1, $2, $3, $4, $5, $6, $7);
    my $table_file = "$summary_tables/$code";
    push @tables, $code unless -e $table_file;
    open $table, ">>", $table_file;
    $message =~ s/\|/\\|/g;
    if ($file =~ m{^https://}) {
        $file =~ s/ /%20/g;
        print $table "$message | $file#$line\n"
    } else {
        $file = uri_escape($file, "^A-Za-z0-9\-\._~/");
        print $table "$message | $url_base/$rev/$file#L$line\n"
    }
    close $table;
}
exit unless @tables;

my ($prefix, $footer, $suffix) = (
    "<details><summary>Details :mag_right:</summary>\n\n",
    "</details>\n\n",
    "\n</details>\n\n"
);
my $footer_length = length $footer;
if ($budget) {
    $budget -= length $prefix + length $suffix;
    print STDERR "Summary Tables budget reduced to: $budget\n";
}
print $prefix;
for $table_file (sort @tables) {
    my $header = "<details><summary>:open_file_folder: $table_file</summary>\n\n".
        "token|path\n".
        "-|-\n";
    my $header_length = length $header;
    my $file_path = "$summary_tables/$table_file";
    my $cost = $header_length + $footer_length + -s $file_path;
    if ($budget && ($budget < $cost)) {
        print STDERR "::warning title=summary-table::Details for '$table_file' too big to include in Step Summary. (summary-table-skipped)\n";
        next;
    }
    open $table, "<", $file_path;
    my @entries;
    my $real_cost = $header_length + $footer_length;
    foreach my $line (<$table>) {
        $real_cost += length $line;
        push @entries, $line;
    }
    close $table;
    if ($real_cost > $cost) {
        print STDERR "budget ($real_cost > $cost)\n";
        if ($budget && ($budget < $real_cost)) {
            print STDERR "::warning title=summary-tables::budget exceeded for $table_file (summary-table-skipped)\n";
            next;
        }
    }
    print $header;
    print join ("", sort CheckSpelling::Util::case_biased @entries);
    print $footer;
    if ($budget) {
        $budget -= $cost;
        print STDERR "Summary Tables budget reduced to: $budget\n";
    }
}
print $suffix;
