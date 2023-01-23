#! -*-perl-*-

package CheckSpelling::DictionaryCoverage;

our $VERSION='0.1.0';
use File::Basename;
use CheckSpelling::Util;

use constant {
  NO_MATCHES => -1,
  NOT_UNIQUE => -2,
  NO_WORD_SEEN_YET => '0'
};

sub entry {
  my ($name) = @_;
  my $handle;
  unless (open ($handle, '<:utf8', $name)) {
    print STDERR "Couldn't open dictionary `$name` (dictionary-not-found)\n";
    return 0;
  }
  return {
    name => $name,
    handle => $handle,
    word => NO_WORD_SEEN_YET,
    uniq => 0,
    covered => 0
  }
}

sub update_unique {
  my ($uniq, $file_id) = @_;
  if ($uniq == NO_MATCHES) {
    $uniq = $file_id;
  } elsif ($uniq > NO_MATCHES) {
    $uniq = NOT_UNIQUE;
  }
  return $uniq;
}

sub main {
  my ($check, @dictionaries) = @_;
  my @files;
  my $unknown_words;
  unless (open($unknown_words, '<:utf8', $check)) {
    print STDERR "Could not read $check\n";
    return 0;
  }

  for my $name (@dictionaries) {
    push @files, entry($name);
  }
  my @results=@files;
  while (@files) {
    last if eof($unknown_words);
    my $unknown = <$unknown_words>;
    chomp $unknown;
    last if ($unknown eq '');
    my @drop;
    my $uniq = NO_MATCHES;
    for (my $file_id = 0; $file_id < scalar @files; $file_id++) {
      my $current = $files[$file_id];
      my ($word, $handle) = ($current->{'word'}, $current->{'handle'});
      while ($word ne '' && $word lt $unknown) {
        if (eof $handle) {
          $word = '';
        } else {
          $word = <$handle>;
          chomp $word;
        }
      }
      if ($word eq $unknown) {
        ++$current->{'covered'};
        $uniq = update_unique($uniq, $file_id);
        if (eof $handle) {
          $word = '';
        } else {
          $word = <$handle>;
          chomp $word;
        }
      }
      $current->{'word'} = $word;
      if ($word eq '') {
        push @drop, $file_id;
      }
    }
    if ($uniq > NO_MATCHES) {
      my $current = $files[$uniq];
      ++$current->{'uniq'};
    }
    if (@drop) {
      for $file_id (reverse @drop) {
        splice @files, $file_id, 1;
      }
    }
  }
  my $re=CheckSpelling::Util::get_file_from_env('aliases', '');
  my $extra_dictionaries = CheckSpelling::Util::get_file_from_env('extra_dictionaries', '');
  @dictionaries=split /\n/, $extra_dictionaries;
  for (my $file_id = 0; $file_id < scalar @results; $file_id++) {
    my $current = $results[$file_id];
    my $covered = $current->{'covered'};
    next unless $covered;

    my $handle = $current->{'handle'};

    my $name = $current->{'name'};
    my @pretty = grep m{[:/]$name}, @dictionaries;
    unless (@pretty) {
      $name = basename($name);
      @pretty = grep m{[:/]$name}, @dictionaries;
    }
    $name = $pretty[0] if @pretty;

    my $uniq = $current->{'uniq'};
    my $word = $current->{'word'};
    $word = <$handle> while !eof($handle);
    my $lines = $handle->input_line_number();

    local $_ = $name;
    eval $re;
    my $url = $_;

    my $name_without_spaces = $name;
    $name_without_spaces =~ s/\s+/_/g;

    my $unique = '';
    if ($uniq) {
      $unique = " ($uniq uniquely)";
    } else {
      $uniq = 0;
    }
    print "$covered-$lines-$uniq-$name_without_spaces [$name]($url) ($lines) covers $covered of them$unique\n";
  }
}

1;
