#!/usr/bin/env -S perl -T -Ilib

use strict;
use warnings;

use Test::More;

plan tests => 5;
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
