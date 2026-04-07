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
no warnings qw(experimental::vlb);
use utf8;
use Encode qw/decode_utf8 encode FB_DEFAULT/;
use File::Basename;
use Cwd 'abs_path';
use File::Spec;
use File::Temp qw/ tempfile tempdir /;
use File::Path qw/ make_path /;
use CheckSpelling::Util;
use Digest::SHA;
our $VERSION='0.1.0';

my ($longest_word, $shortest_word, $word_match, $forbidden_re, $patterns_re, $candidates_re, $disable_word_collating, $check_file_names);
my ($check_homoglyphs);
my ($ignore_pattern, $upper_pattern, $lower_pattern, $not_lower_pattern, $not_upper_or_lower_pattern, $punctuation_pattern);
my ($shortest, $longest) = (255, 0);
my @forbidden_re_list;
my %forbidden_re_descriptions;
my @candidates_re_list;
my $hunspell_dictionary_path;
my @hunspell_dictionaries;
my %dictionary = ();
my $base_dict;
my %unique;
my %unique_unrecognized;
my ($last_file, $words, $unrecognized) = ('', 0, 0);
my ($ignore_next_line_pattern);
my ($check_images, $ocr_directory);

my $disable_flags;

sub test_re {
  my ($expression) = @_;
  return eval { qr /$expression/ };
}

