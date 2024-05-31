#! -*-perl-*-

package CheckSpelling::EnglishList;

sub build {
  my @args=@_;
  @args = grep(/\w/, @args);
  my ($junction, $use_comma);
  my $arg_count=scalar @args;
  return '' if $arg_count == 0;
  return $args[0] if $arg_count == 1;
  $args[$arg_count - 1]="and $args[$arg_count - 1]";
  return join (($arg_count > 2 ? ', ' : ' '), @args);
}

1;
