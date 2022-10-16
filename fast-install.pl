#!/usr/bin/env perl

use strict;
use File::Basename;
use File::Path qw(make_path);

my $dirname = dirname(__FILE__);
my @shared=grep { m{share/perl} } @INC;
my $dest=$shared[0];

make_path($dest, {
    mode => 0755
});
system('/usr/bin/env', 'cp', '-R', "$dirname/lib/CheckSpelling", $dest);
