#!/usr/bin/env -S perl -T

use warnings;
use CheckSpelling::DictionaryCoverage;

my @dictionaries = grep { !/\.(?:aff|etag)$/; } glob("*");
CheckSpelling::DictionaryCoverage::main(shift, @dictionaries);
