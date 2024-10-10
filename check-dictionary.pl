#!/usr/bin/env perl

use Cwd 'realpath';
use File::Spec;
use CheckSpelling::Util;
use CheckSpelling::CheckDictionary;

open WARNINGS, ">>:encoding(UTF-8)", CheckSpelling::Util::get_file_from_env('early_warnings', '/dev/stderr');
$ARGV[0] =~ /^(.*)/;
my $file = $1;
open FILE, "<:encoding(UTF-8)", $file;
$/ = undef;
my $content = <FILE>;
close FILE;
open FILE, ">:encoding(UTF-8)", $file;

$file = File::Spec->abs2rel(realpath($file));

$ENV{comment_char} = '$^' unless $ENV{comment_char} =~ /\S/;

my $first_end = undef;
my $messy = 0;
$. = 0;

my $remainder;
if ($content !~ /(?:\r\n|\n|\r|\x0b|\f|\x85|\x{2028}|\x{2029})$/) {
    $remainder = $1 if $content =~ /([^\r\n\x0b\f\x85\x{2028}\x{2029}]+)$/;
}
while ($content =~ s/([^\r\n\x0b\f\x85\x{2028}\x{2029}]*)(\r\n|\n|\r|\x0b|\f|\x85|\x{2028}|\x{2029})//m) {
    ++$.;
    my ($line, $end) = ($1, $2);
    unless (defined $first_end) {
        $first_end = $end;
    } elsif ($end ne $first_end) {
        print WARNINGS "$file:$.:$-[0] ... $+[0], Warning - Entry has inconsistent line ending. (unexpected-line-ending)\n";
    }
    my ($line, $warning) = CheckSpelling::CheckDictionary::process_line($file, $line);
    if ($warning ne '') {
        print WARNINGS $warning;
    } elsif ($line ne '') {
        print FILE "$line\n";
    }
}
if ($remainder ne '') {
    $remainder = CheckSpelling::CheckDictionary::process_line($file, $remainder);
    print FILE $remainder;
}
close WARNINGS;
