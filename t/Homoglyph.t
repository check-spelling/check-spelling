#!/usr/bin/env -S perl -w -Ilib

use strict;
use warnings;
use utf8;

use Cwd qw();
use open ':std', ':encoding(UTF-8)';
my $path = $ENV{PATH};
$path =~ /(.*)/;
$ENV{PATH} = $path;
use Test::More;
use File::Temp qw/ tempfile tempdir /;
use Capture::Tiny ':all';

my $builder = Test::More->builder;
binmode $builder->output,         ":utf8";
binmode $builder->failure_output, ":utf8";
binmode $builder->todo_output,    ":utf8";

plan tests => 12;
use_ok('CheckSpelling::Homoglyph');

CheckSpelling::Homoglyph::init('t/homoglyph/missing-homoglyph.list');
CheckSpelling::Homoglyph::init('t/homoglyph/homoglyph.list');
my ($output, $error, $result) = capture {
    CheckSpelling::Homoglyph::dump_aliases();
};
my ($output_a, $output_b, $output_c);
$output_a = $output_b = $output_c = $output;
is($output_a =~ s/.*: A\n//g, 4, 'A aliases');
is($output_b =~ s/.*: B\n//g, 9, 'B aliases');
is($output_c =~ s/.*: B C\n//g, 1, 'B C aliases');
like($output, qr/\x{299}\x{391}\x{392}\x{0412}\x{432}\x{13f4}\x{13fc}\x{15f7}\x{16d2}\x{1d00}\x{212C}\x{1D4D0}\x{1D504}/, 'dump_aliases out');
is($CheckSpelling::Homoglyph::homoglyph_to_glyph{'!'}, '!', 'ambiguous glyph maps to itself');
is($CheckSpelling::Homoglyph::homoglyph_to_glyph{'?'}, undef, 'unaliased glyph is not aliased');
is($error, '', 'dump_aliases error');
is($result, 0, 'dump_aliases result');

use CheckSpelling::UnknownWordSplitter;
$ENV{'INPUT_CHECK_HOMOGLYPHS'} = 1;
$CheckSpelling::UnknownWordSplitter::ignore_pattern = '!';
$ENV{'INPUT_UPPER_PATTERN'} = '[Q]';
$ENV{'INPUT_LOWER_PATTERN'} = '[q]';
$ENV{'INPUT_NOT_LOWER_PATTERN'} = '[^q]';
$ENV{'INPUT_NOT_UPPER_OR_LOWER_PATTERN'} = '[^Qq]';
$ENV{'INPUT_PUNCTUATION_PATTERN'} = '=';
$CheckSpelling::UnknownWordSplitter::ignore_next_line_pattern = '';
$CheckSpelling::UnknownWordSplitter::timeout = 5000000;
$CheckSpelling::UnknownWordSplitter::shortest = 3;
$CheckSpelling::UnknownWordSplitter::shortest_word = 3;
$CheckSpelling::UnknownWordSplitter::word_match = '[Qq]{3,8}';
my ($fh, $file) = tempfile();
print $fh '
hello
';
close $fh;
$ENV{'homoglyph_list_path'} = 't/homoglyph/homoglyph.list';
CheckSpelling::UnknownWordSplitter::load_dictionary($file);
my ($stdout, $stderr);
($stdout, $stderr, $result) = capture {
  CheckSpelling::UnknownWordSplitter::split_file($file);
};
is($stdout, '', 'split_file with empty homoglyphs (out)');
is($stderr, '', 'split_file with empty homoglyphs (err)');
like($result, qr{/}, 'split_file with empty homoglyphs (result)');
