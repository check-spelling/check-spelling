#!/usr/bin/env -S perl -wT

use CheckSpelling::DictionaryCoverage;

my @dictionaries = glob("*");
CheckSpelling::DictionaryCoverage::main(shift, @dictionaries);
