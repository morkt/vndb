
package VNDB::Util::Misc;

use strict;
use warnings;
use Exporter 'import';
use TUWF ':html';
use VNDB::Func;
use Socket 'inet_pton', 'inet_ntop', 'AF_INET6';

our @EXPORT = qw|filFetchDB ieCheck normIP|;


my %filfields = (
  vn      => [qw|length hasani tag_inc tag_exc taginc tagexc tagspoil lang olang plat ul_notblack ul_onwish ul_voted ul_onlist|],
  release => [qw|type patch freeware doujin date_before date_after released minage lang olang resolution plat med voiced ani_story ani_ero|],
  char    => [qw|gender bloodt bust_min bust_max waist_min waist_max hip_min hip_max height_min height_max weight_min weight_max trait_inc trait_exc tagspoil role|],
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
  my $dbfunc = $self->can($type eq 'vn' ? 'dbVNGet' : $type eq 'release' ? 'dbReleaseGet' : 'dbCharGet');
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


sub ieCheck {
  my $self = shift;

  return 1 if !$self->reqHeader('User-Agent') ||
    $self->reqHeader('User-Agent') !~ /MSIE [67]/ || $self->reqCookie('ie_sucks');

  if($self->reqGet('i-still-want-access')) {
    (my $ref = $self->reqHeader('Referer') || '/') =~ s/^\Q$self->{url}//;
    $self->resRedirect($ref, 'temp');
    $self->resCookie('ie_sucks' => 1);
    return;
  }

  html;
   head;
    title 'Your browser sucks';
    style type => 'text/css',
      q|body { background: black }|
     .q|div  { position: absolute; left: 50%; top: 50%; width: 500px; margin-left: -250px; height: 180px; margin-top: -90px; background-color: #012; border: 1px solid #258; text-align: center; }|
     .q|p    { color: #ddd; margin: 10px; font: 9pt "Tahoma"; }|
     .q|h1   { color: #258; font-size: 14pt; font-family: "Futura", "Century New Gothic", "Arial", Serif; font-weight: normal; margin: 10px 0 0 0; } |
     .q|a    { color: #fff }|;
   end 'head';
   body;
    div;
     h1 'Oops, we were too lazy to support your browser!';
     p;
      lit qq|We decided to stop supporting Internet Explorer 6 and 7, as it's a royal pain in |
         .qq|the ass to make our site look good in a browser that doesn't want to cooperate with us.<br />|
         .qq|You can try one of the following free alternatives: |
         .qq|<a href="http://www.mozilla.com/firefox/">Firefox</a>, |
         .qq|<a href="http://www.opera.com/">Opera</a>, |
         .qq|<a href="http://www.apple.com/safari/">Safari</a>, or |
         .qq|<a href="http://www.google.com/chrome">Chrome</a>.<br /><br />|
         .qq|If you're really stubborn about using Internet Explorer, upgrading to version 8 will also work.<br /><br />|
         .qq|...and if you're mad, you can also choose to ignore this warning and |
         .qq|<a href="/?i-still-want-access=1">open the site anyway</a>.|;
     end;
    end;
   end 'body';
  end 'html';
  return 0;
}


# Normalized IP address to use for duplicate detection/throttling. For IPv4
# this is just the normal address, but for IPv6 this is the /48 subnet, with
# the rest of the address zero'd.
sub normIP {
    my $s = shift;
    my $ip = $s->reqIP();
    return $ip if $ip !~ /:/;

    # There's a whole bunch of IPv6 manipulation modules on CPAN, but many seem
    # quite bloated and still don't offer the functionality to return an IP
    # with its mask applied (admittedly not a common operation). The libc
    # socket functions will do fine in parsing and formatting IPv6 addresses,
    # and the actual masking is quite trivial in binary form.
    $ip = inet_pton AF_INET6, $ip;
    return '::' if !$ip;
    $ip =~ s/^(.{6}).+$/$1 . "\0"x10/e;
    return inet_ntop AF_INET6, $ip;
}

1;

