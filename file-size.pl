#!/usr/bin/env perl
@x=stat(shift);
print $x[7];