sub quote_re {
  my ($expression) = @_;
  return $expression if $expression =~ /\?\{/;
  $expression =~ s/
   \G
   (
      (?:[^\\]|\\[^Q])*
   )
   (?:
      \\Q
      (?:[^\\]|\\[^E])*
      (?:\\E)?
   )?
/
   $1 . (defined($2) ? quotemeta($2) : '')
/xge;
  return $expression;
}

sub file_to_lists {
  my ($re) = @_;
  my @patterns;
  my %hints;
  my $fh;
  if (open($fh, '<:utf8', $re)) {
    local $/=undef;
    my $file=<$fh>;
    close $fh;
    my $line_number = 0;
    my $hint = '';
    for (split /\R/, $file) {
      ++$line_number;
      chomp;
      if (/^#(?:\s(.+)|)/) {
        $hint = $1 if ($hint eq '' && defined $1);
        next;
      }
      $hint = '' unless $_ ne '';
      next if $_ eq '$^';
      my $pattern = $_;
      next unless s/^(.+)/(?:$1)/;
      my $quoted = quote_re($1);
      unless (test_re $quoted) {
        my $error = $@;
        my $home = dirname(__FILE__);
        $error =~ s/$home.*?\.pm line \d+\./$re line $line_number (bad-regex)/;
        print STDERR $error;
        $_ = '(?:\$^ - skipped because bad-regex)';
        $hint = '';
      }
      if (defined $hints{$_}) {
        my $pattern_length = length $pattern;
        my $wrapped = CheckSpelling::Util::wrap_in_backticks($pattern);
        print STDERR "$re:$line_number:1 ... $pattern_length, Warning - duplicate pattern: $wrapped (duplicate-pattern)\n";
        $_ = '(?:\$^ - skipped because duplicate-pattern on $line_number)';
      } else {
        push @patterns, $_;
        $hints{$_} = $hint;
      }
      $hint = '';
    }
  }

  return {
    patterns => \@patterns,
    hints => \%hints,
  };
}

sub file_to_list {
  my ($re) = @_;
  my $lists = file_to_lists($re);

  return @{$lists->{'patterns'}};
}

sub list_to_re {
  my (@list) = @_;
  @list = map { my $quoted = quote_re($_); test_re($quoted) ? $quoted : '' } @list;
  @list = grep { $_ ne '' } @list;
  return '$^' unless scalar @list;
  return join "|", (@list);
}

sub not_empty {
  my ($thing) = @_;
  return defined $thing && $thing ne '' && $thing =~ /^\d+$/;
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
  our ($upper_pattern, $lower_pattern, $punctuation_pattern);
  my $word_pattern = join '|', (grep { defined $_ && /./ } ($upper_pattern, $lower_pattern, $punctuation_pattern));
  $word_pattern = q<\\w|'> unless $word_pattern;
  if ((defined $shortest && not_empty($longest)) &&
      ($shortest > $longest)) {
    $word_pattern = "(?:$word_pattern){3}";
    return qr/$word_pattern/;
  }
  $shortest = 3 unless defined $shortest;
  $longest = '' unless not_empty($longest);
  $word_match = "(?:$word_pattern){$shortest,$longest}";
  return qr/\b$word_match\b/;
}

sub load_dictionary {
  my ($dict) = @_;
  our ($word_match, $longest, $shortest, $longest_word, $shortest_word, %dictionary);
  $longest_word = CheckSpelling::Util::get_val_from_env('INPUT_LONGEST_WORD', undef);
  $shortest_word = CheckSpelling::Util::get_val_from_env('INPUT_SHORTEST_WORD', 0);
  our ($ignore_pattern, $upper_pattern, $lower_pattern, $not_lower_pattern, $not_upper_or_lower_pattern, $punctuation_pattern);
  $ignore_pattern = CheckSpelling::Util::get_file_from_env_utf8('INPUT_IGNORE_PATTERN', q<[^a-zA-Z']>);
  $upper_pattern = CheckSpelling::Util::get_file_from_env_utf8('INPUT_UPPER_PATTERN', '[A-Z]');
  $lower_pattern = CheckSpelling::Util::get_file_from_env_utf8('INPUT_LOWER_PATTERN', '[a-z]');
  $not_lower_pattern = CheckSpelling::Util::get_file_from_env_utf8('INPUT_NOT_LOWER_PATTERN', '[^a-z]');
  $not_upper_or_lower_pattern = CheckSpelling::Util::get_file_from_env_utf8('INPUT_NOT_UPPER_OR_LOWER_PATTERN', '[^A-Za-z]');
  $punctuation_pattern = CheckSpelling::Util::get_file_from_env_utf8('INPUT_PUNCTUATION_PATTERN', q<'>);
  our $check_homoglyphs = CheckSpelling::Util::get_val_from_env('INPUT_CHECK_HOMOGLYPHS', 0);
  if ($check_homoglyphs && $check_homoglyphs !~ /false/i) {
    my $homoglyph_list_path = CheckSpelling::Util::get_file_from_env_utf8('homoglyph_list_path', '/dev/null');
    if (-s $homoglyph_list_path) {
      use CheckSpelling::Homoglyph;
      CheckSpelling::Homoglyph::init($homoglyph_list_path);
    } else {
      $check_homoglyphs = 0;
    }
  } else {
    $check_homoglyphs = 0;
  }
  %dictionary = ();

  open(my $dict_fh, '<:utf8', $dict);
  while (!eof($dict_fh)) {
    my $word = <$dict_fh>;
    chomp $word;
    next unless $word =~ $word_match;
    my $l = length $word;
    $longest = -1 unless not_empty($longest);
    $longest = $l if $l > $longest;
    $shortest = $l if $l < $shortest;
    $dictionary{$word}=1;
  }
  close $dict_fh;

  $word_match = valid_word();
}

sub hunspell_dictionary {
  my ($dict) = @_;
  my $name = $dict;
  $name =~ s{/src/index/hunspell/index\.dic$}{};
  $name =~ s{.*/}{};
  my $aff = $dict;
  my $encoding;
  $aff =~ s/\.dic$/.aff/;
  if (open my $aff_fh, '<', $aff) {
    while (<$aff_fh>) {
      next unless /^SET\s+(\S+)/;
      $encoding = $1 if ($1 !~ /utf-8/i);
      last;
    }
    close $aff_fh;
  }
  return {
    name => $name,
    dict => $dict,
    aff => $aff,
    encoding => $encoding,
    engine => Text::Hunspell->new($aff, $dict),
  }
}

sub init {
  my ($configuration) = @_;
  our ($word_match, %unique, $patterns_re, @forbidden_re_list, $forbidden_re, @candidates_re_list, $candidates_re);
  our $sandbox = CheckSpelling::Util::get_file_from_env('sandbox', '');
  our $hunspell_dictionary_path = CheckSpelling::Util::get_file_from_env('hunspell_dictionary_path', '');
  our $timeout = CheckSpelling::Util::get_val_from_env('splitter_timeout', 30);
  our %forbidden_re_descriptions;
  if ($hunspell_dictionary_path) {
    our @hunspell_dictionaries = ();
    if (eval 'use Text::Hunspell; 1') {
      my @hunspell_dictionaries_list = glob("$hunspell_dictionary_path/*.dic");
      for my $hunspell_dictionary_file (@hunspell_dictionaries_list) {
        push @hunspell_dictionaries, hunspell_dictionary($hunspell_dictionary_file);
      }
    } else {
      print STDERR "Could not load Text::Hunspell for dictionaries (hunspell-unavailable)\n";
    }
  }
  my (@patterns_re_list, %in_patterns_re_list);
  if (-e "$configuration/patterns.txt") {
    @patterns_re_list = file_to_list "$configuration/patterns.txt";
    $patterns_re = list_to_re @patterns_re_list;
    %in_patterns_re_list = map {$_ => 1} @patterns_re_list;
  } else {
    $patterns_re = undef;
  }

  if (-e "$configuration/forbidden.txt") {
    my $forbidden_re_info = file_to_lists "$configuration/forbidden.txt";
    @forbidden_re_list = @{$forbidden_re_info->{'patterns'}};
    %forbidden_re_descriptions = %{$forbidden_re_info->{'hints'}};
    $forbidden_re = list_to_re @forbidden_re_list;
  } else {
    $forbidden_re = undef;
  }

  if (-e "$configuration/candidates.txt") {
    @candidates_re_list = file_to_list "$configuration/candidates.txt";
    @candidates_re_list = map { my $quoted = quote_re($_); $in_patterns_re_list{$_} || !test_re($quoted) ? '' : $quoted } @candidates_re_list;
    $candidates_re = list_to_re @candidates_re_list;
  } else {
    $candidates_re = undef;
  }

  our $largest_file = CheckSpelling::Util::get_val_from_env('INPUT_LARGEST_FILE', 1024*1024);

  my $disable_flags = CheckSpelling::Util::get_file_from_env('INPUT_DISABLE_CHECKS', '');
  our $disable_word_collating = $disable_flags =~ /(?:^|,|\s)word-collating(?:,|\s|$)/;
  our $disable_minified_file = $disable_flags =~ /(?:^|,|\s)minified-file(?:,|\s|$)/;
  our $disable_single_line_file = $disable_flags =~ /(?:^|,|\s)single-line-file(?:,|\s|$)/;

  our $ignore_next_line_pattern = CheckSpelling::Util::get_file_from_env('INPUT_IGNORE_NEXT_LINE', '');
  $ignore_next_line_pattern =~ s/\s+/|/g;

  our $check_images = CheckSpelling::Util::get_val_from_env('INPUT_CHECK_IMAGES', '');
  $check_images = $check_images =~ /^(?:1|true)$/i;
  if ($check_images) {
    our $ocr_directory = CheckSpelling::Util::get_file_from_env('ocr_directory', '/tmp/ocr');
    $ocr_directory = $1 if ($ocr_directory =~ /^(.*)$/);
  }

  our $check_file_names = CheckSpelling::Util::get_file_from_env('check_file_names', '');

  our $use_magic_file = CheckSpelling::Util::get_val_from_env('INPUT_USE_MAGIC_FILE', '');

  $word_match = valid_word();

  our $base_dict = CheckSpelling::Util::get_file_from_env('dict', "$configuration/words");
  $base_dict = '/usr/share/dict/words' unless -e $base_dict;
  load_dictionary($base_dict);
}

sub split_line {
  our (%dictionary, $word_match, $disable_word_collating);
  our ($ignore_pattern, $upper_pattern, $lower_pattern, $not_lower_pattern, $not_upper_or_lower_pattern, $punctuation_pattern);
  our @hunspell_dictionaries;
  our $shortest;
  my $shortest_threshold = $shortest + 2;
  my $pattern = '.';
  # $pattern = "(?:$upper_pattern){$shortest,}|$upper_pattern(?:$lower_pattern){2,}\n";

  # https://www.fileformat.info/info/unicode/char/2019/
  my $rsqm = "\xE2\x80\x99";

  my ($words, $unrecognized) = (0, 0);
  my ($line, $unique_ref, $unique_unrecognized_ref, $unrecognized_line_items_ref) = @_;
    $line =~ s/(?:$rsqm|&apos;|&#39;|\%27|&#8217;|&#x2019;|&rsquo;|\\u2019|\x{2019}|')+/'/g;
    $line =~ s/(?:$ignore_pattern)+/ /g;
    while ($line =~ s/($upper_pattern{2,})($upper_pattern$lower_pattern{2,})/ $1 $2 /g) {}
    while ($line =~ s/((?:$lower_pattern|$punctuation_pattern)+)($upper_pattern)/$1 $2/g) {}
    for my $token (split /\s+/, $line) {
      next unless $token =~ /$pattern/;
      $token =~ s/^(?:'|$rsqm)+//g;
      $token =~ s/(?:'|$rsqm)+s?$//g;
      my $raw_token = $token;
      $token =~ s/^[^Ii]?'+//; # need to reconsider for French
      $token =~ s/'+$//;
      next unless $token =~ $word_match;
      if (defined $dictionary{$token}) {
        ++$words;
        $unique_ref->{$token}=1;
        next;
      }
      if (@hunspell_dictionaries) {
        my $found = 0;
        for my $hunspell_dictionary (@hunspell_dictionaries) {
          my $token_encoded = defined $hunspell_dictionary->{'encoding'} ?
            encode($hunspell_dictionary->{'encoding'}, $token) : $token;
          next unless ($hunspell_dictionary->{'engine'}->check($token_encoded));
          ++$words;
          $dictionary{$token} = 1;
          $unique_ref->{$token}=1;
          $found = 1;
          last;
        }
        next if $found;
      }
      my $key = lc $token;
      if (defined $dictionary{$key}) {
        ++$words;
        $unique_ref->{$key}=1;
        next;
      }
      unless ($disable_word_collating) {
        $key =~ s/''+/'/g;
        $key =~ s/'[sd]$// unless length $key >= $shortest_threshold;
      }
      if (defined $dictionary{$key}) {
        ++$words;
        $unique_ref->{$key}=1;
        next;
      }
      ++$unrecognized;
      $unique_unrecognized_ref->{$raw_token}=1;
      $unrecognized_line_items_ref->{$raw_token}=1;
    }
    return ($words, $unrecognized);
}

sub skip_file {
  my ($temp_dir, $reason) = @_;
  open(my $skipped_fh, '>:utf8', "$temp_dir/skipped");
  print $skipped_fh $reason;
  close $skipped_fh;
}

sub maybe_ocr_file {
  my ($file) = @_;
  our $ocr_directory;
  my $ocr_file = "$ocr_directory/$file";
  $ocr_file =~ /^(.*)$/;
  $ocr_file = $1;
  my $ocr_source_sha = "$ocr_file.sha1";
  $ocr_file = "$ocr_file.txt";
  my $sha = Digest::SHA->new(1)->addfile($file, 'b')->hexdigest;
  if (-e $ocr_file &&
      -e $ocr_source_sha &&
      open my $source_sha, '<', $ocr_source_sha) {
    my $last_sha = <$source_sha>;
    close $source_sha;
    if ($last_sha =~ /(.*)/) {
      return ($ocr_file, 1) if ($1 eq $sha);
    }
  }
  my $tesseract = dirname(dirname(dirname(__FILE__)))."/wrappers/run-tesseract";
  $ENV{'input'} = $file;
  my $text_file = `"$tesseract"`;
  delete $ENV{'input'};
  return ($file, 0) unless defined $text_file;
  my $file_converted = 0;
  chomp $text_file;
  if ($text_file =~ /^(.*)$/) {
    $text_file = $1;
    my $file_size = -s $text_file || 0;
    if ($file_size > 20) {
      $file_converted = 1;
      make_path(dirname($ocr_source_sha));
      open my $source_sha, '>', $ocr_source_sha;
      print $source_sha $sha;
      close $source_sha;
      rename($text_file, $ocr_file);
      $file = $ocr_file;
    } else {
      unlink($text_file);
    }
  }
  return ($file, $file_converted);
}

sub split_file {
  my ($file) = @_;
  our (
    $unrecognized, $shortest, $largest_file, $words,
    $word_match, %unique, %unique_unrecognized, $forbidden_re,
    @forbidden_re_list, $patterns_re, %dictionary,
    $candidates_re, @candidates_re_list, $check_file_names, $use_magic_file, $disable_minified_file,
    $disable_single_line_file,
    $ignore_next_line_pattern,
    $sandbox,
    $check_images,
  );
  $ignore_next_line_pattern = '$^' unless $ignore_next_line_pattern =~ /./;

  our %forbidden_re_descriptions;
  our ($ignore_pattern, $upper_pattern, $lower_pattern, $not_lower_pattern, $not_upper_or_lower_pattern, $punctuation_pattern);

  # https://www.fileformat.info/info/unicode/char/2019/
  my $rsqm = "\xE2\x80\x99";

  my @candidates_re_hits = (0) x scalar @candidates_re_list;
  my @candidates_re_lines = (0) x scalar @candidates_re_list;
  my @forbidden_re_hits = (0) x scalar @forbidden_re_list;
  my @forbidden_re_lines = (0) x scalar @forbidden_re_list;
  my $temp_dir = tempdir(DIR=>$sandbox);
  print STDERR "checking file: $file\n" if defined $ENV{'DEBUG'};
  open(my $name_fh, '>', "$temp_dir/name");
    print $name_fh $file;
  close $name_fh;
  if (defined readlink($file) &&
      rindex(File::Spec->abs2rel(abs_path($file)), '../', 0) == 0) {
    skip_file($temp_dir, "symbolic link points outside repository (out-of-bounds-symbolic-link)\n");
    return $temp_dir;
  }
  if ($use_magic_file) {
    if (open(my $file_fh, '-|',
              '/usr/bin/file',
              '-b',
              '--mime',
              '-e', 'cdf',
              '-e', 'compress',
              '-e', 'csv',
              '-e', 'elf',
              '-e', 'json',
              '-e', 'tar',
              $file)) {
      my $file_kind = <$file_fh>;
      close $file_fh;
      my $file_converted = 0;
      if ($check_images && $file_kind =~ m<^image/(?!svg)>) {
        ($file, $file_converted) = maybe_ocr_file($file);
      }
      if ($file_converted == 0 && $file_kind =~ /^(.*?); charset=binary/) {
        skip_file($temp_dir, "it appears to be a binary file (`$1`) (binary-file)\n");
        return $temp_dir;
      }
    }
  } elsif ($file =~ /\.(?:png|jpe?g|gif)$/) {
    my $file_converted = 0;
    ($file, $file_converted) = maybe_ocr_file($file);
  }
  my $file_size = -s $file;
  if (defined $largest_file) {
    unless ($check_file_names eq $file) {
      if ($file_size > $largest_file) {
        skip_file($temp_dir, "size `$file_size` exceeds limit `$largest_file` (large-file)\n");
        return $temp_dir;
      }
    }
  }
  open my $file_fh, '<', $file;
  binmode $file_fh;
  my $head;
  read($file_fh, $head, 4096);
  $head =~ s/(?:\r|\n)+$//;
  my $dos_new_lines = () = $head =~ /\r\n/gi;
  my $unix_new_lines = () = $head =~ /\n/gi;
  my $mac_new_lines = () = $head =~ /\r/gi;
  local $/;
  if ($unix_new_lines == 0 && $mac_new_lines == 0) {
    $/ = "\n";
  } elsif ($dos_new_lines >= $unix_new_lines && $dos_new_lines >= $mac_new_lines) {
    $/ = "\r\n";
  } elsif ($mac_new_lines > $unix_new_lines) {
    $/ = "\r";
  } else {
    $/ = "\n";
  }
  seek($file_fh, 0, 0);
  ($words, $unrecognized) = (0, 0);
  %unique = ();
  %unique_unrecognized = ();

  local $SIG{__WARN__} = sub {
    my $message = shift;
    $message =~ s/> line/> in $file - line/;
    chomp $message;
    print STDERR "$message\n";
  };

  open(my $warnings_fh, '>:utf8', "$temp_dir/warnings");
  our $timeout;
  eval {
    local $SIG{ALRM} = sub { die "alarm\n" }; # NB: \n required
    alarm $timeout;

    my $ignore_next_line = 0;
    my $offset = 0;
    while (<$file_fh>) {
      if ($. == 1) {
        unless ($disable_minified_file) {
          if ($file_size >= 512 && length($_) == $file_size) {
            skip_file($temp_dir, "file only has a single line (single-line-file)\n");
            last;
          }
        }
      }
      $_ = decode_utf8($_, FB_DEFAULT);
      if (/[\x{D800}-\x{DFFF}]/) {
        skip_file($temp_dir, "file contains a UTF-16 surrogate -- UTF-16 surrogates are not supported (utf16-surrogate-file)\n");
        last;
      }
      s/\R$//;
      s/^\x{FEFF}// if $. == 1;
      next unless /./;
      my $raw_line = $_;

      my $ignore_this_line = $ignore_next_line;
      $ignore_next_line = ($_ =~ /$ignore_next_line_pattern/);
      next if $ignore_this_line;

      # hook for custom line based text exclusions:
      if (defined $patterns_re) {
        s/($patterns_re)/"="x length($1)/ge;
      }
      my $initial_line_state = $_;
      my $previous_line_state = $_;
      my $line_flagged;
      if ($forbidden_re) {
        while (s/($forbidden_re)/"="x length($1)/e) {
          $line_flagged = 1;
          my ($begin, $end, $match) = ($-[0] + 1, $+[0] + 1, $1);
          my $found_trigger_re;
          for my $i (0 .. $#forbidden_re_list) {
            my $forbidden_re_singleton = $forbidden_re_list[$i];
            my $test_line = $previous_line_state;
            if ($test_line =~ s/($forbidden_re_singleton)/"="x length($1)/e) {
              next unless $test_line eq $_;
              my ($begin_test, $end_test, $match_test) = ($-[0] + 1, $+[0] + 1, $1);
              next unless $begin == $begin_test;
              next unless $end == $end_test;
              next unless $match eq $match_test;
              $found_trigger_re = $forbidden_re_singleton;
              my $hit = "$.:$begin:$end";
              $forbidden_re_hits[$i]++;
              $forbidden_re_lines[$i] = $hit unless $forbidden_re_lines[$i];
              last;
            }
          }
          my $wrapped = CheckSpelling::Util::wrap_in_backticks($match);
          if ($found_trigger_re) {
            my $description = $forbidden_re_descriptions{$found_trigger_re} || '';
            $found_trigger_re =~ s/^\(\?:(.*)\)$/$1/;
            my $quoted_trigger_re = CheckSpelling::Util::truncate_with_ellipsis(CheckSpelling::Util::wrap_in_backticks($found_trigger_re), 99);
            if ($description ne '') {
              print $warnings_fh ":$.:$begin ... $end, Warning - $wrapped matches a line_forbidden.patterns rule: $description - $quoted_trigger_re (forbidden-pattern)\n";
            } else {
              print $warnings_fh ":$.:$begin ... $end, Warning - $wrapped matches a line_forbidden.patterns entry: $quoted_trigger_re (forbidden-pattern)\n";
            }
          } else {
            print $warnings_fh ":$.:$begin ... $end, Warning - $wrapped matches a line_forbidden.patterns entry (forbidden-pattern)\n";
          }
          $previous_line_state = $_;
        }
        $_ = $initial_line_state;
      }
      # This is to make it easier to deal w/ rules:
      s/^/ /;
      my %unrecognized_line_items = ();
      our $check_homoglyphs;
      if ($check_homoglyphs) {
        my $check_line_for_homoglyphs = $_;
        my $homoglyphs = $CheckSpelling::Homoglyph::homoglyphs;
        # problematic characters: `\\`, `-`, `]`
        $homoglyphs =~ s/([-\\\]])/\\$1/g;
        $homoglyphs = "[$homoglyphs]";
        our ($longest_word, $shortest_word);
        my $longest_word_string = defined $longest_word && ($longest_word =~ /^\d+$/) ? $longest_word : '';
        my $dollar = '$';
        my $homoglyph_re = "(?=(?:${homoglyphs}|(?:${upper_pattern}|${lower_pattern}|${punctuation_pattern})){${shortest_word},${longest_word_string}}(?:${not_upper_or_lower_pattern}|${dollar}))((?:${upper_pattern}|${lower_pattern})+${homoglyphs}(?:(?:${upper_pattern}|${lower_pattern}|${punctuation_pattern})|${homoglyphs})*|${homoglyphs}+(?:${upper_pattern}|${lower_pattern})(?:(?:${upper_pattern}|${lower_pattern}|${punctuation_pattern})|${homoglyphs})*)";
        while ($check_line_for_homoglyphs =~ /((?=(?:${homoglyphs}|(?:${upper_pattern}|${lower_pattern}|${punctuation_pattern})){${shortest_word},${longest_word_string}}(?:${not_upper_or_lower_pattern}|${dollar}))((?:${upper_pattern}|${lower_pattern})+${homoglyphs}(?:(?:${upper_pattern}|${lower_pattern}|${punctuation_pattern})|${homoglyphs})*|${homoglyphs}+(?:${upper_pattern}|${lower_pattern})(?:(?:${upper_pattern}|${lower_pattern}|${punctuation_pattern})|${homoglyphs})*))/g) {
          my ($token, $token_raw, $begin, $end) = ($1, $1, $-[0], $+[0]);
          $token =~ s/($homoglyphs)/$CheckSpelling::Homoglyph::homoglyph_to_glyph{$1}/g;
          if (defined $dictionary{$token}) {
            my $token_raw = CheckSpelling::Util::wrap_in_backticks($token_raw);
            my $token = CheckSpelling::Util::wrap_in_backticks($token);
            my $wrapped = "$token_raw should probably be $token (homoglyph-word)";
            print $warnings_fh ":$.:$begin ... $end, Error - $wrapped\n";
          }
        }
      }
      my ($new_words, $new_unrecognized) = split_line($_, \%unique, \%unique_unrecognized, \%unrecognized_line_items);
      $words += $new_words;
      $unrecognized += $new_unrecognized;
      my $line_length = length($raw_line);
      for my $token (sort CheckSpelling::Util::case_biased keys %unrecognized_line_items) {
        my $found_token = 0;
        my $raw_token = $token;
        $token =~ s/'/(?:'|\x{2019}|\&apos;|\&#39;)+/g;
        my $before;
        if ($token =~ /^$upper_pattern$lower_pattern/) {
          $before = '(?<=.)';
        } elsif ($token =~ /^$upper_pattern/) {
          $before = "(?<!$upper_pattern)";
        } else {
          $before = "(?<=$not_lower_pattern)";
        }
        my $after = ($token =~ /$upper_pattern$/) ? "(?=$not_upper_or_lower_pattern)|(?=$upper_pattern$lower_pattern)" : "(?=$not_lower_pattern)";
        while ($raw_line =~ /(?:\b|$before)($token)(?:\b|$after)/g) {
          $line_flagged = 1;
          $found_token = 1;
          my ($begin, $end, $match) = ($-[0] + 1, $+[0] + 1, $1);
          next unless $match =~ /./;
          my $wrapped = CheckSpelling::Util::wrap_in_backticks($match);
          print $warnings_fh ":$.:$begin ... $end: $wrapped\n";
        }
        unless ($found_token) {
          if ($raw_line !~ /$token.*$token/ && $raw_line =~ /($token)/) {
            my ($begin, $end, $match) = ($-[0] + 1, $+[0] + 1, $1);
            my $wrapped = CheckSpelling::Util::wrap_in_backticks($raw_token);
            print $warnings_fh ":$.:$begin ... $end: $wrapped\n";
          } else {
            my $offset = $line_length + 1;
            my $wrapped = CheckSpelling::Util::wrap_in_backticks($raw_token);
            print $warnings_fh ":$.:1 ... $offset, Warning - Could not identify whole word $wrapped in line (token-is-substring)\n";
          }
        }
      }
      if ($line_flagged && $candidates_re) {
        $_ = $previous_line_state = $initial_line_state;
        s/($candidates_re)/"="x length($1)/ge;
        if ($_ ne $initial_line_state) {
          $_ = $previous_line_state;
          for my $i (0 .. $#candidates_re_list) {
            my $candidate_re = $candidates_re_list[$i];
            next unless $candidate_re =~ /./ && $raw_line =~ /$candidate_re/;
            if (($_ =~ s/($candidate_re)/"="x length($1)/e)) {
              my ($begin, $end) = ($-[0] + 1, $+[0] + 1);
              my $hit = "$.:$begin:$end";
              $_ = $previous_line_state;
              my $replacements = ($_ =~ s/($candidate_re)/"="x length($1)/ge);
              $candidates_re_hits[$i] += $replacements;
              $candidates_re_lines[$i] = $hit unless $candidates_re_lines[$i];
              $_ = $previous_line_state;
            }
          }
        }
      }
      unless ($disable_minified_file) {
        s/={3,}//g;
        $offset += length;
        my $ratio = int($offset / $.);
        my $ratio_threshold = 1000;
        if ($ratio > $ratio_threshold) {
          skip_file($temp_dir, "average line width ($ratio) exceeds the threshold ($ratio_threshold) (minified-file)\n");
          last;
        }
      }
    }

    alarm 0;
  };
  if ($@) {
    die unless $@ eq "alarm\n";
    print $warnings_fh ":$.:1 ... 1, Warning - Could not parse file within time limit (slow-file)\n";
    skip_file($temp_dir, "it could not be parsed file within time limit (slow-file)\n");
    return $temp_dir;
  }

  close $file_fh;
  close $warnings_fh;

  if ($unrecognized || @candidates_re_hits || @forbidden_re_hits) {
    open(my $stats_fh, '>:utf8', "$temp_dir/stats");
      print $stats_fh "{words: $words, unrecognized: $unrecognized, unknown: ".(keys %unique_unrecognized).
      ", unique: ".(keys %unique).
      (@candidates_re_hits ? ", candidates: [".(join ',', @candidates_re_hits)."]" : "").
      (@candidates_re_lines ? ", candidate_lines: [".(join ',', @candidates_re_lines)."]" : "").
      (@forbidden_re_hits ? ", forbidden: [".(join ',', @forbidden_re_hits)."]" : "").
      (@forbidden_re_lines ? ", forbidden_lines: [".(join ',', @forbidden_re_lines)."]" : "").
      "}";
    close $stats_fh;
    open(my $unknown_fh, '>:utf8', "$temp_dir/unknown");
      print $unknown_fh map { "$_\n" } sort CheckSpelling::Util::case_biased keys %unique_unrecognized;
    close $unknown_fh;
  }

  return $temp_dir;
}

sub main {
  my ($configuration, @ARGV) = @_;
  our %dictionary;
  unless (%dictionary) {
    init($configuration);
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
