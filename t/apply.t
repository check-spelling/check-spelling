#!/usr/bin/env -S perl -Ilib

use strict;
use warnings;

use Cwd qw/ abs_path getcwd realpath /;
use File::Copy;
use File::Temp qw/ tempfile tempdir /;
use File::Basename;
use Test::More;
use Capture::Tiny ':all';

plan tests => 3;

my $spellchecker = dirname(dirname(abs_path(__FILE__)));

my $sandbox = tempdir();
chdir($sandbox);
$ENV{PERL5OPT} = '-MDevel::Cover';
$ENV{GITHUB_WORKSPACE} = $sandbox;
my ($fh, $temp) = tempfile();
close $temp;
$ENV{maybe_bad} = $temp;
my ($stdout, $stderr, $result);

sub run_apply {
  my @args = @_;
  my ($stdout, $stderr, @results) = capture {
    system(@args);
  };
  $stdout =~ s!Current apply script differs from '.*?/apply\.pl' \(locally downloaded to \`.*`\)\. You may wish to upgrade\.\n!!;

  my $result = $results[0] >> 8;
  return ($stdout, $stderr, $result);
}
($stdout, $stderr, $result) = run_apply("$spellchecker/apply.pl", 'check-spelling/check-spelling', 6117093644);

my $sandbox_name = basename $sandbox;
my $temp_name = basename $temp;
is($stdout, "$spellchecker/apply.pl: GitHub Run Artifact expired. You will need to trigger a new run.
", 'apply.pl (stdout) expired');
is($stderr, '', 'apply.pl (stderr) expired');
is($result, 1, 'apply.pl (exit code) expired');
