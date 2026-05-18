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

my @paths = qw(/usr/bin /bin);
if (CheckSpelling::Util::get_val_from_env('INPUT_CHECK_IMAGES', '') =~ /^(?:1|true)$/i) {
  $ENV{PATH} =~ /(.*)/;
  my $path = $1;
  for my $dir (split /:/, $path) {
    if (-x "$dir/tesseract") {
      push @paths, $dir;
      last;
    }
  }
}
$ENV{PATH} = join ':', @paths;

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
