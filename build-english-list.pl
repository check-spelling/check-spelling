#!/usr/bin/env -S perl

use warnings;
use CheckSpelling::EnglishList;

print CheckSpelling::EnglishList::build(@ARGV);
