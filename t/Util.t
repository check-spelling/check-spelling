#!/usr/bin/perl -wT -Ilib

use strict;

use Test::More;

plan tests => 2;
use_ok('CheckSpelling::Util');

$ENV{'EMPTY_VAR'}='';
is(CheckSpelling::Util::get_val_from_env('EMPTY_VAR', 1), 1);
