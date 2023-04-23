#!/usr/bin/env perl
":" || q@<<"=END_OF_PERL"@;

use File::Basename qw(dirname);
use File::Path qw(make_path);
use File::Spec::Functions qw(catfile path);
use File::Temp qw/ tempfile tempdir /;
use JSON::PP;
use warnings;

my @safe_path = qw(
    /opt/homebrew/bin
    /opt/homebrew/sbin
    /usr/local/bin
    /usr/bin
    /bin
    /usr/sbin
    /sbin
);

my $ua = 'check-spelling-agent/0.0.2';

$ENV{'PATH'} = join ':', @safe_path unless defined $ENV{SYSTEMROOT};

sub check_exists_command {
    my ($program) = @_;

    my @path = path;
    my @pathext = ('');

    if ($^O eq 'MSWin32') {
        push @pathext, map { lc } split /;/, $ENV{PATHEXT};
    }

    for my $dir (@path) {
        for my $suffix (@pathext) {
            my $f = catfile $dir, "$program$suffix";
            return $f if -x $f;
        }
    }
}

sub needs_command_because {
    my ($program, $reason) = @_;
    return if check_exists_command($program);
    die 'Please install `'.$program.'` - it is needed to '.$reason;
}

sub check_basic_tools {
    needs_command_because('git', 'interact with git repositories');
    needs_command_because('curl', 'download other tools');
    needs_command_because('gh', 'interact with github');
    #needs_command_because('magic-magic', 'debugging');
}

sub download_with_curl {
    my ($url, $dest, $flags) = @_;
    $flags = '-fsL' unless defined $flags;
    system('curl',
        '-A', $ua,
        $flags,
        '-o', $dest,
        $url
    );
}

sub tempfile_name {
    my ($fh, $filename) = tempfile();
    close $fh;
    return $filename;
}

