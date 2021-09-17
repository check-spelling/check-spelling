#!/usr/bin/perl -wT

use CheckSpelling::DictionaryCoverage;

my @dictionaries = glob("*");
CheckSpelling::DictionaryCoverage::main(shift, @dictionaries);
