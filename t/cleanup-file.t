#!/usr/bin/env -S perl -Ilib

use strict;
use warnings;

use Cwd qw/ abs_path getcwd realpath /;
use File::Copy;
use File::Temp qw/ tempfile tempdir /;
use File::Basename;
use Test::More;
use Capture::Tiny ':all';

plan tests => 8;

my $spellchecker = dirname(dirname(abs_path(__FILE__)));

my $sandbox = tempdir();
$ENV{PERL5OPT} = '-MDevel::Cover';
$ENV{GITHUB_WORKSPACE} = $sandbox;
chdir $sandbox;
my ($fh, $temp) = tempfile();
close $temp;
$ENV{maybe_bad} = $temp;
my ($stdout, $stderr, @results);
($stdout, $stderr, @results) = capture {
  system("$spellchecker/cleanup-file.pl");
};

my $sandbox_name = basename $sandbox;
my $temp_name = basename $temp;
like($stdout, qr!::error ::Configuration files must live within .*?$sandbox_name\.\.\.!, 'cleanup-file.pl (stdout) sandbox');
like($stdout, qr!::error ::Unfortunately, file [\w/]+?/$temp_name appears to reside elsewhere\.!, 'cleanup-file.pl (stdout) temp');
is($stderr, '', 'cleanup-file.pl (stderr)');
my $result = $results[0] >> 8;
is($result, 3, 'cleanup-file.pl (exit code)');

my $git_dir = "$sandbox/.git";
mkdir $git_dir;
my $git_child = "$sandbox/.git/bad";
$ENV{maybe_bad} = $git_child;

($stdout, $stderr, @results) = capture {
  system("$spellchecker/cleanup-file.pl");
};
like($stdout, qr!::error ::Configuration files must not live within \`\.git/\`\.\.\.!, 'cleanup-file.pl (stdout) sandbox');
like($stdout, qr!::error ::Unfortunately, file [\w/]+?/\.git/bad appears to\.!, 'cleanup-file.pl (stdout) temp');
is($stderr, '', 'cleanup-file.pl (stderr)');
$result = $results[0] >> 8;
is($result, 4, 'cleanup-file.pl (exit code)');
