#!/usr/bin/env -S perl -wT

use warnings;
use CheckSpelling::SpellingCollator;

binmode STDOUT, ':utf8';

CheckSpelling::SpellingCollator::main();
