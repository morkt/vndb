
package VNDB::Util::Misc;

use strict;
use warnings;
use Exporter 'import';
use TUWF ':html';
use VNDB::Func;

our @EXPORT = qw|filFetchDB bbSubstLinks|;


our %filfields = (
  vn      => [qw|length hasani hasshot tag_inc tag_exc taginc tagexc tagspoil lang olang plat ul_notblack ul_onwish ul_voted ul_onlist|],
  release => [qw|type patch freeware doujin date_before date_after released minage lang olang resolution plat med voiced ani_story ani_ero|],
  char    => [qw|gender bloodt bust_min bust_max waist_min waist_max hip_min hip_max height_min height_max weight_min weight_max trait_inc trait_exc tagspoil role|],
  staff   => [qw|gender role truename lang|],
);


# Arguments:
#   type ('vn', 'release' or 'char'),
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
  my $dbfunc = $self->can($type eq 'vn' ? 'dbVNGet' : $type eq 'release' ? 'dbReleaseGet' : $type eq 'char' ? 'dbCharGet' : 'dbStaffGet');
  my $prefname = 'filter_'.$type;
  my $pref = $self->authPref($prefname);

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

  return $dbfunc->($self, %$pre, %$filters, %$post) if defined $overwrite or !keys %$filters;;

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


sub bbSubstLinks {
  my ($self, $msg) = @_;

  # pre-parse vndb links within message body
  my (%lookup, %links);
  while ($msg =~ m/(?:^|\s)\K([vcpgis])([1-9][0-9]*)\b/g) {
    $lookup{$1}{$2} = 1;
  }
  return $msg unless %lookup;
  my @opt = (results => 50);
  # lookup parsed links
  if ($lookup{v}) {
    $links{"v$_->{id}"} = $_->{title} for (@{$self->dbVNGet(id => [keys %{$lookup{v}}], @opt)});
  }
  if ($lookup{c}) {
    $links{"c$_->{id}"} = $_->{name} for (@{$self->dbCharGet(id => [keys %{$lookup{c}}], @opt)});
  }
  if ($lookup{p}) {
    $links{"p$_->{id}"} = $_->{name} for (@{$self->dbProducerGet(id => [keys %{$lookup{p}}], @opt)});
  }
  if ($lookup{g}) {
    $links{"g$_->{id}"} = $_->{name} for (@{$self->dbTagGet(id => [keys %{$lookup{g}}], @opt)});
  }
  if ($lookup{i}) {
    $links{"i$_->{id}"} = $_->{name} for (@{$self->dbTraitGet(id => [keys %{$lookup{i}}], @opt)});
  }
  if ($lookup{s}) {
    $links{"s$_->{id}"} = $_->{name} for (@{$self->dbStaffGet(id => [keys %{$lookup{s}}], @opt)});
  }
  return $msg unless %links;
  my($result, @open) = ('', 'first');

  while($msg =~ m{
    (?:\b([tdvprcugis][1-9]\d*)(?:\.[1-9]\d*)?\b) | # 1. id
    (\[[^\s\]]+\])                                | # 2. tag
    ((?:https?|ftp)://[^><"\n\s\]\[]+[\d\w=/-])     # 3. url
  }x) {
    my($match, $id, $tag) = ($&, $1, $2);
    $result .= $`;
    $msg = $';

    if($open[$#open] ne 'raw' && $open[$#open] ne 'code') {
      # handle tags
      if($tag) {
        $tag = lc $tag;
        if($tag eq '[raw]') {
          push @open, 'raw';
        } elsif($tag eq '[quote]') {
          push @open, 'quote';
        } elsif($tag eq '[code]') {
          push @open, 'code';
        } elsif($tag eq '[/quote]' && $open[$#open] eq 'quote') {
          pop @open;
        } elsif($match =~ m{\[url=((https?://|/)[^\]>]+)\]}i) {
          push @open, 'url';
        } elsif($tag eq '[/url]' && $open[$#open] eq 'url') {
          pop @open;
        }
      } elsif($id && !grep(/^(?:quote|url)/, @open) && $links{$id}) {
        $match = sprintf '[url=/%s]%s[/url]', $match, $links{$id};
      }
    }
    pop @open if($tag && $open[$#open] eq 'raw'  && lc$tag eq '[/raw]');
    pop @open if($tag && $open[$#open] eq 'code' && lc$tag eq '[/code]');

    $result .= $match;
  }
  $result .= $msg;

  return $result;
}

1;

