#!/usr/bin/env -S perl -Ilib

use strict;
use warnings;

use Cwd qw(abs_path getcwd realpath);
use File::Basename;
use File::Copy "cp";
use File::Temp qw(tempfile tempdir);
use File::Path qw(make_path);
use Test::More;
use Capture::Tiny ':all';

plan tests => 9;

my ($fh, $github_step_summary) = tempfile();
close $fh;

my $working_directory = getcwd();
my $sandbox = $working_directory;
my $dictionaries_base_dir = tempdir();
my $config = "$sandbox/t/with-dictionaries/config";

cp(qw(
  t/with-dictionaries/unknown-words-server
  wrappers/unknown-words-server
));

my $github_repository = $ENV{GITHUB_REPOSITORY} || 'check-spelling/check-spelling';

my @environment_variables_to_drop = split /\n/, `git ls-files -z |
  xargs -0 grep GITHUB_ |
  perl -pe 's/[^_A-Z]+/\n/g' |
  grep ^GITHUB_ |
  sort -u`;
push @environment_variables_to_drop, 'ACT';

for my $key (@environment_variables_to_drop) {
  delete $ENV{$key};
}

$ENV{GITHUB_STEP_SUMMARY} = $github_step_summary;
$ENV{GITHUB_REPOSITORY} = $github_repository;

my $github_output;
($fh, $github_output) = tempfile();
$ENV{GITHUB_OUTPUT} = $github_output;

system(qw(git config user.email check-spelling-bot@users.noreply.github.com));
system(qw(git config user.name check-spelling-bot));

$ENV{PERL5OPT} = "-MDevel::Cover";
$ENV{INPUTS} = qq<{
  "config": "$config",
  "post_comment": 0,
  "cache-dictionaries": 0,
  "dictionary_url": "http://localhost:8123/basic.txt",
  "check_extra_dictionaries": " ",
  "extra_dictionaries": "http://localhost:8123/429.php http://localhost:8123/503.php http://localhost:8123/sample.txt"
}>;

my ($stdout, $stderr, @results);
($stdout, $stderr, @results) = capture {
  $ENV{PATH} = "$working_directory/wrappers:$ENV{PATH}";
  $ENV{spellchecker} = $working_directory;
  $ENV{dictionaries_base_dir} = $dictionaries_base_dir;
  $ENV{THIS_ACTION_PATH} = $working_directory;
  system("unknown-words-server")
};

