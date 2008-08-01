
package VNDB::VNLists;

use strict;
use warnings;
use Exporter 'import';

use vars ('$VERSION', '@EXPORT');
$VERSION = $VNDB::VERSION;
@EXPORT = qw| VNMyList VNVote RListMod RList WListMod WList |;


sub VNMyList {
  my $self = shift;
  my $user = shift;

  my $u = $self->DBGetUser(uid => $user)->[0];
  return $self->ResNotFound if !$user || !$u || !$self->AuthInfo->{id} || $self->AuthInfo->{id} != $user;

  my $f = $self->FormCheck(
    { name => 's', required => 0, default => 'title', enum => [ qw|title date| ] },
    { name => 'o', required => 0, default => 'a', enum => [ 'a','d' ] },
    { name => 'p', required => 0, template => 'int', default => 1 },
    { name => 't', required => 0, enum => [ -1..$#$VNDB::LSTAT ], default => -1 },
  );
  return $self->ResNotFound if $f->{_err};

  if($self->ReqMethod eq 'POST') {
    my $f = $self->FormCheck({ name => 'sel', required => 1, multi => 1, template => 'int' });
    $self->DBDelVNList($user, @{$f->{sel}}) if !$f->{_err};
  }

  my $order = $f->{s} . ($f->{o} eq 'a' ? ' ASC' : ' DESC');
  my($list, $np) = $self->DBGetVNList(
    uid => $u->{id},
    order => $order,
    results => 50,
    page => $f->{p},
    $f->{t} >= 0 ? (
      status => $f->{t} ) : ()
  );

  $self->ResAddTpl(vnlist => {
    npage => $np,
    page => $f->{p},
    list => $list,
    order => [ $f->{s}, $f->{o} ],
    user => $u,
    status => $f->{t},
  });
}


sub VNVote {
  my $self = shift;
  my $id = shift;

  my $uid = $self->AuthInfo()->{id};
  return $self->ResDenied() if !$uid;

  my $f = $self->FormCheck(
    { name => 'v', required => 0, default => 0, enum => [ '-1','1'..'10'] }
  );
  return $self->ResNotFound() if !$f->{v};

  
  $self->DBDelVote($uid, $id) if $f->{v} == -1 || $self->DBGetVotes(uid => $uid, vid => $id)->[0]{vid};
  $self->DBAddVote($id, $uid, $f->{v}) if $f->{v} > 0;
   
  $self->ResRedirect('/v'.$id, 'temp');
}


sub RListMod {
  my $self = shift;
  my $rid = shift;

  my $f = $self->FormCheck(
    { name => 'd', required => 0 },
    { name => 'r', required => 0, enum => [ 0..$#$VNDB::RSTAT ] },
    { name => 'v', required => 0, enum => [ 0..$#$VNDB::VSTAT ] },
  );

  return $self->ResNotFound if $f->{_err};
  return $self->ResDenied if !$self->AuthInfo->{id};

  if($f->{d}) {
    $self->DBDelRList($self->AuthInfo->{id}, $rid);
  } else {
    $self->DBEditRList(
      uid => $self->AuthInfo->{id},
      rid => $rid,
      rstat => $f->{r},
      vstat => $f->{v},
    );
  }

  my $r = $self->ReqHeader('Referer');
  $r = $r && $r =~ /([vr][0-9]+)$/ ? $1 : 'r'.$rid;
  return $self->ResRedirect('/'.$r, 'temp');
}


sub RList {
  my $self = shift;
  my $uid = shift;

  my $u = $self->DBGetUser(uid => $uid)->[0];
  return $self->ResNotFound if !$uid || !$u || (($self->AuthInfo->{id}||0) != $uid && !($u->{flags} & $VNDB::UFLAGS->{list}));

  my $f = $self->FormCheck(
    { name => 's', required => 0, default => 'title', enum => [ qw|title vote| ] },
    { name => 'o', required => 0, default => 'a', enum => [ 'a','d' ] },
    { name => 'p', required => 0, template => 'int', default => 1 },
    { name => 'c', required => 0, default => 'all', enum => [ 'a'..'z', '0', 'all' ] },
  );
  return $self->ResNotFound if $f->{_err};

  if($self->ReqMethod eq 'POST') {
    return $self->ResDenied if $uid != $self->AuthInfo->{id};
    my $frm = $self->FormCheck(
      { name => 'vnlistchange', required => 1, enum => [ 'd', 'r0'..('r'.$#$VNDB::RSTAT), 'v0'..('v'.$#$VNDB::VSTAT) ] },
      { name => 'rsel', required => 1, multi => 1, template => 'int' },
    );
    if(!$frm->{_err} && @{$frm->{rsel}}) {
      $self->DBDelRList($uid, $frm->{rsel}) if $frm->{vnlistchange} eq 'd';
      $self->DBEditRList(
        uid => $uid,
        rid => $frm->{rsel},
        substr($frm->{vnlistchange},0,1).'stat', substr($frm->{vnlistchange},1)
      ) if $frm->{vnlistchange} ne 'd';
    }
  }

  my $order = $f->{s} . ($f->{o} eq 'a' ? ' ASC' : ' DESC');
  my($list, $np) = $self->DBGetRLists(
    uid => $uid,
    results => 50,
    page => $f->{p},
    order => $order,
    char => $f->{c} eq 'all' ? undef : $f->{c},
  );

  $self->ResAddTpl(rlist => {
    user => $u,
    list => $list,
    char => $f->{c},
    order => [ $f->{s}, $f->{o} ],
    page => $f->{p},
    npage => $np,
  });
}


sub WListMod {
  my $self = shift;
  my $vid = shift;

  my $f = $self->FormCheck(
    { name => 'w', required => 1, enum => [ -1..$#$VNDB::RSTAT ] },
  );

  return $self->ResNotFound if $f->{_err};
  return $self->ResDenied if !$self->AuthInfo->{id};

  if($f->{w} == -1) {
    $self->DBDelWishList($self->AuthInfo->{id}, [ $vid ]);
  } else {
    $self->DBEditWishList(
      uid => $self->AuthInfo->{id},
      vid => $vid,
      wstat => $f->{w}
    );
  }

  return $self->ResRedirect('/v'.$vid, 'temp');
}


sub WList {
  my $self = shift;
  my $uid = shift;

  my $u = $self->DBGetUser(uid => $uid)->[0];
  return $self->ResNotFound if !$uid || !$u || (($self->AuthInfo->{id}||0) != $uid && !($u->{flags} & $VNDB::UFLAGS->{list}));

  my $f = $self->FormCheck(
    { name => 's', required => 0, default => 'title', enum => [ qw|title wstat added| ] },
    { name => 'o', required => 0, default => 'a', enum => [ 'a','d' ] },
    { name => 'p', required => 0, template => 'int', default => 1 },
  );
  return $self->ResNotFound if $f->{_err};

  if($self->ReqMethod eq 'POST') {
    return $self->ResDenied if $uid != $self->AuthInfo->{id};
    my $frm = $self->FormCheck(
      { name => 'sel', required => 1, multi => 1, template => 'int' },
      { name => 'vnlistchange', required => 1, enum => [ 'd', '0'.."$#$VNDB::WLIST" ] },
    );
    if(!$frm->{_err} && @{$frm->{sel}}) {
      $self->DBDelWishList($uid, $frm->{sel}) if $frm->{vnlistchange} eq 'd';
      $self->DBEditWishList(
        uid => $uid,
        vid => $frm->{sel},
        wstat => $frm->{vnlistchange}
      ) if $frm->{vnlistchange} ne 'd';
    }
  }

  my $order = $f->{s} . ($f->{o} eq 'a' ? ' ASC' : ' DESC');
  $order .= ', title' . ($f->{o} eq 'a' ? ' ASC' : ' DESC') if $f->{s} eq 'wstat';
  my($list, $np) = $self->DBGetWishList(
    uid => $u->{id},
    order => $order,
    results => 50,
    what => 'vn',
    page => $f->{p},
  );

  $self->ResAddTpl(wlist => {
    npage => $np,
    page => $f->{p},
    list => $list,
    order => [ $f->{s}, $f->{o} ],
    user => $u,
  });
}


1;
