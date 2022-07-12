#! -*-perl-*-

# ~/bin/w
# Search for potentially misspelled words
# Output is:
# misspellled
# woord (WOORD, Woord, woord, woord's)
package CheckSpelling::UnknownWordSplitter;

use 5.022;
use feature 'unicode_strings';
use strict;
use warnings;
use Encode qw/decode_utf8 FB_DEFAULT/;
use File::Basename;
use Cwd 'abs_path';
use File::Temp qw/ tempfile tempdir /;
use CheckSpelling::Util;
our $VERSION='0.1.0';

my ($longest_word, $shortest_word, $word_match, $forbidden_re, $patterns_re);
my ($shortest, $longest) = (255, 0);
my @forbidden_re_list;
my %dictionary = ();
my %unique;
my %unique_unrecognized;
my ($last_file, $words, $unrecognized) = ('', 0, 0);

sub file_to_list {
  my ($re) = @_;
  my @file;
  if (open(FILE, '<:utf8', $re)) {
    local $/=undef;
    my $file=<FILE>;
    close FILE;
    for (split /\R/, $file) {
      next if /^#/;
      chomp;
      next unless s/^(.+)/(?:$1)/;
      push @file, $_;
    }
  }
  return @file;
}

sub list_to_re {
  my (@list) = @_;
  return '$^' unless scalar @list;
  return join "|", @list;
}

sub file_to_re {
  my ($re) = @_;
  return list_to_re(file_to_list($re));
}

sub not_empty {
  my ($thing) = @_;
  return defined $thing && $thing ne ''
}

sub valid_word {
  # shortest_word is an absolute
  our ($shortest, $longest, $shortest_word, $longest_word);
  $shortest = $shortest_word if $shortest_word;
  if ($longest_word) {
    # longest_word is an absolute
    $longest = $longest_word;
  } elsif (not_empty($longest)) {
    # we allow for some sloppiness (a couple of stuck keys per word)
    # it's possible that this should scale with word length
    $longest += 2;
  }
  return qr/\w{3}/ if (defined $shortest && not_empty($longest)) && ($shortest > $longest);
  $shortest = 3 unless defined $shortest;
  $longest = '' unless defined $longest;
  $word_match = "\\w{$shortest,$longest}";
  return qr/\b$word_match\b/;
}

sub load_dictionary {
  my ($dict) = @_;
  our ($word_match, $longest, $shortest, $longest_word, $shortest_word, %dictionary);
  $longest_word = CheckSpelling::Util::get_val_from_env('INPUT_LONGEST_WORD', undef);
  $shortest_word = CheckSpelling::Util::get_val_from_env('INPUT_SHORTEST_WORD', undef);
  %dictionary = ();

  open(DICT, '<:utf8', $dict);
  while (!eof(DICT)) {
    my $word = <DICT>;
    chomp $word;
    next unless $word =~ $word_match;
    my $l = length $word;
    $longest = -1 unless not_empty($longest);
    $longest = $l if $l > $longest;
    $shortest = $l if $l < $shortest;
    $dictionary{$word}=1;
  }
  close DICT;

  $word_match = valid_word();
}

sub init {
  my ($dirname) = @_;
  our ($word_match, %unique);
  our $patterns_re = file_to_re "$dirname/patterns.txt";
  our @forbidden_re_list = file_to_list "$dirname/forbidden.txt";
  our $forbidden_re = list_to_re @forbidden_re_list;
  our $largest_file = CheckSpelling::Util::get_val_from_env('INPUT_LARGEST_FILE', 1024*1024);

  $word_match = valid_word();

  my $dict = "$dirname/words";
  $dict = '/usr/share/dict/words' unless -e $dict;
  load_dictionary($dict);
}

