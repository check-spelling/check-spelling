#!/usr/bin/env -S perl -T -Ilib

use strict;
use warnings;

use Test::More;

plan tests => 42;
use_ok('CheckSpelling::Util');

$ENV{'EMPTY_VAR'}='';
is(CheckSpelling::Util::get_val_from_env('EMPTY_VAR', 1), 1, 'fallback env var value');

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
is(join ('-', @sorted), join ('-', @expected), 'case_biased sorting');

my $file;
{
    open FILE, '<:utf8', 't/Util.t';
    local $/ = undef;
    $file = <FILE>;
    close FILE;
}
is(CheckSpelling::Util::read_file('t/Util.t'), $file, 'read_file');

is(CheckSpelling::Util::read_file('no-such-file'), undef, "undefined as expected");

is(CheckSpelling::Util::calculate_delay(
    'Ignored: 2'
), 5, 'calculate delay (no inputs)');
is(CheckSpelling::Util::calculate_delay(
    'Retry-After: 0'
), 1, 'calculate delay (retry after 0)');
is(CheckSpelling::Util::calculate_delay(
    'Retry-After: 2'
), 2, 'calculate delay (retry after 2)');
is(CheckSpelling::Util::calculate_delay(
    'Retry-After: 4',
    'Retry-After: 3'
), 3, 'calculate delay (multiple retry after)');
is(CheckSpelling::Util::calculate_delay(
    'Date: Thu, 19 Jan 2023 01:44:06 GMT',
    'expires: Thu, 19 Jan 2023 01:49:06 GMT'
), 300, 'calculate delay (expires after date)');
is(CheckSpelling::Util::calculate_delay(
    'Date: Thu, 19 Jan 2023 01:44:06 GMT',
    'expires: Thu, 19 Jan 2023 01:44:06 GMT'
), 5, 'calculate delay (expires = date)');
is(CheckSpelling::Util::calculate_delay(
    'Date: Thu, 19 Jan 2023 01:44:06 GMT'
), 5, 'calculate delay (date without expires)');
is(CheckSpelling::Util::calculate_delay(
    'Date: Thu, 19 Jan 2023 01:44:06 GMT',
    'expires: MT'
), 5, 'calculate delay (bogus expires)');
is(CheckSpelling::Util::calculate_delay(
    'expires: Thu, 19 Jan 2023 01:49:06 GMT'
), 5, 'calculate delay (expires without date)');
is(CheckSpelling::Util::calculate_delay(
    'Date: GMT'
), 5, 'calculate delay (date without expires)');
is(CheckSpelling::Util::calculate_delay(
    'expires: MT'
), 5, 'calculate delay (expires without date)');
is(CheckSpelling::Util::list_with_terminator(
    '-', 1, 2
), '1-2-', 'list_with_terminator');
is(CheckSpelling::Util::number_biased(
    '1',
    '1'
), 0, '==');
is(CheckSpelling::Util::number_biased(
    '1',
    '2'
), -1, '<');
is(CheckSpelling::Util::number_biased(
    '2',
    '1'
), 1, '>');
is(CheckSpelling::Util::number_biased(
    'a',
    'a'
), 0, 'eq');
is(CheckSpelling::Util::number_biased(
    'a',
    'b'
), -1, '-cmp');
is(CheckSpelling::Util::number_biased(
    'b',
    'a'
), 1, '+cmp');
is(CheckSpelling::Util::number_biased(
    'a',
    'A'
), 1, '+cmp aA');
is(CheckSpelling::Util::number_biased(
    'b',
    'A'
), 1, '+cmp bA');
is(CheckSpelling::Util::number_biased(
    'A',
    'a'
), -1, '-cmp Aa');
is(CheckSpelling::Util::number_biased(
    'A',
    'b'
), -1, '-cmp bA');
is(CheckSpelling::Util::number_biased(
    '1',
    'a'
), -1, '-cmp 1a');
is(CheckSpelling::Util::number_biased(
    'a',
    '1'
), 1, '+cmp 1a');

is(CheckSpelling::Util::number_biased(
    'zzzz1',
    'zzzz1'
), 0, '==');
is(CheckSpelling::Util::number_biased(
    'zzzz9',
    'zzzz20'
), -1, '<');
is(CheckSpelling::Util::number_biased(
    'zzzz20',
    'zzzz9'
), 1, '>');
is(CheckSpelling::Util::number_biased(
    '0//0a',
    '0//0a'
), 0, 'eq');
is(CheckSpelling::Util::number_biased(
    '0//0a',
    '0//0b'
), -1, '-cmp');
is(CheckSpelling::Util::number_biased(
    '0//0b',
    '0//0a'
), 1, '+cmp');
is(CheckSpelling::Util::number_biased(
    '0//0a',
    '0//0A'
), 1, '+cmp aA');
is(CheckSpelling::Util::number_biased(
    '0//0b',
    '0//0A'
), 1, '+cmp bA');
is(CheckSpelling::Util::number_biased(
    '0//0A',
    '0//0a'
), -1, '-cmp Aa');
is(CheckSpelling::Util::number_biased(
    '0//0A',
    '0//0b'
), -1, '-cmp bA');
is(CheckSpelling::Util::number_biased(
    'zz//1',
    'zz//a'
), -1, '-cmp 1a');
is(CheckSpelling::Util::number_biased(
    'zz//a',
    'zz//1'
), 1, '+cmp 1a');
@unsorted = qw(
  hello123world
  hello99world
  hello79world
  123world
  -123hello
  Hello99world
);
my @expected_sort = qw(
  -123hello
  123world
  Hello99world
  hello79world
  hello99world
  hello123world
);
@sorted = sort CheckSpelling::Util::number_biased @unsorted;
is_deeply(\@sorted, \@expected_sort, 'sorting with number_biased');
