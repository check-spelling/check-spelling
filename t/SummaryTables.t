#!/usr/bin/env -S perl -w -Ilib

use strict;
use warnings;

use Cwd qw();
use Test::More;
use File::Temp qw/ tempfile tempdir /;
use Capture::Tiny ':all';

plan tests => 20;
use_ok('CheckSpelling::SummaryTables');

is(CheckSpelling::SummaryTables::github_repo(
    'https://github.com/some/thing.git'), 'some/thing');
is(CheckSpelling::SummaryTables::github_repo(
    'git@github.com:some/thing'), 'some/thing');
is(CheckSpelling::SummaryTables::github_repo(
    '../some/thing'), '');
is(CheckSpelling::SummaryTables::file_ref(
    'file name', 20), 'file%20name:20');

my $git_dir = `sh -c 'dirname \$(which git)'`;
chomp $git_dir;
is(CheckSpelling::SummaryTables::find_git(), $git_dir);

$ENV{summary_budget} = 0;

my $origin = Cwd::cwd();

my $test_git_root = tempdir();

chdir $test_git_root;

my $owner_repo='https://github.com/owner/example';
my $other_repo='git@github.com:another/place.git';
my $name='first last';
my $email='first.last@example.com';
my $ref;
`
git init --initial-branch=main .;
git config user.name '$name';
git config user.email '$email';
git remote add origin '$owner_repo';
touch README.md;
git add README.md;
git commit -m README;
git clone -q . child;
GIT_DIR=child/.git git remote set-url origin '$other_repo';
echo >> README.md;
git commit -m blank;
`;

$ref = `git rev-parse HEAD`;
chomp $ref;
is(CheckSpelling::SummaryTables::github_blame(
    'README.md', 1), "https://github.com/owner/example/blame/$ref/README.md#L1");
$ref = `GIT_DIR=child/.git git rev-parse HEAD`;
chomp $ref;
is(CheckSpelling::SummaryTables::github_blame(
    'child/README.md', 1), "https://github.com/another/place/blame/$ref/README.md#L1");

my $oldIn = *ARGV;
my $text = 'file.yml:1:1 ... 1, Warning - Unsupported configuration: use_sarif needs security-events: write. (unsupported-configuration)
file.yml:2:1 ... 1, Warning - Unsupported configuration: use_sarif needs security-events: write. (alternate-configuration)
file.yml:3:1 ... 1, Warning - Unsupported configuration: use_sarif needs security-events: write. (alternate-configuration)
file.yml:4:1 ... 1, Warning - Unsupported configuration: use_sarif needs security-events: write. (alternate-configuration)
file.yml:5:1 ... 1, Warning - Unsupported configuration: use_sarif needs security-events: write. (some-configuration)

';
$ENV{'GITHUB_HEAD_REF'} = 'test-ref';
$ENV{'GITHUB_SERVER_URL'} = 'http://github.localdomain';
$ENV{'GITHUB_REPOSITORY'} = 'owner/repo';
$ENV{'GITHUB_EVENT_PATH'} = "$origin/t/summary-table-main/event-path.json";
my $head = `GIT_DIR=.git git rev-parse HEAD`;
chomp $head;

open my $input, '<', \$text;
*ARGV = $input;
$ENV{'summary_budget'} = 600;
my ($stdout, $stderr, $result) = capture {
CheckSpelling::SummaryTables::main();
};
is($stdout, "<details><summary>Details :mag_right:</summary>

<details><summary>:open_file_folder: some-configuration</summary>

note|path
-|-
Unsupported configuration: use_sarif needs security-events: write. | https://github.com/owner/example/blame/$head/file.yml#L5
</details>

<details><summary>:open_file_folder: unsupported-configuration</summary>

note|path
-|-
Unsupported configuration: use_sarif needs security-events: write. | https://github.com/owner/example/blame/$head/file.yml#L1
</details>


</details>

");
is($stderr, "Summary Tables budget: 600
Summary Tables budget reduced to: 538
::warning title=summary-table::Details for 'alternate-configuration' too big to include in Step Summary. (summary-table-skipped)
Summary Tables budget reduced to: 284
Summary Tables budget reduced to: 23
");
is($result, 1);
close $input;

open $input, '<', \$text;
$ENV{'summary_budget'} = 100;
($stdout, $stderr, $result) = capture {
CheckSpelling::SummaryTables::main();
};
is($stderr, q<Summary Tables budget: 100
Summary Tables budget reduced to: 38
::warning title=summary-table::Details for 'alternate-configuration' too big to include in Step Summary. (summary-table-skipped)
::warning title=summary-table::Details for 'some-configuration' too big to include in Step Summary. (summary-table-skipped)
::warning title=summary-table::Details for 'unsupported-configuration' too big to include in Step Summary. (summary-table-skipped)
>);
is($stdout, '');
is($result, 0);
close $input;

open $input, '<', \$text;
$ENV{'GITHUB_REPOSITORY'} = 'another/repo';
($stdout, $stderr, $result) = capture {
CheckSpelling::SummaryTables::main();
};
is($stderr, q<Summary Tables budget: 100
Summary Tables budget reduced to: 38
::warning title=summary-table::Details for 'alternate-configuration' too big to include in Step Summary. (summary-table-skipped)
::warning title=summary-table::Details for 'some-configuration' too big to include in Step Summary. (summary-table-skipped)
::warning title=summary-table::Details for 'unsupported-configuration' too big to include in Step Summary. (summary-table-skipped)
>);
is($stdout, '');
is($result, 0);
close $input;

$text = '';
open $input, '<', \$text;
$ENV{'GITHUB_REPOSITORY'} = 'another/repo';
($stdout, $stderr, $result) = capture {
CheckSpelling::SummaryTables::main();
};
is($stderr, q<Summary Tables budget: 100
>);
is($stdout, '');
is($result, undef);
close $input;


*ARGV = $oldIn;
