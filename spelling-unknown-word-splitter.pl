#!/usr/bin/env -S perl -T

use 5.022;
use feature 'unicode_strings';
use strict;
use warnings;
use Encode qw/decode_utf8 FB_DEFAULT/;
use Cwd 'abs_path';
use File::Basename;
use CheckSpelling::UnknownWordSplitter;
use CheckSpelling::Util;

binmode STDIN;
binmode STDOUT, ':utf8';

$ENV{PATH} = '/usr/bin:/bin';

exit 0 unless scalar @ARGV;

# skip files that don't exist (including dangling symlinks)
my @files = grep {! -l && -f && -r} @ARGV;
unless (scalar @files) {
  print STDERR "::warning ::Was not provided any regular readable files\n";
  print STDERR join "\n", @ARGV;
  print STDERR "\n";
  exit 0;
}

my $configuration = CheckSpelling::Util::get_file_from_env('splitter_configuration', dirname(abs_path(__FILE__)));
CheckSpelling::UnknownWordSplitter::init($configuration);
CheckSpelling::UnknownWordSplitter::main($configuration, @files);
