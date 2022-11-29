#!/usr/bin/env perl

use File::Path qw(make_path);
use File::Basename qw(dirname);
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

my $ua = 'check-spelling-agent/0.0.1';

$ENV{'PATH'} = join ':', @safe_path unless defined $ENV{SYSTEMROOT};

sub check_exists_command {
    my $check = `/bin/sh -c 'command -v $_[0]'`;
    return $check;
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
    `curl -A '$ua' $flags -o '$dest' '$url'`;
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

sub compare_files {
    my ($one, $two) = @_;
    my $one_stripped = strip_comments($one);
    my $two_stripped = strip_comments($two);
    `diff -qwB '$one' '$two'`;
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

sub check_current_script {
    return if "$0" eq '-';
    my ($fh, $filename) = tempfile();
    close $fh;
    my $source = 'https://raw.githubusercontent.com/check-spelling/check-spelling/prerelease/apply.pl';
    download_with_curl($source, $filename);
    if ($? == 0) {
        if (compare_files($filename, $0)) {
            print "Current script differs from '$source' (locally downloaded to '$filename'). You may wish to upgrade.\n";
        }
    }
}

sub gh_is_happy {
    my $gh_auth_status = `gh auth status 2>&1`;
    return 1 if $? == 0;
    if ($? != 0) {
        if ($? >> 8) {
            print $gh_auth_status;
            return 0;
        }
    }
    return 0;
}

sub tools_are_ready {
    unless (gh_is_happy()) {
        die "$0 requires a happy gh, please try 'gh auth login'\n";
    }
}

sub maybe_unlink {
    unlink($_[0]) if $_[0];
}

sub retrieve_spell_check_this {
    my ($artifact, $config_ref) = @_;
    my $spell_check_this_config = `unzip -p '$artifact' 'spell_check_this.json' 2>/dev/null`;
    return unless $spell_check_this_config =~ /\{.*\}/s;
    my %config;
    eval { %config = %{decode_json $spell_check_this_config}; } || die "decode_json failed in retrieve_spell_check_this with '$spell_check_this_config'";
    my ($repo, $branch, $destination, $path) = ($config{url}, $config{branch}, $config{config}, $config{path});
    $spell_check_this_dir = tempdir();
    system("git clone --depth 1 --no-tags $repo --branch $branch $spell_check_this_dir > /dev/null 2> /dev/null");
    make_path($destination);
    system("cp -i -R \$(cd '$spell_check_this_dir/$path/'; pwd)/* '$destination'");
    system("git add '$destination'");
}

sub case_biased {
    lc($a)."-".$a cmp lc($b)."-".$b;
}

sub add_to_excludes {
    my ($artifact, $config_ref) = @_;
    my %config = %{$config_ref};
    my $excludes = $config{"excludes_file"};
    my $should_exclude_patterns = `unzip -p '$artifact' should_exclude.txt 2>/dev/null`;
    return unless $should_exclude_patterns =~ /\w/;
    $should_exclude_patterns =~ s{^(.*)}{^\\Q$1\\E\$}gm;
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
    my @stale = split /\s+/s, `unzip -p '$artifact' remove_words.txt 2>/dev/null`;
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
    my $suffix = ".".time();
    my $old_argv = '';
    for my $file (@expect_files) {
        my $rewritten = "$file$suffix";
        open INPUT, '<', $file;
        open OUTPUT, '>', $rewritten;
        while (<INPUT>) {
            next if /^(?:$re)(?:(?:\r|\n)*$| .*)/;
            print OUTPUT $_;
        }
        close OUTPUT;
        close INPUT;
        rename($rewritten, $file);
    };
}

sub add_expect {
    my ($artifact, $config_ref) = @_;
    my @add = `unzip -p '$artifact' tokens.txt 2>/dev/null`;
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
        chomp $word;
        print FILE "$word\n" if $word =~ /\w/;
    };
    close FILE;
    system("git", "add", $new_expect_file);
}

sub get_artifact {
    my ($program, $repo, $run) = @_;
    my $artifact_dir = tempdir(CLEANUP => 1);
    my ($fh, $gh_err) = tempfile();
    close $fh;

    my $ret = system("gh run download -D '$artifact_dir' -R '$repo' '$run' -n check-spelling-comment 2> '$gh_err'");
    if (($ret >> 8)) {
        open GH_ERR, '<', $gh_err;
            local $/;
            $gh_err_text = <GH_ERR>;
        close GH_ERR;
        if ($gh_err_text =~ /no valid artifacts found to download/) {
            my $expired_json = `gh api /repos/$repo/actions/runs/$run/artifacts -q '.artifacts.[]|select(.name=="check-spelling-comment")|.expired'`;
            if ($expired_json ne '') {
                chomp $expired_json;
                my $expired;
                eval { $expired = decode_json $expired_json } || die "decode_json failed in update_repository with '$expired_json'";
                if ($expired) {
                    print "Run artifact expired. You will need to trigger a new run.\n";
                    exit 1;
                }
            }
            print "Run may not have completed. If so, please wait for it to finish and try again.\n";
            exit 2;
        }
        if ($gh_err_text =~ /no artifact matches any of the names or patterns provided/) {
            print "unexpected error, please file a bug to https://github.com/check-spelling/check-spelling/issues/new\n";
            print $gh_err;
            exit 3;
        }
        print "unknown error, please file a bug to https://github.com/check-spelling/check-spelling/issues/new\n";
        print "$gh_err";
        exit 4;
    }
    return "$artifact_dir/artifact.zip";
}

sub update_repository {
    my ($program, $artifact) = @_;
    die if $artifact =~ /'/;
    my $apply = `unzip -p '$artifact' 'apply.json' 2>/dev/null`;
    unless ($apply =~ /\{.*\}/s) {
        print STDERR "Could not retrieve valid apply.json from artifact\n";
        $apply = '{
            "expect_files": [".github/actions/spelling/expect.txt"],
            "new_expect_file": ".github/actions/spelling/expect.txt",
            "excludes_file": ".github/actions/spelling/excludes.txt",
            "config": ".github/actions/spelling"
        }';
    }
    my $config_ref;
    eval { $config_ref = decode_json($apply); } ||
        die "decode_json failed in update_repository with '$apply'";

    my $git_repo_root = `git rev-parse --show-toplevel`;
    chomp $git_repo_root;
    die "$program could not find git repo root..." unless $git_repo_root =~ /\w/;
    chdir $git_repo_root;

    retrieve_spell_check_this($artifact, $config_ref);
    remove_stale($artifact, $config_ref);
    add_expect($artifact, $config_ref);
    add_to_excludes($artifact, $config_ref);
    system("git add -u");
}

sub main {
    my ($program, $first, $run) = @_;
    my $syntax = "$program <RUN_URL | OWNER/REPO RUN | ARTIFACT.zip>";
    # Stages
    # - 1 check for tools basic
    check_basic_tools();
    # - 2 check for current
    # -> 1 download the latest version to a temp file
    # -> 2. parse current and latest (stripping comments) and compare (whitespace insensitively)
    # -> 3. offer to update if the latest version is different
    check_current_script();
    # - 4 parse arguments
    die $syntax unless defined $first;
    my ($repo, $artifact);
    if (-s $first) {
        $artifact = $first;
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
            $artifact = "$artifact_dir/artifact.zip";
        }
    } else {
        if ($first =~ m{^\s*https://.*/([^/]+/[^/]+)/actions/runs/(\d+)(?:/attempts/\d+|)\s*$}) {
            ($repo, $run) = ($1, $2);
        } else {
            $repo = $first;
        }
        die $syntax unless defined $repo && defined $run;
        # - 3 check for tool readiness (is `gh` working)
        tools_are_ready();
        $artifact = get_artifact($program, $repo, $run);
    }

    # - 5 do work
    update_repository($program, $artifact);
}
main($0, @ARGV);
