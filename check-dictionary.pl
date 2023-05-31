#!/usr/bin/env perl
open WARNINGS, ">>", $ENV{early_warnings};
my $file = $ARGV[0];
open FILE, "<", $file;
$/ = undef;
my $content = <FILE>;
close FILE;
open FILE, ">", $file;

$ENV{comment_char} = '$^' unless $ENV{comment_char} =~ /\S/;

my $first_end = undef;
my $messy = 0;
$. = 0;
while ($content =~ s/([^\r\n\x0b\f\x85\x{2028}\x{2029}]*)(\r\n|\n|\r|\x0b|\f|\x85|\x{2028}|\x{2029})//m) {
    ++$.;
    my ($line, $end) = ($1, $2);
    unless (defined $first_end) {
        $first_end = $end;
    } elsif ($end ne $first_end) {
        print WARNINGS "$file:$.:$-[0] ... $+[0], Warning - entry has inconsistent line ending (unexpected-line-ending)\n";
    }
    if ($line =~ /^.*?($ENV{expected_chars}+)/) {
        my ($left, $right) = ($-[1] + 1, $+[1] + 1);
        my $column_range="$left ... $right";
        unless ($line =~ /^$ENV{comment_char}/) {
            print WARNINGS "$file:$.:$column_range, Warning - ignoring entry because it contains non-alpha characters (non-alpha-in-dictionary)\n";
        }
        $line = "";
    }
    print FILE "$line\n";
}
print FILE $content;
close WARNINGS;
