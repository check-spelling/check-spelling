#!/usr/bin/env -S perl -T

use warnings;
use CheckSpelling::Sarif;
use CheckSpelling::Util;

sub main {
    my $sarif_template_file = "$ENV{spellchecker}/sarif.json";
    my $sarif_template_overlay_file = CheckSpelling::Util::get_file_from_env('sarif_overlay_path', '/dev/null');
    my $output = CheckSpelling::Sarif::main($sarif_template_file, $sarif_template_overlay_file);
    exit 1 unless $output;
    print $output;
}

main();
