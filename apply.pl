#!/usr/bin/env perl
":" || q@<<"=END_OF_PERL"@;

use Symbol 'gensym';
use IPC::Open3;
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

my $ua = 'check-spelling-agent/0.0.3';

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
        '--connect-timeout', 3,
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

sub capture_system {
    my @args = @_;
    my $pid = open3(my $child_in, my $child_out, my $child_err = gensym, @args);
    my (@err, @out);
    while (my $output = <$child_out>) {
        push @out, $output;
    }
    while (my $error = <$child_err>) {
        push @err, $error;
    }
    waitpid( $pid, 0 );
    my $child_exit_status = $?;
    my $output_joined = join '', @out;
    my $error_joined = join '', @err;
    return ($output_joined, $error_joined, $child_exit_status);
}

sub capture_merged_system {
    my ($output_joined, $error_joined, $child_exit_status) = capture_system(@_);
    my $joiner = ($output_joined ne '') ? "\n" : '';
    return ($output_joined.$joiner.$error_joined, $child_exit_status);
}

sub compare_files {
    my ($one, $two) = @_;
    my $one_stripped = strip_comments($one);
    my $two_stripped = strip_comments($two);
    my $exit;
    (undef, undef, $exit) = capture_system(
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
    my $source = 'https://raw.githubusercontent.com/check-spelling/check-spelling/main/apply.pl';
    download_with_curl($source, $filename);
    if ($? == 0) {
        if (compare_files($filename, $0)) {
            print "Current apply script differs from '$source' (locally downloaded to `$filename`). You may wish to upgrade.\n";
        }
    }
}

sub die_with_message {
    our $program;
    my ($gh_err_text) = @_;
    if ($gh_err_text =~ /error connecting to / && $gh_err_text =~ /check your internet connection/) {
        print "$program: Internet access may be limited. Check your connection (this often happens with lousy cable internet service providers where their CG-NAT or whatever strands the modem).\n\n$gh_err_text";
        exit 5;
    }
    if ($gh_err_text =~ /proxyconnect tcp:.*connect: connection refused/) {
        print "$program: Proxy is not accepting connections.\n";
        for my $proxy (qw(http_proxy HTTP_PROXY https_proxy HTTPS_PROXY)) {
            if (defined $ENV{$proxy}) {
                print "  $proxy: '$ENV{$proxy}'\n";
            }
        }
        print "\n$gh_err_text";
        exit 6;
    }
    if ($gh_err_text =~ /dial unix .*: connect: .*/) {
        print "$program: Unix http socket is not working.\n";
        my $gh_http_unix_socket = `gh config get http_unix_socket`;
        print "  http_unix_socket: $gh_http_unix_socket\n";
        print "\n$gh_err_text";
        exit 7;
    }
}

sub gh_is_happy_internal {
    my ($output, $exit) = capture_merged_system(qw(gh api /installation/repositories));
    return ($exit, $output) if $exit == 0;
    ($output, $exit) = capture_merged_system(qw(gh api /user));
    return ($exit, $output);
}

sub gh_is_happy {
    my ($program) = @_;
    my ($gh_auth_status, $gh_status_lines) = gh_is_happy_internal();
    return 1 if $gh_auth_status == 0;
    die_with_message($gh_status_lines);

    my @problematic_env_variables;
    for my $variable (qw(GH_TOKEN GITHUB_TOKEN GITHUB_ACTIONS CI)) {
        if (defined $ENV{$variable}) {
            delete $ENV{$variable};
            push @problematic_env_variables, $variable;
            ($gh_auth_status, $gh_status_lines) = gh_is_happy_internal();
            if ($gh_auth_status == 0) {
                print STDERR "$0: gh program did not like these environment variables: ".join(', ', @problematic_env_variables)." -- consider unsetting them.\n";
                return 1;
            }
        }
    }

    print $gh_status_lines;
    return 0;
}

sub tools_are_ready {
    my ($program) = @_;
    unless (gh_is_happy($program)) {
        $! = 1;
        my $or_gh_token = (defined $ENV{CI} && $ENV{CI}) ? ' or set the GH_TOKEN environment variable' : '';
        die "$program requires a happy gh, please try 'gh auth login'$or_gh_token\n";
    }
}

sub maybe_unlink {
    unlink($_[0]) if $_[0];
}

sub run_pipe {
    my @args = @_;
    my ($out, undef, $exit) = capture_system(@args);
    return $out;
}

sub unzip_pipe {
    my ($artifact, $file) = @_;
    return run_pipe(
        'unzip',
        '-p', $artifact,
        $file
    );
}

sub retrieve_spell_check_this {
    my ($artifact, $config_ref) = @_;
    my $spell_check_this_config = unzip_pipe($artifact, 'spell_check_this.json');
    return unless $spell_check_this_config =~ /\{.*\}/s;
    my %config;
    eval { %config = %{decode_json $spell_check_this_config}; } || die "decode_json failed in retrieve_spell_check_this with '$spell_check_this_config'";
    my ($repo, $branch, $destination, $path) = ($config{url}, $config{branch}, $config{config}, $config{path});
    my $spell_check_this_dir = tempdir();
    my $exit;
    (undef, undef, $exit) = capture_system(
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
    my $should_exclude_patterns = unzip_pipe($artifact, 'should_exclude.patterns');
    unless ($should_exclude_patterns =~ /\w/) {
        $should_exclude_patterns = unzip_pipe($artifact, 'should_exclude.txt');
        return unless $should_exclude_patterns =~ /\w/;
        $should_exclude_patterns =~ s{^(.*)}{^\\Q$1\\E\$}gm;
    }
    my $need_to_add_excludes;
    my %excludes;
    if (-f $excludes) {
        open EXCLUDES, '<', $excludes;
        while (<EXCLUDES>) {
            chomp;
            next unless /./;
            $excludes{$_."\n"} = 1;
        }
        close EXCLUDES;
    } else {
        $need_to_add_excludes = 1;
    }
    for $pattern (split /\n/, $should_exclude_patterns) {
        next unless $pattern =~ /./;
        $excludes{$pattern."\n"} = 1;
    }
    open EXCLUDES, '>', $excludes;
    print EXCLUDES join "", sort case_biased keys %excludes;
    close EXCLUDES;
    system('git', 'add', '--', $excludes) if $need_to_add_excludes;
}

sub remove_stale {
    my ($artifact, $config_ref) = @_;
    my @stale = split /\s+/s, unzip_pipe($artifact, 'remove_words.txt');
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
            next if /^(?:$re)(?:(?:\r|\n)*$|[# ].*)/;
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
    my @add = split /\s+/s, (unzip_pipe($artifact, 'tokens.txt'));
    return unless @add;
    my %config = %{$config_ref};
    my $new_expect_file = $config{"new_expect_file"};
    my @words;
    make_path (dirname($new_expect_file));
    if (-s $new_expect_file) {
        open FILE, q{<}, $new_expect_file;
        local $/ = undef;
        @words = split /\s+/, <FILE>;
        close FILE;
    }
    my %items;
    @items{@words} = @words x (1);
    @items{@add} = @add x (1);
    @words = sort case_biased keys %items;
    open FILE, q{>}, $new_expect_file;
    for my $word (@words) {
        print FILE "$word\n" if $word =~ /\S/;
    };
    close FILE;
    system("git", "add", $new_expect_file);
}

sub get_artifacts {
    my ($repo, $run, $suffix) = @_;
    our $program;
    my $artifact_dir = tempdir(CLEANUP => 1);
    my $gh_err_text;
    my $artifact_name = 'check-spelling-comment';
    if ($suffix) {
        $artifact_name .= "-$suffix";
    }
    while (1) {
        ($gh_err_text, $ret) = capture_merged_system(
            'gh', 'run', 'download',
            '-D', $artifact_dir,
            '-R', $repo,
            $run,
            '-n', $artifact_name
        );
        return glob("$artifact_dir/artifact*.zip") unless ($ret >> 8);

        die_with_message($gh_err_text);
        if ($gh_err_text =~ /no valid artifacts found to download/) {
            my $expired_json = run_pipe(
                'gh', 'api',
                "/repos/$repo/actions/runs/$run/artifacts",
                '-q',
                '.artifacts.[]|select(.name=="'.$artifact_name.'")|.expired'
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
            $github_server_url = $ENV{GITHUB_SERVER_URL} || '';
            my $run_link;
            if ($github_server_url) {
                $run_link = "[$run]($github_server_url/$repo/actions/runs/$run)";
            } else {
                $run_link = "$run";
            }
            print "$program: The referenced repository ($repo) run ($run_link) does not have a corresponding artifact ($artifact_name). If it was deleted, that's unfortunate. Consider pushing a change to the branch to trigger a new run?\n";
            print "If you don't think anyone deleted the artifact, please file a bug to https://github.com/check-spelling/check-spelling/issues/new including as much information about how you triggered this error as possible.\n";
            exit 3;
        }
        unless ($gh_err_text =~ /HTTP 403: API rate limit exceeded for .*?./) {
            print "$program: Unknown error, please file a bug to https://github.com/check-spelling/check-spelling/issues/new\n";
            print $gh_err_text;
            exit 4;
        }
        my $request_id = $1 if ($gh_err_text =~ /\brequest ID\s+(\S+)/);
        my $timestamp = $1 if ($gh_err_text =~ /\btimestamp\s+(.*? UTC)/);
        my $has_gh_token = defined $ENV{GH_TOKEN} || defined $ENV{GITHUB_TOKEN};
        my $meta_url = 'https://api.github.com/meta';
        while (1) {
            my @curl_args = qw(curl);
            unless ($has_gh_token) {
                my $gh_token = `gh auth token`;
                push @curl_args, '-u', "token:$gh_token" unless $?;
            }
            push @curl_args, '-I', $meta_url;
            my ($curl_stdout, $curl_stderr, $curl_result);
            ($curl_stdout, $curl_stderr, $curl_result) = capture_system(@curl_args);
            my $delay = 1;
            if ($curl_stdout =~ m{^HTTP/\S+\s+200}) {
                if ($curl_stdout =~ m{^x-ratelimit-remaining:\s+(\d+)$}m) {
                    my $ratelimit_remaining = $1;
                    last if ($ratelimit_remaining > 10);

                    $delay = 5;
                    print STDERR "Sleeping for $delay seconds because $ratelimit_remaining is close to 0\n";
                } else {
                    print STDERR "Couldn't find x-ratelimit-remaining, will sleep for $delay\n";
                }
            } elsif ($curl_stdout =~ m{^HTTP/\S+\s+403}) {
                if ($curl_stdout =~ /^retry-after:\s+(\d+)/m) {
                    $delay = $1;
                    print STDERR "Sleeping for $delay seconds (presumably due to API rate limit)\n";
                } else {
                    print STDERR "Couldn't find retry-after, will sleep for $delay\n";
                }
            } else {
                my $response = $1 if $curl_stdout =~ m{^(HTTP/\S+)};
                print STDERR "Unexpected response ($response) from $meta_url; sleeping for $delay\n";
            }
            sleep $delay;
        }
    }
}

sub update_repository {
    my ($artifact) = @_;
    die if $artifact =~ /'/;
    our $program;
    my $apply = unzip_pipe($artifact, 'apply.json');
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

    my $git_repo_root = run_pipe('git', 'rev-parse', '--show-toplevel');
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
    our $program;
    my ($bash_script, $first, $run);
    ($program, $bash_script, $first, $run) = @_;
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
            system('unzip', '-q', '-d', $artifact_dir, $artifact, 'artifact.zip');
            @artifacts = ("$artifact_dir/artifact.zip");
        } else {
            @artifacts = ($artifact);
        }
    } else {
        my $suffix;
        if ($first =~ m{^\s*https://.*/([^/]+/[^/]+)/actions/runs/(\d+)(?:/attempts/\d+|)(?:#(\S+)|)\s*$}) {
            ($repo, $run, $suffix) = ($1, $2, $3);
        } else {
            $repo = $first;
        }
        die $syntax unless defined $repo && defined $run;
        # - 3 check for tool readiness (is `gh` working)
        tools_are_ready($program);
        @artifacts = get_artifacts($repo, $run, $suffix);
    }

    # - 5 do work
    for my $artifact (@artifacts) {
        update_repository($artifact);
    }
}

main($0 ne '-' ? $0 : 'apply.pl', $bash_script, @ARGV);