sub split_file {
  my ($file) = @_;
  our (
    $unrecognized, $longest_word, $shortest_word, $largest_file, $words,
    $word_match, %unique, %unique_unrecognized, $forbidden_re,
    @forbidden_re_list, $patterns_re, %dictionary,
  );
  my $temp_dir = tempdir();
  open(NAME, '>:utf8', "$temp_dir/name");
    print NAME $file;
  close NAME;
  if (defined $largest_file) {
    my $file_size = -s $file;
    if ($file_size > $largest_file) {
      open(SKIPPED, '>:utf8', "$temp_dir/skipped");
      print SKIPPED "size `$file_size` exceeds limit `$largest_file`. (large-file)\n";
      close SKIPPED;
      return $temp_dir;
    }
  }
  open FILE, '<', $file;
  binmode FILE;
  ($words, $unrecognized) = (0, 0);
  %unique = ();
  %unique_unrecognized = ();

  local $SIG{__WARN__} = sub {
    my $message = shift;
    $message =~ s/> line/> in $file - line/;
    chomp $message;
    print STDERR "$message\n";
  };

  open(WARNINGS, '>:utf8', "$temp_dir/warnings");
  while (<FILE>) {
    $_ = decode_utf8($_, FB_DEFAULT);
    s/\R$//;
    next unless /./;
    my $raw_line = $_;
    # hook for custom line based text exclusions:
    s/($patterns_re)/"="x length($1)/ge;
    my $previous_line_state = $_;
    while (s/($forbidden_re)/"="x length($1)/e) {
      my ($begin, $end, $match) = ($-[0] + 1, $+[0], $1);
      my $found_trigger_re;
      for my $forbidden_re_singleton (@forbidden_re_list) {
        my $test_line = $previous_line_state;
        if ($test_line =~ s/($forbidden_re_singleton)/"="x length($1)/e) {
          next unless $test_line eq $_;
          my ($begin_test, $end_test, $match_test) = ($-[0] + 1, $+[0], $1);
          next unless $begin == $begin_test;
          next unless $end == $end_test;
          next unless $match eq $match_test;
          $found_trigger_re = $forbidden_re_singleton;
          last;
        }
      }
      if ($found_trigger_re) {
        $found_trigger_re =~ s/^\(\?:(.*)\)$/$1/;
        print WARNINGS "line $., columns $begin-$end, Warning - `$match` matches a line_forbidden.patterns entry: `$found_trigger_re`. (forbidden-pattern)\n";
      } else {
        print WARNINGS "line $., columns $begin-$end, Warning - `$match` matches a line_forbidden.patterns entry. (forbidden-pattern)\n";
      }
      $previous_line_state = $_;
    }
    # This is to make it easier to deal w/ rules:
    s/^/ /;
    while (s/([^\\])\\[rtn]/$1 /g) {}
    # https://www.fileformat.info/info/unicode/char/2019/
    my $rsqm = "\xE2\x80\x99";
    s/$rsqm|&apos;|&#39;/'/g;
    s/[^a-zA-Z']+/ /g;
    while (s/([A-Z]{2,})([A-Z][a-z]{2,})/ $1 $2 /g) {}
    while (s/([a-z']+)([A-Z])/$1 $2/g) {}
    my %unrecognized_line_items = ();
    for my $token (split /\s+/, $_) {
      $token =~ s/^(?:'|$rsqm)+//g;
      $token =~ s/(?:'|$rsqm)+s?$//g;
      my $raw_token = $token;
      $token =~ s/^[^Ii]?'+(.*)/$1/;
      $token =~ s/(.*?)'+$/$1/;
      next unless $token =~ $word_match;
      if (defined $dictionary{$token}) {
        ++$words;
        $unique{$token}=1;
        next;
      }
      my $key = lc $token;
      $key =~ s/''+/'/g;
      $key =~ s/'[sd]$//;
      if (defined $dictionary{$key}) {
        ++$words;
        $unique{$key}=1;
        next;
      }
      ++$unrecognized;
      $unique_unrecognized{$raw_token}=1;
      $unrecognized_line_items{$raw_token}=1;
    }
    for my $token (keys %unrecognized_line_items) {
      $token =~ s/'/(?:'|$rsqm)+/g;
      my $before;
      if ($token =~ /^[A-Z][a-z]/) {
        $before = '(?<=.)';
      } elsif ($token =~ /^[A-Z]/) {
        $before = '(?<=[^A-Z])';
      } else {
        $before = '(?<=[^a-z])';
      }
      my $after = ($token =~ /[A-Z]$/) ? '(?=[^A-Za-z])|(?=[A-Z][a-z])' : '(?=[^a-z])';
      while ($raw_line =~ /(?:\b|$before)($token)(?:\b|$after)/g) {
        my ($begin, $end, $match) = ($-[0] + 1, $+[0], $1);
        next unless $match =~ /./;
        print WARNINGS "line $. cols $begin-$end: '$match'\n";
      }
    }
  }
  close FILE;

  if ($unrecognized) {
    open(STATS, '>:utf8', "$temp_dir/stats");
      print STATS "{words: $words, unrecognized: $unrecognized, unknown: ".(keys %unique_unrecognized).", unique: ".(keys %unique)."}";
    close STATS;
    open(UNKNOWN, '>:utf8', "$temp_dir/unknown");
      print UNKNOWN join "\n", sort keys %unique_unrecognized;
    close UNKNOWN;
    close WARNINGS;
  }

  return $temp_dir;
}

sub main {
  my ($dirname, @ARGV) = @_;
  our %dictionary;
  unless (%dictionary) {
    init($dirname);
  }

  # read all input
  my @reports;

  for my $file (@ARGV) {
    my $temp_dir = split_file($file);
    push @reports, "$temp_dir\n";
  }
  print join '', @reports;
}

1;
