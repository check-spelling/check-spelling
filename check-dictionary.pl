#!/usr/bin/env perl
open WARNINGS, ">>:encoding(UTF-8)", $ENV{early_warnings};
my $file = $ARGV[0];
open FILE, "<:encoding(UTF-8)", $file;
$/ = undef;
my $content = <FILE>;
close FILE;
open FILE, ">:encoding(UTF-8)", $file;

$ENV{comment_char} = '$^' unless $ENV{comment_char} =~ /\S/;

my $first_end = undef;
my $messy = 0;
$. = 0;

sub process_line {
    my ($file, $line) = @_;
    if ($line =~ /^.*?($ENV{INPUT_IGNORE_PATTERN}+)/) {
        my ($left, $right) = ($-[1] + 1, $+[1] + 1);
        my $column_range="$left ... $right";
        unless ($line =~ /^$ENV{comment_char}/) {
            print WARNINGS "$file:$.:$column_range, Warning - Ignoring entry because it contains non-alpha characters. (non-alpha-in-dictionary)\n";
        }
        $line = "";
    }
    return $line;
}

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
    $line = process_line($file, $line);
    print FILE "$line\n";
}
if ($remainder ne '') {
    $remainder = process_line($file, $remainder);
    print FILE $remainder;
}
close WARNINGS;
