#!/usr/bin/env -S perl -T

use warnings;
use CheckSpelling::DictionaryCoverage;

my @dictionaries = glob("*");
CheckSpelling::DictionaryCoverage::main(shift, @dictionaries);
