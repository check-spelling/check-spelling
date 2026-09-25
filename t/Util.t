#!/usr/bin/env -S perl -T -w -Ilib

use strict;
use warnings;
use utf8;

use Test::More;
use Capture::Tiny ':all';
use File::Temp qw/ tempfile /;

plan tests => 59;
use_ok('CheckSpelling::Util');

$ENV{'EMPTY_VAR'}='';
is(CheckSpelling::Util::get_val_from_env('EMPTY_VAR', 1), 1, 'fallback env var value');
is(CheckSpelling::Util::get_file_from_env('EMPTY_VAR', 1), 1, 'fallback file env var value');

'hi' =~ /(.*)/;
$ENV{'NOT_A_NUMBER'}='a';
is(CheckSpelling::Util::get_val_from_env('NOT_A_NUMBER', 1), 1, 'fallback env var for non number');

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

my ($stdout, $stderr, $result) = capture { CheckSpelling::Util::read_file('no-such-file') };

is($stdout, '');
is($stderr, 'Could not open file (no-such-file)
');
is($result, undef);

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

is(CheckSpelling::Util::wrap_in_backticks('`this'), '`` `this ``', 'leading backtick');
is(CheckSpelling::Util::wrap_in_backticks('this'), '`this`', 'basic string');
is(CheckSpelling::Util::wrap_in_backticks('this `thing` is good'), '``this `thing` is good``', 'nested backticks');
is(CheckSpelling::Util::wrap_in_backticks('this `thing` is ``very`` good'), '```this `thing` is ``very`` good```', 'many backticks');

my $a10 = 'a'x10;
is(CheckSpelling::Util::truncate_with_ellipsis($a10, 6), 'a'x6 . '…', 'truncate');
is(CheckSpelling::Util::truncate_with_ellipsis(CheckSpelling::Util::wrap_in_backticks($a10), 4), '`'.'a'x3 . '`…', 'truncate in backticks');
is(CheckSpelling::Util::truncate_with_ellipsis($a10, 10), $a10, 'no truncation');

my ($insert_fd, $insert) = tempfile;
print $insert_fd "Insertion
Text
";
close $insert_fd;
$ENV{'insert'} = $insert;

my ($base_fd, $base) = tempfile;
print $base_fd "# Unrecognized words

<details><summary>These words ...
are ...
</summary>
</details><p></p>

<details><summary>To accept
these terms...
</summary>
</details><p></p>

The end.
";
close $base_fd;
$ENV{'base'} = $base;

($stdout, $stderr, $result) = capture {
    CheckSpelling::Util::insert_into_summary();
};
like($stdout, qr{</details><p></p>\n\nInsertion\nText\n\n<details><summary>To accept}, 'insert_into_summary out');
is($stderr, '', 'insert_into_summary err');
is($result, '1', 'insert_into_summary result');

($base_fd, $base) = tempfile;
print $base_fd "# Unrecognized words
<details><summary>To accept these
terms...
</summary>
</details><p></p>

The end.
";
close $base_fd;
$ENV{'base'} = $base;

($stdout, $stderr, $result) = capture {
    CheckSpelling::Util::insert_into_summary();
};
like($stdout, qr{# Unrecognized words\nInsertion\nText\n\n\*\*OR\*\*\n{3}<details><summary>To accept}, 'insert_into_summary or out');
is($stderr, '', 'insert_into_summary or err');
is($result, '1', 'insert_into_summary or result');
