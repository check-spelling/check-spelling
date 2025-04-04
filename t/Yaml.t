#!/usr/bin/env -S perl -w -Ilib

use strict;
use warnings;
no warnings 'once';
no warnings 'redefine';

use Cwd qw();
use Test::More;
use File::Temp qw/ tempfile tempdir /;

plan tests => 22;
use_ok('CheckSpelling::Yaml');

is(CheckSpelling::Yaml::get_yaml_value(
    'no-such-action.yml', 'name'), '');

is(CheckSpelling::Yaml::get_yaml_value(
    'action.yml', 'name'), '"Check Spelling"');

is(CheckSpelling::Yaml::get_yaml_value('action.yml', 'inputs.largest_file.default'), '"1048576"');

is(CheckSpelling::Yaml::get_yaml_value('action.yml', 'inputs.shortest_word.default'), '"3"');

open my $oldin, '<&', \*STDIN or die "Can't dup STDIN:$!";

my $yaml_content = '
parent:
  items:
  - a
  - b
  # foo: bar
fruit: apple
berry: blue
wine: white
fruit: salad
tree: pear
';

my $invar = $yaml_content;

our $triggered = 0;

*CheckSpelling::Yaml::report = sub {
    my ($file, $start_line, $start_pos, $end, $message, $match, $report_match) = @_;
    is($file, '-');
    is($start_line, 9);
    is($start_pos, 1);
    is($end, 12);
    is($message, 'Good work');
    is($match, 'wine: white');
    is($report_match, 1);
    ++$main::triggered;
};

CheckSpelling::Yaml::check_yaml_key_value('wine', 'white', 'Good work', 1, '-', $yaml_content);
is($triggered, 1, 'should call CheckSpelling::Yaml::report (wine: white)');

$triggered = 0;
*CheckSpelling::Yaml::report = sub {
    my ($file, $start_line, $start_pos, $end, $message, $match, $report_match) = @_;
    is($file, '-');
    is($start_line, 10);
    is($start_pos, 1);
    is($end, 13);
    is($message, 'Good night');
    is($match, 'fruit: salad');
    is($report_match, 1);
    ++$main::triggered;
};

CheckSpelling::Yaml::check_yaml_key_value('fruit', 'salad', 'Good night', 1, '-', $yaml_content);
is($triggered, 1, 'should call CheckSpelling::Yaml::report (fruit: salad)');

$triggered = 0;
*CheckSpelling::Yaml::report = sub {
    my ($file, $start_line, $start_pos, $end, $message, $match, $report_match) = @_;
    ++$main::triggered;
};

CheckSpelling::Yaml::check_yaml_key_value('juice', 'apple', 'No work', 1, '-', $yaml_content);
is($triggered, 0, 'should not call CheckSpelling::Yaml::report');
close STDIN;

open STDIN, '<&', $oldin;
