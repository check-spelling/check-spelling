#!/usr/bin/env -S perl -T

use warnings;
use CheckSpelling::EnglishList;

print CheckSpelling::EnglishList::build(@ARGV);
