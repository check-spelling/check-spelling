#!/usr/bin/env -S perl -T -Ilib

use strict;
use warnings;

use File::Basename;
use File::Temp qw/ tempfile /;
use Test::More;
use CheckSpelling::Util;

plan tests => 3;
use_ok('CheckSpelling::SuggestExcludes');

my $tests = dirname(__FILE__);
my $base = dirname($tests);

my ($fh, $list) = tempfile();
my @files = qw(
  test/.keep
  case/.keep
  case/README.md
  case/ignore
  README.md
  a/test/case
  a/q.go
  a/ignore
  b/test/file
  delta/go.md
  delta/README.md
  case
  Ignore.md
  flour/wine
  flour/grapes
  flour/meal
  flour/wheat
  flour/eggs
  flour/cream
  flour/rice
  flour/meat
  flour/flour/pie
  new/wine
  new/grapes
  new/meal
  new/wheat
  new/eggs
  new/cream
  new/rice
  new/meat
  new/pie
);
print $fh CheckSpelling::Util::list_with_terminator "\0", @files;
close $fh;

my $excludes_file;
($fh, $excludes_file) = tempfile();
my @excludes = qw (
  a/ignore
  test/.keep
  case/.keep
  delta/go.md
  case/ignore
  Ignore.md
  flour/wine
  flour/grapes
  flour/meal
  flour/wheat
  flour/eggs
  flour/cream
  flour/rice
  flour/meat
);
print $fh CheckSpelling::Util::list_with_terminator "\n", @excludes;
close $fh;

my $old_excludes_file;
($fh, $old_excludes_file) = tempfile();
my @old_excludes = qw (
  ^test\.keep$
);
print $fh CheckSpelling::Util::list_with_terminator "\n", @old_excludes;
close $fh;

my @expected_results = qw(
(?:^|/)\.keep$
^\Qdelta/go.md\E$
^\QIgnore.md\E$
(?:^|/)ignore$
);
push @expected_results, '(?:|$^ 88.89% - excluded 8/9)^flour/';
@expected_results = sort CheckSpelling::Util::case_biased @expected_results;

my @expect_drop_patterns = qw(
^test\.keep$
);
@expect_drop_patterns = sort CheckSpelling::Util::case_biased @expect_drop_patterns;

my ($results_ref, $drop_ref) = CheckSpelling::SuggestExcludes::main($list, $excludes_file, $old_excludes_file);
my @results = @{$results_ref};
my @drop_patterns = @{$drop_ref};
@results = sort CheckSpelling::Util::case_biased @results;
is(CheckSpelling::Util::list_with_terminator("\n", @results),
CheckSpelling::Util::list_with_terminator("\n", @expected_results));
is(CheckSpelling::Util::list_with_terminator("\n", @drop_patterns),
CheckSpelling::Util::list_with_terminator("\n", @expect_drop_patterns));