sub strip_comments {
    my ($file) = @_;
    my ($fh, $filename) = tempfile();
    open INPUT, '<', $file;
    while (<INPUT>) {
        next if /^\s*(?:#.*)/;
        print $fh $_;
    }
    close INPUT;
    close $fh;
    return $filename;
}

sub run_program_capture_output {
    my ($output, $error, @arguments) = @_;
    $ENV{'OUTPUT'} = $output;
    $ENV{'ERROR'} = $error;
    system('/bin/sh', $0, @arguments);
}

sub run_and_swallow_output {
    run_program_capture_output('/dev/null', '/dev/null', @_);
}

sub compare_files {
    my ($one, $two) = @_;
    my $one_stripped = strip_comments($one);
    my $two_stripped = strip_comments($two);
    run_and_swallow_output(
        'diff',
        '-qwB',
        $one_stripped, $two_stripped
    );
    if ($? == -1) {
        print "could not compare '$one' and '$two': $!\n";
        return 0;
    }
    if ($? & 127) {
        printf "child died with signal %d, %s core dump\n",
        ($? & 127),  ($? & 128) ? 'with' : 'without';
        return 0;
    }
    return 0 if $? == 0;
    return 1;
}

my $bash_script=q{
=END_OF_PERL@
# bash
set -e
if [ "$OUTPUT" = "$ERROR" ]; then
    ("$@" 2>&1) > "$OUTPUT"
else
    "$@" > "$OUTPUT" 2> "$ERROR"
fi
exit
};

sub check_current_script {
    if ("$0" eq '-') {
        my ($bash_script) = @_;
        my $fh;
        ($fh, $0) = tempfile();
        $bash_script =~ s/^=.*\@$//m;
        print $fh $bash_script;
        close $fh;
        return;
    }
    my $filename = tempfile_name();
    my $source = 'https://raw.githubusercontent.com/check-spelling/check-spelling/prerelease/apply.pl';
    download_with_curl($source, $filename);
    if ($? == 0) {
        if (compare_files($filename, $0)) {
            print "Current script differs from '$source' (locally downloaded to '$filename'). You may wish to upgrade.\n";
        }
    }
}

sub gh_is_happy_internal {
    my ($gh_status) = @_;
    run_program_capture_output($gh_status, $gh_status, 'gh', 'auth', 'status');
    return $?;
}

sub gh_is_happy {
    my ($program) = @_;
    my $gh_status = tempfile_name();
    my $gh_auth_status = gh_is_happy_internal($gh_status);
    return 1 if $gh_auth_status == 0;
    my @problematic_env_variables;
    for my $variable (qw(GH_TOKEN GITHUB_TOKEN)) {
        if (defined $ENV{$variable}) {
            delete $ENV{$variable};
            push @problematic_env_variables, $variable;
            $gh_auth_status = gh_is_happy_internal($gh_status);
            return 1 if $gh_auth_status == 0;

            print STDERR "$0: gh program did not like these environment variables: ".join(', ', @problematic_env_variables)." -- consider unsetting them.\n";
            return 1;
        }
    }

    if ($gh_auth_status != 0) {
        if ($gh_auth_status >> 8) {
            open my $fh, '<', $gh_status;
            print while (<$fh>);
            close $fh;
            return 0;
        }
    }
    return 0;
}

sub tools_are_ready {
    my ($program) = @_;
    unless (gh_is_happy($program)) {
        die "$program requires a happy gh, please try 'gh auth login'\n";
    }
}

sub maybe_unlink {
    unlink($_[0]) if $_[0];
}

sub run_pipe {
    my $out = tempfile_name();
    run_program_capture_output($out, '/dev/null', @_);
    my @lines;
    open my $fh, '<', $out;
    while (<$fh>) {
        push @lines, $_;
    }
    close $fh;
    return @lines;
}

sub unzip_pipe {
    my ($artifact, $file) = @_;
    return run_pipe(
        'unzip',
        '-p', $artifact,
        $file
    );
}

sub unzip_pipe_string {
    return join '', unzip_pipe(@_);
}

sub retrieve_spell_check_this {
    my ($artifact, $config_ref) = @_;
    my $spell_check_this_config = unzip_pipe_string($artifact, 'spell_check_this.json');
    return unless $spell_check_this_config =~ /\{.*\}/s;
    my %config;
    eval { %config = %{decode_json $spell_check_this_config}; } || die "decode_json failed in retrieve_spell_check_this with '$spell_check_this_config'";
    my ($repo, $branch, $destination, $path) = ($config{url}, $config{branch}, $config{config}, $config{path});
    my $spell_check_this_dir = tempdir();
    run_and_swallow_output(
        'git', 'clone',
        '--depth', '1',
        '--no-tags',
        $repo,
        '--branch', $branch,
        $spell_check_this_dir
    );
    if ($?) {
        die "git clone $repo#$branch failed";
    }

    make_path($destination);
    system('cp', '-i', '-R', glob("$spell_check_this_dir/$path/*"), $destination);
    system('git', 'add', '-f', $destination);
}

sub case_biased {
    lc($a)."-".$a cmp lc($b)."-".$b;
}

sub add_to_excludes {
    my ($artifact, $config_ref) = @_;
    my %config = %{$config_ref};
    my $excludes = $config{"excludes_file"};
    my $should_exclude_patterns = unzip_pipe_string($artifact, 'should_exclude.patterns');
    unless ($should_exclude_patterns =~ /\w/) {
        $should_exclude_patterns = unzip_pipe_string($artifact, 'should_exclude.txt');
        return unless $should_exclude_patterns =~ /\w/;
        $should_exclude_patterns =~ s{^(.*)}{^\\Q$1\\E\$}gm;
    }
    open EXCLUDES, '<', $excludes;
    my %excludes;
    while (<EXCLUDES>) {
        chomp;
        next unless /./;
        $excludes{$_."\n"} = 1;
    }
    close EXCLUDES;
    for $pattern (split /\n/, $should_exclude_patterns) {
        next unless $pattern =~ /./;
        $excludes{$pattern."\n"} = 1;
    }
    open EXCLUDES, '>', $excludes;
    print EXCLUDES join "", sort case_biased keys %excludes;
}

sub remove_stale {
    my ($artifact, $config_ref) = @_;
    my @stale = split /\s+/s, unzip_pipe_string($artifact, 'remove_words.txt');
    return unless @stale;
    my %config = %{$config_ref};
    my @expect_files = @{$config{"expect_files"}};
    @expect_files = grep {
        print STDERR "Could not find $_\n" unless -f $_;
        -f $_;
    } @expect_files;
    unless (@expect_files) {
        die "Could not find any of the processed expect files, are you on the wrong branch?";
    }

    my $re = join "|", @stale;
    for my $file (@expect_files) {
        open INPUT, '<', $file;
        my @keep;
        while (<INPUT>) {
            next if /^(?:$re)(?:(?:\r|\n)*$| .*)/;
            push @keep, $_;
        }
        close INPUT;

        open OUTPUT, '>', $file;
        print OUTPUT join '', @keep;
        close OUTPUT;
    };
}

sub add_expect {
    my ($artifact, $config_ref) = @_;
    my @add = unzip_pipe($artifact, 'tokens.txt');
    return unless @add;
    my %config = %{$config_ref};
    my $new_expect_file = $config{"new_expect_file"};
    my @words;
    make_path (dirname($new_expect_file));
    if (-s $new_expect_file) {
        open FILE, q{<}, $new_expect_file;
        @words = <FILE>;
        close FILE;
    }
    my %items;
    @items{@words} = @words x (1);
    @items{@add} = @add x (1);
    @words = sort case_biased keys %items;
    open FILE, q{>}, $new_expect_file;
    for my $word (@words) {
        print FILE "$word" if $word =~ /\S/;
    };
    close FILE;
    system("git", "add", $new_expect_file);
}

sub get_artifacts {
    my ($program, $repo, $run) = @_;
    my $artifact_dir = tempdir(CLEANUP => 1);
    my $gh_err_text;
    my $artifact_name = 'check-spelling-comment';
    my $out = tempfile_name();

    run_program_capture_output($out, $out,
        'gh', 'run', 'download',
        '-D', $artifact_dir,
        '-R', $repo,
        $run,
        '-n', $artifact_name
    );
    my $ret = $?;
    if (($ret >> 8)) {
        open my $fh, '<', $out;
        while (<$fh>) {
            $gh_err_text .= $_;
        }
        close $fh;

        if ($gh_err_text =~ /no valid artifacts found to download/) {
            my $expired_json = join '', run_pipe(
                'gh', 'api',
                "/repos/$repo/actions/runs/$run/artifacts",
                '-q',
                '.artifacts.[]|select(.name=="check-spelling-comment")|.expired'
            );
            if ($expired_json ne '') {
                chomp $expired_json;
                my $expired;
                eval { $expired = decode_json $expired_json } || die "decode_json failed in update_repository with '$expired_json'";
                if ($expired) {
                    print "$program: GitHub Run Artifact expired. You will need to trigger a new run.\n";
                    exit 1;
                }
            }
            print "$program: GitHub Run may not have completed. If so, please wait for it to finish and try again.\n";
            exit 2;
        }
        if ($gh_err_text =~ /no artifact matches any of the names or patterns provided/) {
            print "$program: The referenced repository ($repo) run ($run) does not have a corresponding artifact ($artifact_name). If it was deleted, that's unfortunate. Consider pushing a change to the branch to trigger a new run?\n";
            print "If you don't think anyone deleted the artifact, please file a bug to https://github.com/check-spelling/check-spelling/issues/new including as much information about how you triggered this error as possible.\n";
            exit 3;
        }
        print "$program: Unknown error, please file a bug to https://github.com/check-spelling/check-spelling/issues/new\n";
        print $gh_err_text;
        exit 4;
    }
    return glob("$artifact_dir/artifact*.zip");
}

sub update_repository {
    my ($program, $artifact) = @_;
    die if $artifact =~ /'/;
    my $apply = unzip_pipe_string($artifact, 'apply.json');
    unless ($apply =~ /\{.*\}/s) {
        print STDERR "$program: Could not retrieve valid apply.json from artifact\n";
        $apply = '{
            "expect_files": [".github/actions/spelling/expect.txt"],
            "new_expect_file": ".github/actions/spelling/expect.txt",
            "excludes_file": ".github/actions/spelling/excludes.txt",
            "spelling_config": ".github/actions/spelling"
        }';
    }
    my $config_ref;
    eval { $config_ref = decode_json($apply); } ||
        die "$program: decode_json failed in update_repository with '$apply'";

    my $git_repo_root = join '', run_pipe('git', 'rev-parse', '--show-toplevel');
    chomp $git_repo_root;
    die "$program: Could not find git repo root..." unless $git_repo_root =~ /\w/;
    chdir $git_repo_root;

    retrieve_spell_check_this($artifact, $config_ref);
    remove_stale($artifact, $config_ref);
    add_expect($artifact, $config_ref);
    add_to_excludes($artifact, $config_ref);
    system('git', 'add', '-u', '--', $config_ref->{'spelling_config'});
}

