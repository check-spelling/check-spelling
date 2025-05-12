#! -*-perl-*-

package CheckSpelling::CheckDictionary;

sub process_line {
    my ($file, $line) = @_;
    $line =~ s/$ENV{comment_char}.*//;
    my $ignore_pattern = $ENV{INPUT_IGNORE_PATTERN};
    if ($ignore_pattern ne '' && $line =~ /^.*?($ignore_pattern+)/) {
        my ($left, $right) = ($-[1] + 1, $+[1] + 1);
        my $column_range="$left ... $right";
        return ('', "$file:$.:$column_range, Warning - Ignoring entry because it contains non-alpha characters. (non-alpha-in-dictionary)\n");
    }
    return ($line, '');
}

1;
