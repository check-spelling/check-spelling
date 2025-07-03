#!/usr/bin/env -S perl -w -Ilib

use strict;
use warnings;

use Cwd qw(abs_path getcwd realpath);
use File::Basename;
use File::Copy;
use File::Temp qw(tempfile tempdir);
use File::Path qw(make_path);
use Test::More;
use Capture::Tiny ':all';

plan tests => 22;

my $working_directory = getcwd();
my $sandbox = $working_directory;

my $repository_owner = 'GITHUB_REPOSITORY_OWNER';
my $github_repository_name = 'GITHUB_REPOSITORY_NAME';
my $github_repository = $ENV{GITHUB_REPOSITORY} || 'check-spelling/check-spelling';

system(qw(git remote rename origin origin.real));
system(qq(git remote add origin https://github.com/$repository_owner/$github_repository_name --no-tags));

my @environment_variables_to_drop = split /\n/, `git ls-files -z |
  xargs -0 grep GITHUB_ 2>/dev/null |
  perl -pe 's/[^_A-Z]+/\n/g' |
  grep ^GITHUB_ |
  sort -u`;
push @environment_variables_to_drop, 'ACT';

for my $key (@environment_variables_to_drop) {
  delete $ENV{$key};
}

$ENV{GITHUB_SERVER_URL} = 'https://github.com';
$ENV{GITHUB_RUN_ID} = 7515;
$ENV{GITHUB_REPOSITORY} = $github_repository;
$ENV{GITHUB_REPOSITORY_OWNER} = $repository_owner;
$ENV{GITHUB_REPOSITORY_NAME} = $github_repository_name;

system(qw(git config user.email check-spelling-bot@users.noreply.github.com));
system(qw(git config user.name check-spelling-bot));

`perl -MDevel::Cover -e 1 2>&1`;
$ENV{PERL5OPT} = '-MDevel::Cover' unless $?;

sub cleanup {
  my ($text, $working_directory, $sandbox, $github_repository, $internal_state_directory) = @_;
  if (defined $internal_state_directory) {
    $text =~ s/ $/=/gm;
    $text =~ s!'/[^']*?/artifact.zip!'ARTIFACT_DIRECTORY/artifact.zip!g;
    $text =~ s/\Q$internal_state_directory\E/INTERNAL_STATE_DIRECTORY/g;
    if ($text =~ m{git am <<'\@\@\@\@([0-9a-f]{40}--\d+)'}) {
      my $am_marker = $1;
      $text =~ s/\Q$am_marker\E/AM_MARKER/g;
      $text =~ s/^From [0-9a-f]{40} Mon Sep 17 00:00:00 2001/From COMMIT_SHA Mon Sep 17 00:00:00 2001/gm;
      $text =~ s/^Date: (?:Sun|Mon|Tue|Wed|Thu|Fri|Sat), \d+ (?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec) \d+ \d+:\d+:\d+ [-+]\d+/Date: COMMIT_DATE/gm;
      $text =~ s/\n--=\n2\.\d+\.\d+\n/\n--=\nGIT_VERSION\n/;
    }
    if ($text =~ m{create mode 100644 .github/actions/spelling/expect/([0-9a-f]{3})([0-9a-f]{37})\.txt}) {
      my ($sha_prefix, $sha_suffix) = ($1, $2);
      $text =~ s/\Q$sha_prefix$sha_suffix\E/EXPECT_FULL_SHA/g;
      $text =~ s/\.\.\.$sha_suffix/\.\.\.ELIPSIS_EXPECT_SHA/g;
    }
    $text =~ s/^ \.\.\.[0-9a-f]{38}(\.txt \| \d+ [+]+)/ ...ELIPSIS_EXPECT_SHA$1/gm;
    # The README.md.txt file can sort before or after the new expect file and we don't actually care about it, as it's a fixed value.
    # First we remove the diff stat line
    $text =~ s!^ \.github/actions/spelling/expect/README\.md\.txt\s+\|\s+1 -\n!!m;
    # The README.md.txt file can sort before or after the new expect file and we don't actually care about it, as it's a fixed value.
    # Then we remove the diff itself.
    $text =~ s!^diff --git a/\.github/actions/spelling/expect/README\.md\.txt b/\.github/actions/spelling/expect/README\.md\.txt\nindex [0-9a-f]{6,}\.\.[0-9a-f]{6,} 100644\n--- a/\.github/actions/spelling/expect/README\.md\.txt\n\+\+\+ b/\.github/actions/spelling/expect/README\.md\.txt\n\@\@ -1,3 \+1,2 \@\@\n gsutil\n spammed\n-workflows\n!!gm;
    $text =~ s/^index 0+\.\.[0-9a-f]{6,}$/index GIT_DIFF_NEW_FILE/gm;
    $text =~ s/^index [0-9a-f]{6,}\.\.[0-9a-f]{6,} 100644$/index GIT_DIFF_CHANGED_FILE/gm;
  }
  $text =~ s!\Qraw.githubusercontent.com/check-spelling/check-spelling\E!raw.githubusercontent.com/CHECK-SPELLING/CHECK-SPELLING!g;
  $text =~ s!$ENV{GITHUB_SERVER_URL}!GITHUB_SERVER_URL!g;
  $text =~ s!$ENV{GITHUB_RUN_ID}!GITHUB_RUN_ID!g;
  $text =~ s!in a clone of the \[.*?\]\(.*?\) repository!in a clone of the [GITHUB_REPOSITORY_OWNER/GITHUB_REPOSITORY_NAME](GITHUB_SERVER_URL/GITHUB_REPOSITORY_OWNER/GITHUB_REPOSITORY_NAME) repository!g;
  $text =~ s!^Devel::Cover: Deleting old coverage for changed file .*$!!m;
  $text =~ s!(locally downloaded to )\`.*?\`!$1...!;
  $text =~ s/^Installed: .*\n//g;
  $text =~ s/\Q$sandbox\E/WORKSPACE/g;
  $text =~ s!/tmp/check-spelling!TEMP_DIRECTORY!g;
  my $github_sha = $ENV{GITHUB_SHA} || `git rev-parse HEAD`;
  $github_sha =~ s/\n|\r//g;
  $text =~ s/$github_sha/GITHUB_SHA/g;
  $text =~ s/\Q$working_directory\E/ENGINE/g;
  $text =~ s!\Q$github_repository\E!GITHUB_REPOSITORY_OWNER/GITHUB_REPOSITORY_NAME!g if $github_repository !~ /^\.?$/;
  $text =~ s!\QTEMP_DIRECTORY/./\E!TEMP_DIRECTORY/GITHUB_REPOSITORY_OWNER/GITHUB_REPOSITORY_NAME/!g if $github_repository eq '.';
  $text =~ s/on the \`[^`]+?\` branch/on the \`GITHUB_BRANCH\` branch/g;
  $text =~ s!\S*(\Q/expect.words.txt\E)!EXPECT_SANDBOX$1!gm;
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

sub extra_cleanup {
  my ($stderr, $stdout, @cleanup_arguments) = @_;
  $stderr = cleanup($stderr, @cleanup_arguments);
  $stderr =~ s<dict.txt \(to \S+\)><dict.txt (to ...)>;

  $stderr =~ s/Installed: [-\w]+\n//;
  $stderr =~ s/Summary Tables budget: \d+/Summary Tables budget: INITIAL_BUDGET/;
  $stderr =~ s/Summary Tables budget reduced to: \d+/Summary Tables budget reduced to: REDUCED_BUDGET/g;

  $stdout =~ s!the \Q[.](.)\E repository!the [https://github.com/GITHUB_REPOSITORY_OWNER/GITHUB_REPOSITORY_NAME](https://github.com/GITHUB_REPOSITORY_OWNER/GITHUB_REPOSITORY_NAME) repository!;

  $stdout = cleanup($stdout, @cleanup_arguments);
  return ($stderr, $stdout);
}

sub test {
my ($sandbox, $instance) = @_;

my $config = "$sandbox/t/$instance/config";

$ENV{INPUTS} = qq<{
  "check_file_names" : 1,
  "config": "$config",
  "check_extra_dictionaries": " ",
  "extra_dictionaries": " ",
  "": "ignored-empty",
  "ignoredEmpty": "",
  "ignoredValue":
  "github_pat_ignored",
  "ignored_key": "ignored",
  "ignored item": "ignored",
  "unused": "unused",
  "conflicting-item": 1,
  "conflicting_item": 2
}>;

my ($fh, $github_step_summary) = tempfile();
close $fh;
$ENV{GITHUB_STEP_SUMMARY} = $github_step_summary;

my $github_output;
($fh, $github_output) = tempfile();
$ENV{GITHUB_OUTPUT} = $github_output;

my ($stdout, $stderr, @results);
($stdout, $stderr, @results) = capture {
  system("$working_directory/unknown-words.sh")
};

my @cleanup_arguments = ($working_directory, $sandbox, $github_repository);
my $outputs = "$working_directory/t/$instance/output";
my $run = "$sandbox/t/$instance/run";
my $expected_stdout = read_file("$outputs/output.txt", @cleanup_arguments);
my $expected_stderr = read_file("$outputs/error.txt", @cleanup_arguments);
my $expected_summary = read_file("$outputs/summary.md", @cleanup_arguments);
my $expected_warnings = read_file("$outputs/warnings.txt", @cleanup_arguments);
my $expected_stale_words = read_file("$outputs/stale.txt", @cleanup_arguments);

my $output = read_file($github_output, @cleanup_arguments);

my $followup = retrieve_value('followup', $output);
my $internal_state_directory = retrieve_value('internal_state_directory', $output);
my $result_code = retrieve_value('result_code', $output);
my $unknown_words_path = retrieve_value('unknown_words', $output);
my $warnings_path = retrieve_value('warnings', $output);
my $stale_words_path = retrieve_value('stale_words', $output);

push @cleanup_arguments, $internal_state_directory;

($stderr, $stdout) = extra_cleanup($stderr, $stdout, @cleanup_arguments);

my $result = $results[0] >> 8;
is($result, 1, "$instance: exit code");
is($result_code, 1, "$instance: result_code");
is($followup, 'comment', "$instance: followup");

unless (defined $internal_state_directory) {
  is($internal_state_directory, "$instance: internal_state_directory");
} else {
  my $artifact = glob("$internal_state_directory/*.zip");
  isnt($artifact, '', "$instance: internal_state_directory - should have a zip file");
}

make_path($run);

write_file("$run/output.txt", $stdout);

my @stdout = split /\n/, $stdout;
my @expected_stdout = split /\n/, $expected_stdout;
is_deeply(\@stdout, \@expected_stdout, "$instance: stdout");

like($stderr, qr{^\QFound conflicting inputs for conflicting-item (1): conflicting_item (2) (migrate-underscores-to-dashes)\E$}m, "$instance: stderr conflicts");
like($stderr, qr{^\QCensoring `ignoredValue` (unexpected-input-value)\E}m, , "$instance: stderr censored");
$stderr =~ s{^\QFound conflicting inputs for conflicting-item (1): conflicting_item (2) (migrate-underscores-to-dashes)\E$}{}m;
$stderr =~ s{^\QCensoring `ignoredValue` (unexpected-input-value)\E$}{}m;
write_file("$run/error.txt", $stderr);
is($stderr, $expected_stderr, "$instance: stderr");

my $summary = read_file($github_step_summary, @cleanup_arguments);
$summary =~ s!\QCurrent apply script differs from 'https://raw.githubusercontent.com/CHECK-SPELLING/CHECK-SPELLING/\E[^']+?\Q/apply.pl' (locally downloaded to ...). You may wish to upgrade.\E\n!!;

write_file("$run/summary.md", $summary);

my @summary_list = split /\n/, $summary;
my @expected_summary_list = split /\n/, $expected_summary;
is_deeply(\@summary_list, \@expected_summary_list, "$instance: GITHUB_STEP_SUMMARY");

my $warning_content = read_file($warnings_path, @cleanup_arguments);

write_file("$run/warnings.txt", $warning_content);
is($warning_content, $expected_warnings, "$instance: warnings");

my $stale = '???';

if (defined $stale_words_path) {
  unless (-f $stale_words_path) {
    my $stale_words_path_filename = basename $stale_words_path;
    my $archive_dir = tempdir();
    `cd "$archive_dir"; unzip "$internal_state_directory/*.zip"`;
    $stale_words_path = "$archive_dir/$stale_words_path_filename";
  }
  $stale = read_file($stale_words_path, @cleanup_arguments);
}

write_file("$run/stale.txt", $stale);
is($stale, $expected_stale_words, "$instance: stale_words");

}

test($sandbox, 'unknown-words');

$ENV{GITHUB_HEAD_REF} = 'some-head';
$ENV{GITHUB_BASE_REF} = 'some-base';

test($sandbox, 'unknown-words.pr');

system(qw(git config --unset user.email));
system(qw(git config --unset user.name));
system(qw(git remote remove origin));
system(qw(git remote rename origin.real origin));
