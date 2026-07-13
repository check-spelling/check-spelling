#!/usr/bin/env -S perl -w -Ilib

use strict;
use warnings;
use utf8;

use Cwd qw/ abs_path getcwd realpath /;
use File::Copy;
use File::Temp qw/ tempfile tempdir /;
use File::Basename;
use Test::More;
use Capture::Tiny ':all';

plan tests => 51;

my @apply_script;
{
  open(my $apply_pl, '<', 'apply.pl') || die "oops";
  open(my $apply_pm, '>', 'lib/CheckSpelling/Apply.pm') || die "oopsie";
  while (<$apply_pl>) {
    push @apply_script, $_;
    s/\bdie /CheckSpelling::Util::die_custom \$program, $., /;
    s<(^#!/usr/bin/env.*)><package CheckSpelling::Apply; use CheckSpelling::Util; $1>;
    s/(^main\()/# $1/;
    s/exit (\d+);/{ CheckSpelling::Util::tear_here($1); die "exiting"; }/;
    print $apply_pm $_;
  }
  close $apply_pm;
  close $apply_pl;

  use_ok('CheckSpelling::Apply');
}

our $spellchecker = dirname(dirname(abs_path(__FILE__)));

my $sandbox = tempdir();
chdir($sandbox);
`perl -MDevel::Cover -e 1 2>&1`;
$ENV{PERL5OPT} = '-MDevel::Cover' unless $?;
$ENV{GITHUB_WORKSPACE} = $sandbox;
$ENV{GITHUB_REF_NAME} = $ENV{GITHUB_REF};
$ENV{spellchecker} = $spellchecker;
my ($fh, $temp) = tempfile();
close $fh;
$ENV{maybe_bad} = $temp;
my ($stdout, $stderr, $result);

sub call_check_current_script {
  our $spellchecker;
  my $script = $0;
  $0 = "$spellchecker/apply.pl";
  CheckSpelling::Apply::check_current_script();
  $0 = $script;
  return 0;
}

$CheckSpelling::Apply::program = "$spellchecker/wrappers/apply.pl";

{

`git -c init.defaultBranch=something init .`;
my $user_email='user@example.com';
`
echo '{
  "expect_files": ["e.txt"],
  "new_expect_file": "new.txt",
  "excludes_file": "ex.txt",
  "spelling_config": "."
}' > apply.json;
echo '{
  "url": "./test.git",
  "branch": "left",
  "config": "output",
  "path": "child",
  "": ""
}' > spell_check_this.json;
echo 'zeebra' >> remove_words.txt;
echo 'moonkey' >> tokens.txt;
echo 'meep' >> should_exclude.txt;
zip artifact.zip spell_check_this.json remove_words.txt tokens.txt apply.json should_exclude.txt;
zip a.zip artifact.zip;
rm artifact.zip;
(echo 'aapple'; echo 'zeebra') > e.txt;
echo er > ex.txt;
git -c init.defaultBranch=wrong init test.git;
mkdir test.git/child;
touch test.git/child/file;
git -C test.git add child/file;
git -C test.git -c user.name=user -c user.email='$user_email' commit -m default;
echo hi > test.git/child/file;
git -C test.git add child/file;
git -C test.git checkout -b left 2>&1;
git -C test.git -c user.name=user -c user.email='$user_email' commit -m version;
git -C test.git checkout wrong 2>&1;
`;

sub check_check_current_script {
  return CheckSpelling::Apply::check_current_script('apply.pl');
}

$0 = '-';
($stdout, $stderr, $result) = run_sub_and_parse_outputs(\&check_check_current_script);
is($stdout, '', 'check_current_script (-) out');
is($stderr, '', 'check_current_script (-) err');
is($result, undef, 'check_current_script (-) exit code');

$0 = 't/Apply.t';
($stdout, $stderr, $result) = run_sub_and_parse_outputs(\&check_check_current_script);
like($stdout,  qr{Current apply script differs from '.*?' \(locally downloaded to `.*`\)\. You may wish to upgrade\.}, 'check_current_script (mismatch) out');
is($stderr, '', 'check_current_script (mismatch) err');
is($result, 0, 'check_current_script (mismatch) exit code');

{
  my $script = $0;
  $0 = "$spellchecker/apply.pl";
  my $full_script = (join '', @apply_script);
  my $github_api_url = $ENV{'GITHUB_API_URL'};
  $ENV{'GITHUB_API_URL'} = 'http://localhost';
  sub call_main {
    CheckSpelling::Apply::main($CheckSpelling::Apply::program, $full_script, 'nonexistent');
  }
  $ENV{'APPLY_SKIP_UPDATE_CHECK'} = 1;
  my ($stdout, $stderr, @results) = ($stdout, $stderr, $result) = run_sub_and_parse_outputs(\&call_main);
  is($stdout, '', 'main out (bad args)');
  like($stderr, qr{\Q<RUN_URL | OWNER/REPO RUN | ARTIFACT.zip>\E}, 'main err (bad args)');
  is($results[0], 1, 'main exit (bad args)');
  $ENV{'GITHUB_API_URL'} = $github_api_url;
  CheckSpelling::Apply::main($CheckSpelling::Apply::program, $full_script, 'a.zip');
  $0 = $script;
}

like(`git status |grep output/file`, qr{new file:\s+output/file$}, 'retrieve_spell_check_this added file');
is(`grep zeebra e.txt`, '', 'remove stale');
is(`grep moonkey new.txt`, 'moonkey
', 'add expect');
is(`cat ex.txt`, '^\Qmeep\E$
er
', 'add exclude (file)');
}

($stdout, $stderr, $result) = run_sub_and_parse_outputs(\&call_check_current_script);

is($stdout, '', 'apply.pl (stdout) check_current_script');
is($stderr, '', 'apply.pl (stderr) check_current_script');
is($result, 0, 'apply.pl (exit code) check_current_script');

($stdout, $stderr, $result) = run_sub_and_parse_outputs(\&call_check_current_script);

is($stdout, '', 'apply.pl (stdout) check_current_script');
is($stderr, '', 'apply.pl (stderr) check_current_script');
is($result, 0, 'apply.pl (exit code) check_current_script');

is(CheckSpelling::Apply::compare_files("$spellchecker/t/Util.t", "$spellchecker/t/Yaml.t"), 1, 'compare_files (different)');

sub run_sub_and_parse_outputs {
  my ($function) = @_;
  $CheckSpelling::Util::exited = undef;
  my ($stdout, $stderr, @results) = capture {
    local $@;
    my @results = eval {
      $function->();
    };
    if ($@) {
      return $@;
    }
    return @results;
  };
  $CheckSpelling::Util::exited = undef;
  return parse_outputs($stdout, $stderr, @results);
}

sub parse_outputs {
  my ($stdout, $stderr, @results) = @_;
  our $spellchecker;
  $stdout =~ s!$spellchecker/wrappers/apply\.pl!SPELLCHECKER/apply.pl!g;
  $stderr =~ s!$spellchecker/wrappers/apply\.pl!SPELLCHECKER/apply.pl!g;
  my $tear_code;
  if ($stderr =~ s#\n<<<TEAR HERE<<<exit: (\d+).*\n*##sm) {
    $tear_code = $1;
  }
  if ($stdout =~ s#\n<<<TEAR HERE<<<exit: (\d+).*\n*##sm) {
    $tear_code = $1;
  }

  my $result = defined $tear_code ? $tear_code : (scalar @results ? $results[0] >> 8 : undef);
  return ($stdout, $stderr, $result);
}

my $expired_artifacts = "$temp.artifacts";
my $expired_artifacts_log = "$temp.artifacts.log";
my $expired_artifact = '';
my $expired_artifact_repo = 'check-spelling/check-spelling';
my $state = 0;
my $api_url = 'https://api.github.com/repos/check-spelling-sandbox/autotest-check-spelling/actions/artifacts?name=check-spelling-comment';
my $jq_expired_artifacts_log = "$temp.jq.artifacts.log";
my $jq_expression = '.artifacts | map(select (.expired == true))[0].workflow_run.id // empty';

my $retries = 0;
my $GH_TOKEN = $ENV{GH_TOKEN};
unless (defined $GH_TOKEN) {
  $GH_TOKEN = `gh auth token`;
  chomp $GH_TOKEN;
}

# three possible passes (not counting retries for rate limits):
# 1. parse for artifact id
# 2. repository renamed (need to store updated repository id)
# 3. artifacts paginated
while ($state < 4 && $retries <= 3) {
  `curl -s -H "Authorization: token $GH_TOKEN" '$api_url' -o '$expired_artifacts' -D '$expired_artifacts_log'`;
  if (-s $expired_artifacts) {
    $expired_artifact = `grep -q '"artifacts":' '$expired_artifacts' && jq -r '$jq_expression' '$expired_artifacts' 2> '$jq_expired_artifacts_log' || touch '$jq_expired_artifacts_log'`;
    if ($?) {
      print STDERR "jq $jq_expression failed: ".`cat '$jq_expired_artifacts_log'`;
    } else {
      if ($expired_artifact =~ /^(\d+).*/) {
        $expired_artifact = $1;
        my $expired_artifact_url = `jq -r '.artifacts[] | select (.workflow_run.id==$expired_artifact) | .url' '$expired_artifacts'`;
        if ($expired_artifact_url =~ m{([^/]+/[^/]+)/actions/artifacts/\d+$}) {
          $expired_artifact_repo = $1;
        }
        last;
      }
    }
  }
  if (open(my $expired_artifacts_log_fh, '<', $expired_artifacts_log)) {
    my $http_state=0;
    while (<$expired_artifacts_log_fh>) {
      if (/^location: (.*)/) {
        $api_url = $1;
        $state++;
        last;
      }
      if (s/^link:\s+//) {
        s/,\s*/\n/g;
        if (/<(.*?)>; rel="last"/) {
          $api_url = $1;
          $state++;
          last;
        }
      }
      if (m{^HTTP/2 (40[13])}) {
        $http_state=$1;
        ++$retries;
        last if $retries > 3;
      } elsif ($http_state == 403 && m/^x-ratelimit-remaining: 0/) {
        my $sleep_delay=10+(rand(10) | 0);
        print STDERR "Hit rate limit. Sleeping $sleep_delay seconds\n";
        sleep $sleep_delay;
        last;
      }
    }
    close($expired_artifacts_log_fh);
  }
}

{
  my $os = $^O;
  $^O = 'MSWin32';
  my $path_ext = $ENV{'PATHEXT'};
  $ENV{'PATHEXT'} = '.exe;.bat;.cmd;.com';
  like(CheckSpelling::Apply::check_exists_command('git'), qr{/git}, 'check_exists_command (git)');
  $^O = $os;
  $ENV{'PATHEXT'} = $path_ext;
}

$CheckSpelling::Apply::program = 'Apply.t';
our $needs_command = 'git';
sub check_needs_command_because {
  return CheckSpelling::Apply::needs_command_because($needs_command, 'test');
}
($stdout, $stderr, $result) = run_sub_and_parse_outputs(\&check_needs_command_because);
is($stdout, '', 'needs_command_because (git)');
is($stderr, '', 'needs_command_because (git)');
is($result, undef, 'needs_command_because (git)');

$needs_command = 'imaginary-git-program';
($stdout, $stderr, $result) = run_sub_and_parse_outputs(\&check_needs_command_because);
is($stdout, '', 'needs_command_because:out (imaginary-git-program)');
like($stderr, qr{\QPlease install `imaginary-git-program` - it is needed to test at Apply.t line \E\d+}, 'needs_command_because:err (imaginary-git-program)');
is($result, 1, 'needs_command_because:result (imaginary-git-program)');

($stdout, $stderr, $result) = run_sub_and_parse_outputs(\&CheckSpelling::Apply::check_basic_tools);
is($stdout, '', 'check_basic_tools:out');
is($stderr, '', 'check_basic_tools:err');
is($result, undef, 'check_basic_tools:result');

{
  my $real_gh_token = $ENV{'GH_TOKEN'};
  my $real_github_token = $ENV{'GITHUB_TOKEN'};
  $CheckSpelling::Apply::token = '';
  $ENV{'GH_TOKEN'} = '';
  $ENV{'GITHUB_TOKEN'} = 'github-token';
  my ($token, $err);
  ($token) = CheckSpelling::Apply::get_token();
  is($token, $ENV{'GITHUB_TOKEN'}, 'get_token (GITHUB_TOKEN)');
  $CheckSpelling::Apply::token = '';
  $ENV{'GH_TOKEN'} = 'gh-token';
  ($token) = CheckSpelling::Apply::get_token();
  is($token, $ENV{'GH_TOKEN'}, 'get_token (GH_TOKEN)');
  $CheckSpelling::Apply::token = '';
  $ENV{'GH_TOKEN'} = '';
  $ENV{'GITHUB_TOKEN'} = '';
  ($token, $err) = CheckSpelling::Apply::get_token();
  if ($err) {
    is($err, 'no oauth token found for github.com', 'get_token (gh auth token - CI no token)');
  } else {
    like($token, qr{^gho_\w+$}, 'get_token (gh auth token)');
  }
  $CheckSpelling::Apply::token = '';
  $ENV{'GH_TOKEN'} = $real_gh_token;
  $ENV{'GITHUB_TOKEN'} = $real_github_token;
}

$ENV{GITHUB_API_URL} = 'https://api.github.com';
my $repository;
sub check_repository {
  CheckSpelling::Apply::get_artifacts($repository, $expired_artifact, undef);
}

SKIP: {
  skip 'could not find an expired artifact', 3 unless $expired_artifact;
  $repository = $expired_artifact_repo;
  ($stdout, $stderr, $result) = run_sub_and_parse_outputs(\&check_repository);

  my $sandbox_name = basename $sandbox;
  my $temp_name = basename $temp;
  is($stdout, "Apply.t: GitHub Run Artifact expired. You will need to trigger a new run.\n", "apply.pl (stdout) $expired_artifact_repo: expired $expired_artifact");
  is($stderr, '', "apply.pl (stderr) $expired_artifact_repo: expired $expired_artifact");
  is($result, 1, "apply.pl (exit code) $expired_artifact_repo: expired $expired_artifact");
}

$repository = "check-spelling/imaginary-repository";
($stdout, $stderr, $result) = run_sub_and_parse_outputs(\&check_repository);
like($stdout, qr{The referenced repository \(check-spelling/imaginary-repository\) may not exist, perhaps you do not have permission to see it\.\s+If the repository is hosted by GitHub Enterprise, check-spelling does not know how to integrate with it\.}, 'apply.pl (stdout) imaginary-repository');
is($stderr, '', 'apply.pl (stderr) imaginary-repository');
is($result, 8, 'apply.pl (exit code) imaginary-repository');

my $gh_token = $ENV{GH_TOKEN};
delete $ENV{GH_TOKEN};
my $real_home = $ENV{HOME};
my $real_http_socket = `gh config get http_unix_socket`;
$ENV{HOME} = $sandbox;
sub check_tools_are_not_ready {
  CheckSpelling::Apply::tools_are_ready($CheckSpelling::Apply::program);
}
($stdout, $stderr, $result) = run_sub_and_parse_outputs(\&check_tools_are_not_ready);

like($stdout, qr{gh auth login|(?:populate|set) the GH_TOKEN environment variable}, 'apply.pl (stdout) not authenticated');
like($stderr, qr{[Aa]pply.\w+ requires a happy gh, please try 'gh auth login'}, 'apply.pl (stderr) not authenticated');
is($result, 1, 'apply.pl (exit code) not authenticated');
$ENV{GH_TOKEN} = $gh_token;

if (-d "$real_home/.config/gh/") {
  mkdir "$sandbox/.config";
  mkdir "$sandbox/.config/gh";
  `cp -R '$real_home/.config/gh/'* '$sandbox/.config/gh/'`;
}

`gh config set http_unix_socket /dev/null`;
($stdout, $stderr, $result) = run_sub_and_parse_outputs(\&check_tools_are_not_ready);

like($stdout, qr{: Unix http socket is not working\.}, 'apply.pl (stdout) bad_socket');
like($stdout, qr{http_unix_socket: /dev/null}, 'apply.pl (stdout) bad_socket');
is($stderr, '', 'apply.pl (stderr) bad_socket');
is($result, 7, 'apply.pl (exit code) bad_socket');
$ENV{HOME} = $real_home;

`gh config set http_unix_socket '$real_http_socket'`;

$ENV{https_proxy}='http://localhost:9123';
$ENV{GH_TOKEN} = 'garbage';
($stdout, $stderr, $result) = run_sub_and_parse_outputs(\&check_tools_are_not_ready);

like($stdout, qr{: Proxy is not accepting connections\.}, 'apply.pl (stdout) bad_proxy');
like($stdout, qr{https_proxy: 'http://localhost:9123'}, 'apply.pl (stdout) bad_proxy');
is($stderr, '', 'apply.pl (stderr) bad_proxy');
is($result, 6, 'apply.pl (exit code) bad_proxy');
delete $ENV{'https_proxy'};
$ENV{GH_TOKEN} = $gh_token;
