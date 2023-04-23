#!/usr/bin/env -S perl -T

use warnings;
use File::Basename;
use CheckSpelling::SuggestExcludes;
use CheckSpelling::Util;

my $dirname = dirname(__FILE__);
my ($should_exclude_patterns) = CheckSpelling::Util::get_file_from_env('should_exclude_patterns', undef);
die "$0 requires \$should_exclude_patterns" unless defined $should_exclude_patterns;
open NEW_PATTERNS_FILE, '>', $should_exclude_patterns;
my ($results_ref, $drop_ref) = CheckSpelling::SuggestExcludes::main(
  $ENV{file_list},
  $ENV{should_exclude_file},
  $ENV{current_exclude_patterns},
);
my @new_patterns = @{$results_ref};
my @drop_patterns = @{$drop_ref};
print NEW_PATTERNS_FILE CheckSpelling::Util::list_with_terminator(
  "\n",
  @new_patterns
);
close NEW_PATTERNS_FILE;
my $remove_excludes_file = CheckSpelling::Util::get_file_from_env('remove_excludes_file', undef);
if (defined $remove_excludes_file) {
  open DROP_PATTERNS_FILE, '>', $remove_excludes_file;
  print DROP_PATTERNS_FILE CheckSpelling::Util::list_with_terminator(
    "\n",
    @drop_patterns
  );
  close DROP_PATTERNS_FILE;
}
