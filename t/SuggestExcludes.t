#!/usr/bin/env -S perl -T -w -Ilib

use strict;
use warnings;
use utf8;

use File::Basename;
use File::Temp qw/ tempfile /;
use Test::More;
use CheckSpelling::Util;

plan tests => 5;
use_ok('CheckSpelling::SuggestExcludes');

my $tests = dirname(__FILE__);
my $base = dirname($tests);

sub fill_file {
  my ($delim, $list) = @_;
  my ($fh, $file) = tempfile();
  print $fh CheckSpelling::Util::list_with_terminator $delim, @{$list};
  close $fh;
  return $file;
}

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
  gamma-delta/go.md
  gamma-delta/README.md
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
my $list = fill_file("\0", \@files);

my @excludes = qw (
  a/ignore
  test/.keep
  case/.keep
  gamma-delta/go.md
  case/ignore
  Ignore.me.md
  flour/wine
  flour/grapes
  flour/meal
  flour/wheat
  flour/eggs
  flour/cream
  flour/rice
  flour/meat
  ignored
);
my $excludes_file = fill_file("\n", \@excludes);

my @old_excludes = qw <
  ^test\.keep$
  ^\Qtest(0)a\E$
>;
my $old_excludes_file = fill_file("\n", \@old_excludes);

my @expected_results = qw(
(?:^|/)\.keep$
^gamma-delta/go\.md$
^\QIgnore.me.md\E$
(?:^|/)ignore$
^ignored$
);
push @expected_results, '(?:|$^ 88% - excluded 8/9)^flour/';
@expected_results = sort CheckSpelling::Util::case_biased @expected_results;

my @expect_drop_patterns = qw(
^test\.keep$
^\Qtest(0)a\E$
);
@expect_drop_patterns = sort CheckSpelling::Util::case_biased @expect_drop_patterns;

my ($results_ref, $drop_ref) = CheckSpelling::SuggestExcludes::main($list, $excludes_file, $old_excludes_file);
my @results = @{$results_ref};
my @drop_patterns = sort CheckSpelling::Util::case_biased @{$drop_ref};
@results = sort CheckSpelling::Util::case_biased @results;
is(CheckSpelling::Util::list_with_terminator("\n", @results),
CheckSpelling::Util::list_with_terminator("\n", @expected_results));
is(CheckSpelling::Util::list_with_terminator("\n", @drop_patterns),
CheckSpelling::Util::list_with_terminator("\n", @expect_drop_patterns));

is(CheckSpelling::SuggestExcludes::path_to_pattern('a'), '^\Qa\E$');

@files = qw(
a-b/@t/1
a-b/@t/2/3
a-b/@t/4
a-b/1
a-b/2
a-b/3
a-b/4
);
$list = fill_file("\0", \@files);

@excludes = qw(
a-b/@t/1
a-b/@t/2/3
a-b/@t/4
);
$excludes_file = fill_file("\n", \@excludes);

@old_excludes = qw();
$old_excludes_file = fill_file("\n", \@old_excludes);

($results_ref, $drop_ref) = CheckSpelling::SuggestExcludes::main($list, $excludes_file, $old_excludes_file);
@results = @{$results_ref};
@results = sort CheckSpelling::Util::case_biased @results;
@expected_results = qw(
^a-b/@t/
);
is(CheckSpelling::Util::list_with_terminator("\n", @results),
CheckSpelling::Util::list_with_terminator("\n", @expected_results));
