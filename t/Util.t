#!/usr/bin/env -S perl -T -Ilib

use strict;
use warnings;

use Test::More;

plan tests => 17;
use_ok('CheckSpelling::Util');

$ENV{'EMPTY_VAR'}='';
is(CheckSpelling::Util::get_val_from_env('EMPTY_VAR', 1), 1);

my @unsorted = qw(
    Zoo
    ZOO
    Cherry
    CHERRY
    cherry
    Apple
    APPLE
);
my @sorted = sort CheckSpelling::Util::case_biased @unsorted;
my @expected = qw(
    APPLE
    Apple
    CHERRY
    Cherry
    cherry
    ZOO
    Zoo
);
is(join ('-', @sorted), join ('-', @expected));

my $file;
{
    open FILE, '<:utf8', 't/Util.t';
    local $/ = undef;
    $file = <FILE>;
    close FILE;
}
is(CheckSpelling::Util::read_file('t/Util.t'), $file);

is(CheckSpelling::Util::read_file('no-such-file'), undef, "undefined as expected");

is(CheckSpelling::Util::calculate_delay(
    'Ignored: 2'
), 5);
is(CheckSpelling::Util::calculate_delay(
    'Retry-After: 0'
), 1);
is(CheckSpelling::Util::calculate_delay(
    'Retry-After: 2'
), 2);
is(CheckSpelling::Util::calculate_delay(
    'Retry-After: 4',
    'Retry-After: 3'
), 3);
is(CheckSpelling::Util::calculate_delay(
    'Date: Thu, 19 Jan 2023 01:44:06 GMT',
    'expires: Thu, 19 Jan 2023 01:49:06 GMT'
), 300);
is(CheckSpelling::Util::calculate_delay(
    'Date: Thu, 19 Jan 2023 01:44:06 GMT',
    'expires: Thu, 19 Jan 2023 01:44:06 GMT'
), 5);
is(CheckSpelling::Util::calculate_delay(
    'Date: Thu, 19 Jan 2023 01:44:06 GMT'
), 5);
is(CheckSpelling::Util::calculate_delay(
    'Date: Thu, 19 Jan 2023 01:44:06 GMT',
    'expires: MT'
), 5);
is(CheckSpelling::Util::calculate_delay(
    'expires: Thu, 19 Jan 2023 01:49:06 GMT'
), 5);
is(CheckSpelling::Util::calculate_delay(
    'Date: GMT'
), 5);
is(CheckSpelling::Util::calculate_delay(
    'expires: MT'
), 5);
is(CheckSpelling::Util::list_with_terminator(
    '-', 1, 2
), '1-2-');
