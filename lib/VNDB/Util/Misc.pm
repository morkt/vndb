
package VNDB::Util::Misc;

use strict;
use warnings;
use Exporter 'import';
use VNDB::Func;

our @EXPORT = qw|filFetchDB|;


my %filfields = (
  vn      => [qw|length hasani tag_inc tag_exc taginc tagexc tagspoil lang olang plat|],
  release => [qw|type patch freeware doujin date_before date_after released minage lang olang resolution plat med voiced ani_story ani_ero|],
);


# Arguments:
#   type ('vn' or 'release'),
#   filter overwrite (string or undef),
#     when defined, these filters will be used instead of the preferences,
#     must point to a variable, will be modified in-place with the actually used filters
#   options to pass to db*Get() before the filters (hashref or undef)
#     these options can be overwritten by the filters or the next option
#   options to pass to db*Get() after the filters (hashref or undef)
#     these options overwrite all other options (pre-options and filters)

sub filFetchDB {
  my($self, $type, $overwrite, $pre, $post) = @_;
  $pre = {} if !$pre;
  $post = {} if !$post;
  my $dbfunc = $self->can($type eq 'vn' ? 'dbVNGet' : 'dbReleaseGet');
  my $prefname = 'filter_'.$type;
  my $pref = $self->authPref($prefname);

  # simply call the DB if we're not applying filters
  return $dbfunc->($self, %$pre, %$post) if !$pref && !$overwrite;

  my $filters = fil_parse $overwrite // $pref, @{$filfields{$type}};

  # compatibility
  $self->authPref($prefname => fil_serialize $filters)
    if $type eq 'vn' && _fil_vn_compat($self, $filters) && !defined $overwrite;

  # write the definite filter string in $overwrite
  $_[2] = fil_serialize({map +(
    exists($post->{$_})    ? ($_ => $post->{$_})    :
    exists($filters->{$_}) ? ($_ => $filters->{$_}) :
    exists($pre->{$_})     ? ($_ => $pre->{$_})     : (),
  ), @{$filfields{$type}}}) if defined $overwrite;

  return $dbfunc->($self, %$pre, %$filters, %$post) if defined $overwrite;

  # since incorrect filters can throw a database error, we have to special-case
  # filters that originate from a preference setting, so that in case these are
  # the cause of an error, they are removed. Not doing this will result in VNDB
  # throwing 500's even for non-browse pages. We have to do some low-level
  # PostgreSQL stuff with savepoints to ensure that an error won't affect our
  # existing transaction.
  my $dbh = $self->dbh;
  $dbh->pg_savepoint('filter');
  my($r, $np);
  my $OK = eval {
    ($r, $np) = $dbfunc->($self, %$pre, %$filters, %$post);
    1;
  };
  $dbh->pg_rollback_to('filter') if !$OK;
  $dbh->pg_release('filter');

  # error occured, let's try again without filters. if that succeeds we know
  # it's the fault of the filter preference, and we should remove it.
  if(!$OK) {
    ($r, $np) = $dbfunc->($self, %$pre, %$post);
    # if we're here, it means the previous function didn't die() (duh!)
    $self->authPref($prefname => '');
    warn sprintf "Reset filter preference for userid %d. Old: %s\n", $self->authInfo->{id}||0, $pref;
  }
  return wantarray ? ($r, $np) : $r;
}


sub _fil_vn_compat {
  my($self, $fil) = @_;

  # older tag specification (by name rather than ID)
  if($fil->{taginc} || $fil->{tagexc}) {
    my $tagfind = sub {
      return map {
        my $i = $self->dbTagGet(name => $_)->[0];
        $i && !$i->{meta} ? $i->{id} : ();
      } grep $_, ref $_[0] ? @{$_[0]} : ($_[0]||'')
    };
    $fil->{tag_inc} //= [ $tagfind->(delete $fil->{taginc}) ] if $fil->{taginc};
    $fil->{tag_exc} //= [ $tagfind->(delete $fil->{tagexc}) ] if $fil->{tagexc};
    return 1;
  }

  return 0;
}

