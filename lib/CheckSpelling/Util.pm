#! -*-perl-*-

use v5.20;
use utf8;
use feature 'unicode_strings';

package CheckSpelling::Util;

use Encode qw/decode_utf8 encode_utf8 FB_DEFAULT/;
use HTTP::Date;
use feature 'signatures';
no warnings qw(experimental::signatures);

our $VERSION='0.1.0';

sub get_file_from_env {
  my ($var, $fallback) = @_;
  return $fallback unless defined $ENV{$var};
  $ENV{$var} =~ /(.*)/s;
  return $fallback if $1 eq '';
  return $1;
}

sub get_file_from_env_utf8 {
  return decode_utf8(get_file_from_env(@_));
}

sub get_val_from_env {
  my ($var, $fallback) = @_;
  return $fallback unless defined $ENV{$var};
  return $fallback unless $ENV{$var} =~ /^(\d+)$/;
  return $1 || $fallback;
}

sub case_biased :prototype($$) ($a, $b) {
  lc($a) cmp lc($b) || $a cmp $b;
}

sub number_biased :prototype($$) ($a, $b) {
  my ($aUnchecked, $bUnchecked) = ($a, $b);
  while ($aUnchecked ne '' && $bUnchecked ne '') {
    my ($aNumber, $bNumber);
    if ($aUnchecked =~ m/^(\d+)(.*)/) {
      $aNumber = $1;
      $aUnchecked = $2;
    }
    if ($bUnchecked =~ m/^(\d+)(.*)/) {
      $bNumber = $1;
      $bUnchecked = $2;
    }
    if (defined $aNumber && defined $bNumber) {
      return $aNumber <=> $bNumber if ($aNumber != $bNumber);
    } else {
      return $aNumber cmp $bUnchecked if defined $aNumber;
      return $aUnchecked cmp $bNumber if defined $bNumber;
      my ($aLetters, $bLetters);
      $aUnchecked =~ m/^(\D+)(.*)/;
      $aLetters = $1;
      $aUnchecked = $2;

      $bUnchecked =~ m/^(\D+)(.*)/;
      $bLetters = $1;
      $bUnchecked = $2;

      return case_biased($aLetters, $bLetters) if (defined $aLetters && defined $bLetters && !($aLetters eq $bLetters));
    }
  }
  return $aUnchecked cmp $bUnchecked;
}

sub list_with_terminator {
  my ($terminator, @list) = @_;
  return join "", map { "$_$terminator" } @list;
}

sub read_file {
  my ($name) = @_;
  local $/ = undef;
  my ($text, $file);
  if (open $file, '<:utf8', $name) {
    $text = <$file>;
    close $file;
  } else {
    print STDERR "Could not open file ($name)\n";
  }
  return $text;
}

sub maybe_str2time {
  my ($time) = @_;
  $time = str2time $time;
  return $time if $time;
}

sub print_insert {
  open INSERT, "<", $ENV{insert};
  local $/=undef;
  print <INSERT>;
  print "\n";
  close INSERT;
}

sub insert_into_summary {
  my $state=0;
  open BASE, "<", $ENV{base};
  while (<BASE>){
    if ($state==0) {
      $state = 1 if /^(?:#+ |<details><summary>)Unrecognized words/;
    } elsif ($state==1) {
      if (/<details><summary>These words/) {
        $state=2;
      } elsif (m{<details><summary>To accept }) {
        $state=3;
        print_insert();
        print "**OR**\n\n\n";
      } elsif (m{^<details><summary>}) {
        $state=3;
        print_insert();
      }
    } elsif ($state==2) {
      $state=1 if m{^</details><p></p>};
    }
    print;
  }
  close BASE;
}

sub build_ignored_event_map {
  my $ignored_events = get_file_from_env('ignored_events', '');
  our %ignored_event_map = ();
  for my $event (split /,/, $ignored_events) {
    $ignored_event_map{$event} = 1;
  }
}

sub is_ignoring_event {
  our %ignored_event_map;
  my ($code) = @_;
  return 1 if $ignored_event_map{$code};
  return 0;
}

sub calculate_delay {
  my (@lines) = @_;
  my $now_stamp = time;
  my ($requested, $expires, $delay);
  for my $line (@lines) {
    if ($line =~ /^date:\s*(.*)/i) {
      $requested = maybe_str2time($1);
      next;
    }
    if ($line =~ /^expires:\s*(.*)/i) {
      $expires = maybe_str2time($1);
      next;
    }
    next unless $line =~ /^retry-after:\s*(\d+)/i;
    $delay = $1 || 1;
  }
  return $delay if defined $delay;
  if (defined $requested && defined $expires) {
    $delay = $expires - $requested;
  }
  $delay = 5 unless defined $delay && $delay > 0;

  return $delay;
}

sub truncate_with_ellipsis {
  my ($text, $length) = @_;
  $text =~ s/^(.{$length}).{4,}?(\s?`+|)$/$1$2…/;
  return $text;
}

sub wrap_in_backticks {
  my ($a) = @_;
  my $longest = 0;
  while ($a =~ /(`+)/g) {
    my $length = length $1;
    $longest = $length if $length > $longest;
  }
  my $q = '`'x ($longest + 1);
  $a = " $a " if ($a =~ /^`|`$/);
  return "$q$a$q";
}

sub tear_here {
  my ($exit) = @_;
  our $exited;
  return if defined $exited;
  print STDERR "\n<<<TEAR HERE<<<exit: $exit\n";
  print STDOUT "\n<<<TEAR HERE<<<exit: $exit\n";
  $exited = $exit;
}
sub die_custom {
  my ($program, $line, $message) = @_;
  print STDERR "$message at $program line $line.\n";
  tear_here(1);
  die "stopping";
}

1;
