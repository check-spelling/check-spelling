#! -*-perl-*-

package CheckSpelling::CheckDictionary;
use CheckSpelling::Util;

sub init {
   our $comment_char = CheckSpelling::Util::get_file_from_env_utf8('comment_char');
   our $ignore_pattern = CheckSpelling::Util::get_file_from_env_utf8('INPUT_IGNORE_PATTERN') || '';
}

sub process_line {
    my ($line) = @_;
    our ($comment_char, $ignore_pattern);
    $line =~ s/$comment_char.*//;
    if ($ignore_pattern ne '' && $line =~ /^.*?($ignore_pattern+)/) {
        my ($left, $right) = ($-[1] + 1, $+[1] + 1);
        my $wrapped = CheckSpelling::Util::wrap_in_backticks($1);
        my $column_range="$left ... $right";
        return ('', "$column_range, Warning - Ignoring entry because it contains non-alpha characters - $wrapped (non-alpha-in-dictionary)\n");
    }
    return ($line, '');
}

1;
