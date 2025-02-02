#! -*-perl-*-

package CheckSpelling::Severities;

our $VERSION='0.1.0';
our $flatten=0;

use JSON::PP;
use CheckSpelling::Util;

sub get_severities {
    my ($sarif_json) = @_;
    my %severities = ();
    my $sarif_template = CheckSpelling::Util::read_file($sarif_json);
    my $json = JSON::PP->new->utf8->pretty->sort_by(sub { $JSON::PP::a cmp $JSON::PP::b });
    my $sarif_json = $json->decode($sarif_template);
    my $rules = $sarif_json->{'runs'}[0]->{'tool'}->{'driver'}->{'rules'};
    for my $rule (@$rules) {
        my $id = $rule->{'id'};
        my $severity = $rule->{'properties'}->{"problem.severity"};
        $severity = 'notice' if $severity eq 'recommendation';
        $severity = 'notice' unless $severity =~ /\w/;
        $severities{$id} = $severity;
    }
    my $errors = CheckSpelling::Util::get_file_from_env('INPUT_ERRORS');
    my $warnings = CheckSpelling::Util::get_file_from_env('INPUT_WARNINGS');
    my $notices = CheckSpelling::Util::get_file_from_env('INPUT_NOTICES');
    my $ignored = CheckSpelling::Util::get_file_from_env('INPUT_IGNORED');
    for my $error (split /\s*,\s*/, $errors) {
        $severities{$error} = 'error';
    }
    for my $warning (split /\s*,\s*/, $warnings) {
        $severities{$warning} = 'warning';
    }
    for my $notice (split /\s*,\s*/, $notices) {
        $severities{$notice} = 'notice';
    }
    for my $ignore (split /\s*,\s*/, $ignored) {
        $severities{$ignore} = 'ignore';
    }
    return \%severities;
}

1;
