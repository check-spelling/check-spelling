#!/bin/bash
Q='"'
q="'"
generate_instructions() {
  instructions=$(mktemp)
  echo 'pushd $(git rev-parse --show-toplevel)' >> $instructions
  to_retrieve_expect >> $instructions
  if [ -n "$patch_remove" ]; then
    if [ -z "$expect_files" ]; then
      expect_files=$expect_file
    fi
    echo 'perl -e '$q'
my @expect_files=qw('$q$Q"$expect_files"$Q$q');
@ARGV=@expect_files;
my @stale=qw('$q$Q"$patch_remove"$Q$q');
my $re=join "|", @stale;
my $suffix=".".time();
my $previous="";
sub maybe_unlink { unlink($_[0]) if $_[0]; }
while (<>) {
  if ($ARGV ne $old_argv) { maybe_unlink($previous); $previous="$ARGV$suffix"; rename($ARGV, $previous); open(ARGV_OUT, ">$ARGV"); select(ARGV_OUT); $old_argv = $ARGV; }
  next if /^(?:$re)(?:(?:\r|\n)*$| .*)/; print;
}; maybe_unlink($previous);'$q >> $instructions
  fi
  if [ -n "$patch_add" ]; then
    echo 'perl -e '$q'
my $new_expect_file="'$new_expect_file'";
use File::Path qw(make_path);
make_path "'$(dirname $new_expect_file)'";
open FILE, q{<}, $new_expect_file; chomp(my @words = <FILE>); close FILE;
my @add=qw('$q$Q"$patch_add"$Q$q');
my %items; @items{@words} = @words x (1); @items{@add} = @add x (1);
@words = sort {lc($a) cmp lc($b)} keys %items;
open FILE, q{>}, $new_expect_file; for my $word (@words) { print FILE "$word\n" if $word =~ /\w/; };
close FILE;'$q >> $instructions
  fi
  echo 'popd' >> $instructions
  echo $instructions
}
