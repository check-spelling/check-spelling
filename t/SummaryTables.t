#!/usr/bin/env -S perl -w -Ilib

use strict;
use warnings;

use Cwd qw();
use Test::More;
use File::Temp qw/ tempfile tempdir /;

plan tests => 8;
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
