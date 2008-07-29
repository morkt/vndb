
package VNDB::VNLists;

use strict;
use warnings;
use Exporter 'import';

use vars ('$VERSION', '@EXPORT');
$VERSION = $VNDB::VERSION;
@EXPORT = qw| VNListMod VNMyList VNVote RListMod RList |;


sub VNListMod {
  my $self = shift;
  my $vid = shift;

  my $uid = $self->AuthInfo()->{id};
  return $self->ResDenied() if !$uid;

  my $f = $self->FormCheck(
    { name => 's', required => 1, enum => [ -1..$#$VNDB::LSTAT ] },
    { name => 'c', required => 0, default => '', maxlength => 500 },
  );
  return $self->ResNotFound if $f->{_err};

  if($f->{s} == -1) {
    $self->DBDelVNList($uid, $vid);
  } elsif($self->DBGetVNList(uid => $uid, vid => $vid)->[0]{vid}) {
    $self->DBEditVNList(uid => $uid, status => $f->{s}, vid => [ $vid ],
      $f->{s} == 6 ? ( comments => $f->{c} ) : ());
  } else {
    $self->DBAddVNList($uid, $vid, $f->{s}, $f->{c});
  }
   
  $self->ResRedirect('/v'.$vid, 'temp');
}


sub VNMyList {
  my $self = shift;
  my $user = shift;

  my $u = $self->DBGetUser(uid => $user)->[0];
  return $self->ResNotFound if !$user || !$u || (($self->AuthInfo->{id}||0) != $user && !($u->{flags} & $VNDB::UFLAGS->{list}));

  my $f = $self->FormCheck(
    { name => 's', required => 0, default => 'title', enum => [ qw|title date| ] },
    { name => 'o', required => 0, default => 'a', enum => [ 'a','d' ] },
    { name => 'p', required => 0, template => 'int', default => 1 },
    { name => 't', required => 0, enum => [ -1..$#$VNDB::LSTAT ], default => -1 },
  );
  return $self->ResNotFound if $f->{_err};

  if($self->ReqMethod eq 'POST') {
    my $frm = $self->FormCheck(
      { name => 'vnlistchange', required => 1, enum => [ -2..$#$VNDB::LSTAT ] },
      { name => 'comments', required => 0, default => '', maxlength => 500 },
      { name => 'sel', required => 1, multi => 1 },
    );
    if(!$frm->{_err}) {
      my @change = map { /^[0-9]+$/ ? $_ : () } @{$frm->{sel}};
      $self->DBDelVNList($user, @change) if @change && $frm->{vnlistchange} eq '-1';
      $self->DBEditVNList(
        uid => $user,
        vid => \@change,
        $frm->{vnlistchange} eq '-2' ? (
          comments => $frm->{comments}
        ) : (
          status => $frm->{vnlistchange}
        ),
      ) if @change && $frm->{vnlistchange} ne '-1';
    }
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


1;
