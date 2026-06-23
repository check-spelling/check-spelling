#!/usr/bin/env -S perl

use warnings;
use CheckSpelling::SpellingCollator;

binmode STDOUT, ':utf8';

CheckSpelling::SpellingCollator::main();
