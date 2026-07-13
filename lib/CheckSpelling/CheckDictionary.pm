#! -*-perl-*-

package CheckSpelling::CheckDictionary;
use CheckSpelling::Util;

sub process_line {
    my ($line) = @_;
    $line =~ s/$ENV{comment_char}.*//;
    my $ignore_pattern = $ENV{INPUT_IGNORE_PATTERN} || '';
    if ($ignore_pattern ne '' && $line =~ /^.*?($ignore_pattern+)/) {
        my ($left, $right) = ($-[1] + 1, $+[1] + 1);
        my $wrapped = CheckSpelling::Util::wrap_in_backticks($1);
        my $column_range="$left ... $right";
        return ('', "$column_range, Warning - Ignoring entry because it contains non-alpha characters - $wrapped (non-alpha-in-dictionary)\n");
    }
    return ($line, '');
}

1;
