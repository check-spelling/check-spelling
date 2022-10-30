#!/usr/bin/env perl
use Cwd qw(abs_path);
my $maybe_bad=abs_path($ENV{maybe_bad});
my $workspace_path=abs_path($ENV{GITHUB_WORKSPACE});
if ($maybe_bad !~ /^\Q$workspace_path\E/) {
    print "::error ::Configuration files must live within $workspace_path...\n";
    print "::error ::Unfortunately, file $maybe_bad appears to reside elsewhere.\n";
    exit 3;
}
if ($maybe_bad =~ m{/\.git/}i) {
    print "::error ::Configuration files must not live within `.git/`...\n";
    print "::error ::Unfortunately, file $maybe_bad appears to.\n";
    exit 4;
}
