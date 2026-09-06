#! -*-perl-*-

package CheckSpelling::CleanupFiles;

use Cwd 'realpath';
use File::Spec;
use CheckSpelling::Util;
use CheckSpelling::CheckDictionary;
use CheckSpelling::CheckPattern;
use CheckSpelling::EnglishList;
use Cwd qw(abs_path);

sub identity {
  my ($line) = @_;
  return ($line, '');
}

sub call_check_line {
  my ($line) = @_;
  my $warning;
  our ($check_line, $output_fh, $warnings_fh);
  ($line, $warning) = $check_line->($line);
  if ($warning ne '') {
    print $warnings_fh "$ARGV:$.:$warning";
  }
  print $output_fh $line."\n";
}

sub maybe_log_event {
  my ($handle, $message, $code) = @_;
  print $handle "$message ($code)\n" unless CheckSpelling::Util::is_ignoring_event($code);
}

sub clean_files {
  my @files = @_;
  CheckSpelling::Util::build_ignored_event_map();
  CheckSpelling::CheckPattern::reset_seen();
  my $type=CheckSpelling::Util::get_file_from_env('type');
  my $output=CheckSpelling::Util::get_file_from_env('output', '/dev/null');
  my $workspace_path=abs_path(CheckSpelling::Util::get_file_from_env('GITHUB_WORKSPACE', '.'));
  my $used_config_files=CheckSpelling::Util::get_file_from_env('used_config_files', '/dev/null');
  $ENV{comment_char}='\s*#';
  open our $warnings_fh, '>>:encoding(UTF-8)', CheckSpelling::Util::get_file_from_env('early_warnings', '/dev/null');
  open our $output_fh, '>>:encoding(UTF-8)', $output;
  open my $used_config_files_fh, '>>:encoding(UTF-8)', $used_config_files;
  my $old_file;
  our $check_line;

  if ($type =~ /^(?:line_forbidden|patterns|excludes|only|reject)$/) {
    $check_line = \&CheckSpelling::CheckPattern::process_line;
  } elsif ($type =~ /^(?:dictionary|expect|allow)$/) {
    CheckSpelling::CheckDictionary::init();
    $check_line = \&CheckSpelling::CheckDictionary::process_line;
  } else {
    $check_line = \&identity;
  }

  for my $file (@files) {
    my $maybe_bad=abs_path($file);
    if ($maybe_bad !~ /^\Q$workspace_path\E/) {
      print "::error ::Configuration files must live within $workspace_path...\n";
      print "::error ::Unfortunately, file '$file' appears to reside elsewhere.\n";
      return 3;
    }
    if ($maybe_bad =~ m{/\.git/}i) {
      print "::error ::Configuration files must not live within `.git/`...\n";
      print "::error ::Unfortunately, file '$file' appears to.\n";
      return 4;
    }
    my $fh;
    print $used_config_files_fh "$file\0";
    if (open($fh, '<:encoding(UTF-8)', $file)) {
      $ARGV = $file;
      seek($fh, -1, 2);
      read($fh, $buffer, 1);
      my $length = tell($fh);
      seek($fh, 0, 0);
      my $add_nl_at_eof = 0;
      if ($length == 0) {
        maybe_log_event(STDERR, "$file:1:1 ... 1, Notice - File is empty", 'empty-file');
      } else {
        if ($buffer !~ /\R/) {
          $add_nl_at_eof = 1;
        }
        # local $/ = undef;
        my ($nl, $first_end, $end, $line);
        my %eol_counts;
        my $content = '';
        while (!eof($fh)) {
          read $fh, $buffer, 4096;
          $content .= $buffer;
          while ($content =~ s/([^\r\n\x0b\f\x85\x{2028}\x{2029}]*)(\r\n|\n|\r|\x0b|\f|\x85|\x{2028}|\x{2029})//m) {
            ++$.;
            my ($line, $end) = ($1, $2);
            unless (defined $nl) {
              $nl = $end;
            } elsif ($end ne $nl) {
              maybe_log_event($warnings_fh, "$file:$.:$-[0] ... $+[0], Warning - Entry has inconsistent line endings", 'unexpected-line-ending');
            }
            ++$eol_counts{$end};
            my $warning;
            call_check_line($line);
          }
        }
        if ($content ne '') {
          call_check_line($content);
        }
        if ($add_nl_at_eof) {
          my $line_length = length $_;
          maybe_log_event(STDERR, "$file:$.:1 ... $length, Warning - Missing newline at end of file", 'no-newline-at-eof');
          print $output_fh "\n";
        }
        my $eol_a = $eol_counts{"\n"} || 0;
        my $eol_d = $eol_counts{"\r"} || 0;
        my $eol_d_a = $eol_counts{"\r\n"} || 0;
        my @line_endings;
        push @line_endings, "DOS [$eol_d_a]" if $eol_d_a;
        push @line_endings, "UNIX [$eol_a]" if $eol_a;
        push @line_endings, "Mac classic [$eol_d]" if $eol_d;
        if (scalar @line_endings > 1) {
          my $line_length = length $_;
          my $mixed_endings = CheckSpelling::EnglishList::build(@line_endings);
          maybe_log_event($warnings_fh, "$file:$.:1 ... $length, Warning - Mixed $mixed_endings line endings", 'mixed-line-endings');
        }
      }
      close($fh);
    } else {
      maybe_log_event($warnings_fh, "$file:1:1 ... 1, Error - $!", 'file-not-available');
    }
  }
  close $used_config_files_fh;
  close $output_fh;
  close $warnings_fh;
  return 0;
}

1;
