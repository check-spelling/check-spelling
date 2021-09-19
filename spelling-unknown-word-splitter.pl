#!/usr/bin/perl -wT

use 5.022;
use feature 'unicode_strings';
use strict;
use warnings;
use Encode qw/decode_utf8 FB_DEFAULT/;
use Cwd 'abs_path';
use File::Basename;
use CheckSpelling::UnknownWordSplitter;

binmode STDIN;
binmode STDOUT, ':utf8';

# skip files that don't exist (including dangling symlinks)
if (scalar @ARGV) {
  @ARGV = grep {! -l && -f && -r} @ARGV;
  unless (scalar @ARGV) {
    print STDERR "::warning ::Was not provided any regular readable files\n";
    exit 0;
  }
}

my $dirname = dirname(abs_path(__FILE__));
CheckSpelling::UnknownWordSplitter::init($dirname);
CheckSpelling::UnknownWordSplitter::main($dirname, @ARGV);
