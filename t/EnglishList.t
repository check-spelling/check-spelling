#!/usr/bin/env -S perl -T -Ilib

use strict;
use warnings;

use Test::More;

plan tests => 7;
use_ok('CheckSpelling::EnglishList');

is(CheckSpelling::EnglishList::build(
    qw()), '');
is(CheckSpelling::EnglishList::build(
    qw(one)), 'one');
is(CheckSpelling::EnglishList::build(
    qw(one two)), 'one and two');
is(CheckSpelling::EnglishList::build(
    qw(one two three)), 'one, two, and three');
is(CheckSpelling::EnglishList::build(
    'red car', '', 'bus'), 'red car and bus');
is(CheckSpelling::EnglishList::build(
    'red car', 'bus', 'green apple'), 'red car, bus, and green apple');
