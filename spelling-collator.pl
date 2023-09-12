#!/usr/bin/env -S perl -T

use warnings;
use CheckSpelling::SpellingCollator;

binmode STDOUT, ':utf8';

CheckSpelling::SpellingCollator::main();
