#!/usr/bin/env -S perl -Ilib

use strict;
use warnings;

use Cwd qw/ abs_path getcwd realpath /;
use File::Copy;
use File::Temp qw/ tempfile tempdir /;
use File::Basename;
use Test::More;
use Capture::Tiny ':all';

plan tests => 14;

our $spellchecker = dirname(dirname(abs_path(__FILE__)));

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
  our $spellchecker;
  $stdout =~ s!$spellchecker/apply\.pl!SPELLCHECKER/apply.pl!g;
  $stderr =~ s!$spellchecker/apply\.pl!SPELLCHECKER/apply.pl!g;
  $stdout =~ s!Current apply script differs from '.*?/apply\.pl' \(locally downloaded to \`.*`\)\. You may wish to upgrade\.\n!!;

  my $result = $results[0] >> 8;
  return ($stdout, $stderr, $result);
}
($stdout, $stderr, $result) = run_apply("$spellchecker/apply.pl", 'check-spelling/check-spelling', 6117093644);

my $sandbox_name = basename $sandbox;
my $temp_name = basename $temp;
is($stdout, "SPELLCHECKER/apply.pl: GitHub Run Artifact expired. You will need to trigger a new run.
", 'apply.pl (stdout) expired');
is($stderr, '', 'apply.pl (stderr) expired');
is($result, 1, 'apply.pl (exit code) expired');

my $gh_token = $ENV{GH_TOKEN};
delete $ENV{GH_TOKEN};
my $real_home = $ENV{HOME};
my $real_http_socket = `gh config get http_unix_socket`;
$ENV{HOME} = $sandbox;
($stdout, $stderr, $result) = run_apply("$spellchecker/apply.pl", 'check-spelling/check-spelling', 6117093644);

like($stdout, qr{gh auth login|set the GH_TOKEN environment variable}, 'apply.pl (stdout) not authenticated');
like($stderr, qr{SPELLCHECKER/apply.pl requires a happy gh, please try 'gh auth login'}, 'apply.pl (stderr) not authenticated');
is($result, 1, 'apply.pl (exit code) not authenticated');
$ENV{GH_TOKEN} = $gh_token;

if (-d "$real_home/.config/gh/") {
  mkdir "$sandbox/.config";
  `rsync -a '$real_home/.config/gh/' '$sandbox/.config/gh/'`;
}

`gh config set http_unix_socket /dev/null`;
($stdout, $stderr, $result) = run_apply("$spellchecker/apply.pl", 'check-spelling/check-spelling', 6117093644);

like($stdout, qr{SPELLCHECKER/apply.pl: Unix http socket is not working\.}, 'apply.pl (stdout) bad_socket');
like($stdout, qr{http_unix_socket: /dev/null}, 'apply.pl (stdout) bad_socket');
is($stderr, '', 'apply.pl (stderr) bad_socket');
is($result, 7, 'apply.pl (exit code) bad_socket');
$ENV{HOME} = $real_home;

`gh config set http_unix_socket '$real_http_socket'`;

$ENV{https_proxy}='http://localhost:9123';
($stdout, $stderr, $result) = run_apply("$spellchecker/apply.pl", 'check-spelling/check-spelling', 6117093644);

like($stdout, qr{SPELLCHECKER/apply.pl: Proxy is not accepting connections\.}, 'apply.pl (stdout) bad_proxy');
like($stdout, qr{https_proxy: 'http://localhost:9123'}, 'apply.pl (stdout) bad_proxy');
is($stderr, '', 'apply.pl (stderr) bad_proxy');
is($result, 6, 'apply.pl (exit code) bad_proxy');
