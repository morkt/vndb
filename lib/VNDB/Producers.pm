
package VNDB::Producers;

use strict;
use warnings;
use Exporter 'import';
use Digest::MD5;

use vars ('$VERSION', '@EXPORT');
$VERSION = $VNDB::VERSION;
@EXPORT = qw| PPage PBrowse PEdit PLock PHide PXML |;


sub PPage {
  my $self = shift;
  my $id = shift;


  my $r = $self->FormCheck(
    { name => 'rev',  required => 0, default => 0, template => 'int' },
    { name => 'diff', required => 0, default => 0, template => 'int' },
  );
  
  my $p = $self->DBGetProducer(
    id => $id,
    $r->{rev} ? ( what => 'changes' ) : (),
    $r->{rev} ? ( rev => $r->{rev} ) : ()
  )->[0];
  return $self->ResNotFound if !$p->{id};

  $r->{diff} ||= $p->{prev} if $r->{rev};
  my $c = $r->{diff} && $self->DBGetProducer(id => $id, rev => $r->{diff}, what => 'changes')->[0];
  $p->{next} = $self->DBGetHist(type => 'p', id => $id, next => $p->{cid}, showhid => 1)->[0]{id} if $r->{rev};

  return $self->ResAddTpl(ppage => {
    prod => $p,
    prev => $c,
    change => $r->{diff} || $r->{rev},
    vn => $self->DBGetProducerVN($id),
  });
}


sub PBrowse {
  my $self = shift;
  my $chr = shift;
  $chr = 'all' if !defined $chr;

  my $p = $self->FormCheck(
    { name => 'p', required => 0, default => 1, template => 'int' },
    { name => 'q', required => 0, default => '' }
  );

  my($r, $np) = $self->DBGetProducer(
    $chr ne 'all' ? (
      char => $chr ) : (),
    $p->{q} ? (
      search => $p->{q} ) : (),
    page => $p->{p},
    results => 50,
  );

  $self->ResAddTpl(pbrowse => {
    prods => $r,
    page => $p->{p},
    npage => $np,
    query => $p->{q},
    chr => $chr,
  });
}


sub PEdit {
  my $self = shift;
  my $id = shift || 0; # 0 = new

  my $rev = $self->FormCheck({ name => 'rev',  required => 0, default => 0, template => 'int' })->{rev};

  my $p = $self->DBGetProducer(id => $id, what => 'changes', $rev ? ( rev => $rev ) : ())->[0] if $id;
  return $self->ResNotFound() if $id && !$p;

  return $self->ResDenied if !$self->AuthCan('edit') || ($p->{locked} && !$self->AuthCan('lock'));


  my %b4 = $id ? (
    map { $_ => $p->{$_} } qw|name original website type lang desc|
  ) : ();
  
  my $frm = {};
  if($self->ReqMethod() eq 'POST') {
    $frm = $self->FormCheck(
      { name => 'type', required => 1, enum => [ keys %$VNDB::PROT ] },
      { name => 'name',  required => 1, maxlength => 200 },
      { name => 'original', required => 0, maxlength => 200, default => '' },
      { name => 'lang', required => 1, enum => [ keys %$VNDB::LANG ] },
      { name => 'website', required => 0, maxlength => 200, template => 'url', default => '' },
      { name => 'desc', required => 0, maxlength => 10240, default => '' },
      { name => 'comm', required => 0, default => '' },
    );

    return $self->ResRedirect('/p'.$id, 'post')
      if $id && 6 == scalar grep { $_ ne 'comm' && $b4{$_} eq $frm->{$_} } keys %b4;

    if(!$frm->{_err}) {
      my $cid;
      $cid = $self->DBEditProducer($id, %$frm) if $id;    # edit
      ($id, $cid) = $self->DBAddProducer(%$frm) if !$id;   # add
      return $self->ResRedirect('/p'.$id.'?rev='.$cid, 'post');
    }
  }

  if($id) {
    $frm->{$_} ||= $b4{$_} for (keys %b4);
    $frm->{comm} = sprintf 'Reverted to revision %d by %s.', $p->{cid}, $p->{username} if $p->{cid} != $p->{latest};
  } else {
    $frm->{lang} ||= 'ja';
  }

  $self->ResAddTpl(pedit => {
    form => $frm,
    id => $id,
    prod => $p,
  });
}


sub PLock {
  my $self = shift;
  my $id = shift;

  my $p = $self->DBGetProducer(id => $id)->[0];
  return $self->ResNotFound() if !$p;
  return $self->ResDenied if !$self->AuthCan('lock');
  $self->DBLockItem('producers', $id, $p->{locked}?0:1);
  return $self->ResRedirect('/p'.$id, 'perm');
}


sub PHide {
  my $self = shift;
  my $id = shift;

  my $p = $self->DBGetProducer(id => $id)->[0];
  return $self->ResNotFound() if !$p;
  return $self->ResDenied if !$self->AuthCan('del');
  $self->DBHideProducer($id, $p->{hidden}?0:1);
  return $self->ResRedirect('/p'.$id, 'perm');
}

sub PXML {
  my $self = shift;

  my $q = $self->FormCheck(
    { name => 'q', required => 0, maxlength => 100 }
  )->{q};

  my $r = [];
  if($q) {
    $r = $self->DBGetProducer(results => 10,
      $q =~ /^p([0-9]+)$/ ? (id => $1) : (search => $q));
  }

  my $x = $self->ResStartXML;
  $x->startTag('producers', results => $#$r+1, query => $q);
  for (@$r) {
    $x->startTag('item');
    $x->dataElement(id => $_->{id});
    $x->dataElement(name => $_->{name});
    $x->dataElement(original => $_->{original}) if $_->{original};
    $x->dataElement(website => $_->{website}) if $_->{website};
    $x->endTag('item');
  }
  $x->endTag('producers');
}