sub cleanup {
  my ($text, $working_directory, $sandbox, $github_repository, $internal_state_directory) = @_;
  $text =~ s!\Qraw.githubusercontent.com/check-spelling/check-spelling\E/[^/]+/!raw\.githubusercontent\.com/CHECK-SPELLING/CHECK-SPELLING/BRANCH/!g;
  $text =~ s!in a clone of the \[.*?\]\(.*?\) repository!in a clone of the [https://github.com/GITHUB_REPOSITORY_OWNER/GITHUB_REPOSITORY_NAME](https://github.com/GITHUB_REPOSITORY_OWNER/GITHUB_REPOSITORY_NAME) repository!g;
  $text =~ s!^Devel::Cover: Deleting old coverage for changed file .*$!!m;
  $text =~ s!(locally downloaded to )\`.*?\`!$1...!;
  $text =~ s/\Q$sandbox\E/WORKSPACE/g;
  $text =~ s/\Q$working_directory\E/ENGINE/g;
  $text =~ s!\Q$github_repository\E!GITHUB_REPOSITORY_OWNER/GITHUB_REPOSITORY_NAME!g if $github_repository !~ /^\.?$/;
  if (defined $internal_state_directory) {
    $text =~ s/ $/=/gm;
    $text =~ s!'/[^']*?/artifact\.zip!'ARTIFACT_DIRECTORY/artifact.zip!g;
    $text =~ s/\Q$internal_state_directory\E/INTERNAL_STATE_DIRECTORY/g;
    if ($text =~ m{git am <<'\@\@\@\@([0-9a-f]{40}--\d+)'}) {
      my $am_marker = $1;
      $text =~ s/\Q$am_marker\E/AM_MARKER/g;
      $text =~ s/^From [0-9a-f]{40} Mon Sep 17 00:00:00 2001/From COMMIT_SHA Mon Sep 17 00:00:00 2001/gm;
      $text =~ s/^Date: (?:Sun|Mon|Tue|Wed|Thu|Fri|Sat), \d+ (?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec) \d+ \d+:\d+:\d+ [-+]\d+/Date: COMMIT_DATE/gm;
    }
    if ($text =~ m{create mode 100644 .github/actions/spelling/expect/([0-9a-f]{3})([0-9a-f]{37})\.txt}) {
      my ($sha_prefix, $sha_suffix) = ($1, $2);
      $text =~ s/\Q$sha_prefix$sha_suffix\E/EXPECT_FULL_SHA/g;
      $text =~ s/\Q...$sha_suffix\E/...ELIPSIS_EXPECT_SHA/g;
    }
    $text =~ s/^ \.\.\.[0-9a-f]{38}(\.txt \| \d+ [+]+)/ ...ELIPSIS_EXPECT_SHA$1/gm;
    # The README.md.txt file can sort before or after the new expect file and we don't actually care about it, as it's a fixed value.
    # First we remove the diff stat line
    $text =~ s!^ \Q.github/actions/spelling/expect/README.md.txt\E\s+\|\s+1 -\n!!m;
    # The README.md.txt file can sort before or after the new expect file and we don't actually care about it, as it's a fixed value.
    # Then we remove the diff itself.
    $text =~ s!^\Qdiff --git a/.github/actions/spelling/expect/README.md.txt b/.github/actions/spelling/expect/README.md.txt\E\nindex [0-9a-f]{6,}\.\.[0-9a-f]{6,} 100644\n\Q--- a/.github/actions/spelling/expect/README.md.txt\E\n\Q+++ b/.github/actions/spelling/expect/README.md.txt\E\n\Q@@ -1,4 +1,3 @@\E\n gsutil\n spammed\n timeframe\n-workflows\n!!gm;
    $text =~ s/^index 0+\.\.[0-9a-f]{6,}$/index GIT_DIFF_NEW_FILE/gm;
    $text =~ s/^index [0-9a-f]{6,}\.\.[0-9a-f]{6,} 100644$/index GIT_DIFF_CHANGED_FILE/gm;
  }
  return $text;
}

sub read_file {
  my ($file, $working_directory, $sandbox, $github_repository, $internal_state_directory) = @_;
  return unless $file;
  local $/ = undef;
  open my $fh, '<', $file || return;
  my $content = <$fh>;
  close $fh;
  return cleanup($content, $working_directory, $sandbox, $github_repository, $internal_state_directory);
}

sub write_file {
  my ($file, $content) = @_;
  open my $fd, '>', $file;
  print $fd $content if defined $content;
  close $fd;
}

sub retrieve_value {
  my ($key, $haystack) = @_;
  return unless $haystack =~ /^$key=(\S+)/m;
  return $1;
}

sub sort_lines {
  my ($content) = @_;
  my @lines = split /[\r\n]+/, $content;
  @lines = sort @lines;
  push @lines, '';
  return join "\n", @lines;
}

my @cleanup_arguments = ($working_directory, $sandbox, $github_repository);
my $outputs = "$working_directory/t/with-dictionaries/output";
my $run = "$sandbox/t/with-dictionaries/run";
my $expected_stdout = read_file("$outputs/output.txt", @cleanup_arguments);
my $expected_stderr = read_file("$outputs/error.txt", @cleanup_arguments);
my $expected_summary = read_file("$outputs/summary.md", @cleanup_arguments);
my $expected_warnings = read_file("$outputs/warnings.txt", @cleanup_arguments);

my $output = read_file($github_output, @cleanup_arguments);

my $followup = retrieve_value('followup', $output);
my $internal_state_directory = retrieve_value('internal_state_directory', $output);
my $result_code = retrieve_value('result_code', $output);
my $unknown_words_path = retrieve_value('unknown_words', $output);
my $warnings_path = retrieve_value('warnings', $output);
my $stale_words_path = retrieve_value('stale_words', $output);

push @cleanup_arguments, $internal_state_directory;

$stderr = cleanup($stderr, @cleanup_arguments);
$stderr =~ s<8123/basic\.txt \(to \S+\)><8123/basic\.txt (to ...)>;
$stderr =~ s/^\[(?:[A-Z][a-z]{2} ){2}[ \d]\d (\d+:){2}\d+\d+ \d+\]/DATESTAMP/gm;
$stderr =~ s/PHP \d+.*?( Development Server)/PHP PHP_VERSION$1/;
$stderr =~ s/^DATESTAMP \[.*?\]:\d+/DATESTAMP [LOCAL_ADDRESS]:PORT/gm;
$stderr =~ s/^Installed:.*\n//gm;

$stderr = sort_lines($stderr);

$stdout =~ s/^\[.*?\].*install(?:ed|ing).*\n//gm;
$stdout =~ s!the \Q[.](.)\E repository!the [https://github.com/GITHUB_REPOSITORY_OWNER/GITHUB_REPOSITORY_NAME](https://github.com/GITHUB_REPOSITORY_OWNER/GITHUB_REPOSITORY_NAME) repository!;

$stdout = cleanup($stdout, @cleanup_arguments);

my $result = $results[0] >> 8;
is($result, 0, 'unknown-words-server (exit code)');
is($result_code, 0, 'result_code');
is($followup, undef, 'followup');

unless (defined $internal_state_directory) {
  is($internal_state_directory, 'internal_state_directory');
} else {
  my $artifact = glob("$internal_state_directory/*.zip");
  isnt($artifact, '', 'internal_state_directory - should have a zip file');
}

make_path($run);

write_file("$run/output.txt", $stdout);
is($stdout, $expected_stdout, 'unknown-words-server (stdout)');

write_file("$run/error.txt", $stderr);
is($stderr, $expected_stderr, 'unknown-words-server (stderr)');

my $summary = read_file($github_step_summary, @cleanup_arguments);
$summary =~ s!\QCurrent apply script differs from 'https://raw.githubusercontent.com/CHECK-SPELLING/CHECK-SPELLING/\E[^']+?\Q/apply.pl' (locally downloaded to ...). You may wish to upgrade.\E\n!!;

write_file("$run/summary.md", $summary);
is($summary, $expected_summary, 'GITHUB_STEP_SUMMARY');

my $warning_content = read_file($warnings_path, @cleanup_arguments);

write_file("$run/warnings.txt", $warning_content);
is($warning_content, $expected_warnings, 'warnings');

my $stale = '???';

isnt(defined $stale_words_path, 'stale_words');

system(qw(git config --unset user.email));
system(qw(git config --unset user.name));