sub main {
    my ($program, $bash_script, $first, $run) = @_;
    my $syntax = "$program <RUN_URL | OWNER/REPO RUN | ARTIFACT.zip>";
    # Stages
    # - 1 check for tools basic
    check_basic_tools();
    # - 2 check for current
    # -> 1 download the latest version to a temp file
    # -> 2. parse current and latest (stripping comments) and compare (whitespace insensitively)
    # -> 3. offer to update if the latest version is different
    check_current_script($bash_script);
    # - 4 parse arguments
    die $syntax unless defined $first;
    my $repo;
    my @artifacts;
    if (-s $first) {
        my $artifact = $first;
        open my $artifact_reader, '-|', 'unzip', '-l', $artifact;
        my ($has_artifact, $only_file) = (0, 0);
        while (my $line = <$artifact_reader>) {
            chomp $line;
            if ($line =~ /\s+artifact\.zip$/) {
                $has_artifact = 1;
                next;
            }
            if ($line =~ /\s+1 file$/) {
                $only_file = 1;
                next;
            }
            $only_file = 0 if $only_file;
        }
        close $artifact_reader;
        if ($has_artifact && $only_file) {
            my $artifact_dir = tempdir(CLEANUP => 1);
            my ($fh, $gh_err) = tempfile();
            close $fh;
            system('unzip', '-d', $artifact_dir, $artifact, 'artifact.zip');
            @artifacts = ("$artifact_dir/artifact.zip");
        } else {
            @artifacts = ($artifact);
        }
    } else {
        if ($first =~ m{^\s*https://.*/([^/]+/[^/]+)/actions/runs/(\d+)(?:/attempts/\d+|)\s*$}) {
            ($repo, $run) = ($1, $2);
        } else {
            $repo = $first;
        }
        die $syntax unless defined $repo && defined $run;
        # - 3 check for tool readiness (is `gh` working)
        tools_are_ready($program);
        @artifacts = get_artifacts($program, $repo, $run);
    }

    # - 5 do work
    for my $artifact (@artifacts) {
        update_repository($program, $artifact);
    }
}

main($0 ne '-' ? $0 : 'apply.pl', $bash_script, @ARGV);
