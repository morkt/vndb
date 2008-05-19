
package VNDB::Releases;

use strict;
use warnings;
use Exporter 'import';
use Digest::MD5;

use vars ('$VERSION', '@EXPORT');
$VERSION = $VNDB::VERSION;
@EXPORT = qw| RPage REdit RLock RDel RHide RVNCache |;


sub RPage {
  my $self = shift;
  my $id = shift;

  my $r = $self->FormCheck(
    { name => 'rev',  required => 0, default => 0, template => 'int' },
    { name => 'diff', required => 0, default => 0, template => 'int' },
  );
  
  my $v = $self->DBGetRelease(
    id => $id,
    what => 'producers platforms media vn'.($r->{rev} ? ' changes':''),
    $r->{rev} ? ( rev => $r->{rev} ) : ()
  )->[0];
  return $self->ResNotFound if !$v->{id};

  $r->{diff} ||= $v->{prev} if $r->{rev};
  my $c = $r->{diff} && $self->DBGetRelease(id => $id, rev => $r->{diff}, what => 'changes producers platforms media vn')->[0];
  $v->{next} = $self->DBGetHist(type => 'r', id => $id, next => $v->{cid}, showhid => 1)->[0]{id} if $r->{rev};

  $self->ResRedirect('/v'.$v->{vn}[0]{vid})
    if ($self->ReqHeader('Referer')||'') =~ m{^http://[^/]*(yahoo|google)} && @{$v->{vn}} == 1;

  return $self->ResAddTpl(rpage => {
    rel => $v,
    prev => $c,
    change => $r->{diff}||$r->{rev},
  });
}


sub REdit {
  my $self = shift;
  my $act = shift||'v';
  my $id = shift || 0;

  my $rid = $act eq 'r' ? $id : 0;

  my $rev = $self->FormCheck({ name => 'rev',  required => 0, default => 0, template => 'int' })->{rev};

  my $r = $self->DBGetRelease(id => $rid, what => 'changes producers platforms media vn', $rev ? ( rev => $rev ) : ())->[0] if $rid;
  my $ivn = $self->DBGetVN(id => $id)->[0] if !$rid;
  return $self->ResNotFound() if ($rid && !$r) || (!$rid && !$ivn);

  my $vn = $rid ? $r->{vn} : [ { vid => $id, title => $ivn->{title} } ];

  return $self->ResDenied if !$self->AuthCan('edit') || ($r->{locked} && !$self->AuthCan('lock'));

  my %b4 = $rid ? (
    (map { $_ => $r->{$_} } qw|title original language website notes minage type platforms|),
    released => $r->{released} =~ /^([0-9]{4})([0-9]{2})([0-9]{2})$/ ? [ $1, $2, $3 ] : [ 0, 0, 0 ],
    media => join(',', map { $_->{medium} =~ /^(cd|dvd|gdr|blr)$/ ? ($_->{medium}.'_'.$_->{qty}) : $_->{medium} } @{$r->{media}}),
    producers => join('|||', map { $_->{id}.','.$_->{name} } @{$r->{producers}}),
  ) : ();
  $b4{vn} = join('|||', map { $_->{vid}.','.$_->{title} } @$vn);

  my $frm = {};
  if($self->ReqMethod() eq 'POST') {
    $frm = $self->FormCheck(
      { name => 'type',      required => 1, enum => [ 0..$#{$VNDB::RTYP} ] },
      { name => 'title',     required => 1, maxlength => 250 },
      { name => 'original',  required => 0, maxlength => 250, default => '' },
      { name => 'language',  required => 1, enum => [ keys %{$VNDB::LANG} ] },
      { name => 'website',   required => 0, template => 'url', default => '' },
      { name => 'released',  required => 0, multi => 1, template => 'int', default => 0 },
      { name => 'minage' ,   required => 0, enum => [ keys %{$VNDB::VRAGES} ], default => -1 },
      { name => 'notes',     required => 0, maxlength => 10240, default => '' },
      { name => 'platforms', required => 0, multi => 1, enum => [ keys %$VNDB::PLAT ], default => '' },
      { name => 'media',     required => 0, default => '' },
      { name => 'producers', required => 0, default => '' },
      { name => 'vn',        required => 1, maxlength => 10240 },
      { name => 'comm',      required => 0, default => '' },
    );

    my $released = !$frm->{released}[0] ? 0 :
            $frm->{released}[0] == 9999 ? 99999999 :
                                          sprintf '%04d%02d%02d',  $frm->{released}[0], $frm->{released}[1]||99, $frm->{released}[2]||99;
    my $media = [ map { /_/ ? [ split /_/ ] : [ $_, 0 ] } split /,/, $frm->{media} ];
    my $producers = [ map { /^([0-9]+)/ ? $1 : () } split /\|\|\|/, $frm->{producers} ];
    my $new_vn = [ map { /^([0-9]+)/ ? $1 : () } split /\|\|\|/, $frm->{vn} ];

    $frm->{_err} = $frm->{_err} ? [ @{$frm->{_err}}, 'vn_1' ] : [ 'vn_1' ]
      if !@$new_vn;

    # weed out empty string
    $frm->{platforms} = [ map { $_ ? $_ : () } @{$frm->{platforms}} ]; 

    return $self->ResRedirect('/r'.$rid, 'post')
      if $rid && $released == $r->{released} &&
        (join(',', sort @{$b4{platforms}}) eq join(',', sort @{$frm->{platforms}})) &&
        10 == scalar grep { $_ ne 'comm' && $_ ne 'released' && $_ ne 'platforms' && $frm->{$_} eq $b4{$_} } keys %b4;

    if(!$frm->{_err}) {
      my %opts = (
        vn        => $new_vn,
        (map { $_ => $frm->{$_} } qw|title original language website notes minage type comm platforms|),
        released  => $released,
        media     => $media,
        producers => $producers,
      );
      my $cid; 
      $cid = $self->DBEditRelease($rid, %opts) if $rid;   # edit
      ($rid, $cid) = $self->DBAddRelease(%opts) if !$rid;  # add

      $self->RVNCache(@$new_vn, (map { $_->{vid} } @$vn));

      return $self->ResRedirect('/r'.$rid.'?rev='.$cid, 'post');
    }
  }

  if($rid) {
    $frm->{$_} ||= $b4{$_} for (keys %b4);
    $frm->{comm} = sprintf 'Reverted to revision %d by %s.', $r->{cid}, $r->{username} if $r->{cid} != $r->{latest};        
  } else {
    $frm->{language} = 'ja';
    $frm->{vn} = $b4{vn};
  }

  $self->AddHid($frm);
  $frm->{_hid} = {map{$_=>1} qw| info pnm prod |}
    if !$frm->{_hid} && !$rid;
  $self->ResAddTpl(redit => {
    form => $frm,
    id => $rid,
    rel => $r,
    vn => !$rid ? $ivn : $vn,
  });
}


sub RLock {
  my $self = shift;
  my $id = shift;

  my $r = $self->DBGetRelease(id => $id)->[0];
  return $self->ResNotFound() if !$r;
  return $self->ResDenied if !$self->AuthCan('lock');
  $self->DBLockItem('releases', $id, $r->{locked}?0:1);
  return $self->ResRedirect('/r'.$id, 'perm');
}


sub RDel {
  my $self = shift;
  my $id = shift;

  return $self->ResDenied if !$self->AuthCan('del');
  my $r = $self->DBGetRelease(id => $id, what => 'vn')->[0];
  return $self->ResNotFound if !$r;
  $self->DBDelRelease($id);
  $self->RVNCache(map { $_->{vid} } @{$r->{vn}});
  return $self->ResRedirect('/v'.$r->{vn}[0]{id}, 'perm');
}


sub RHide {
  my $self = shift;
  my $id = shift;

  return $self->ResDenied if !$self->AuthCan('del');
  my $r = $self->DBGetRelease(id => $id, what => 'vn')->[0];
  return $self->ResNotFound if !$r;
  $self->DBHideRelease($id, $r->{hidden}?0:1);
  $self->RVNCache(map { $_->{vid} } @{$r->{vn}});
  return $self->ResRedirect('/r'.$id, 'perm');
}


sub RVNCache { # @vids - calls update_vncache and regenerates relation graphs if needed
  my($self, @vns) = @_;
  my $before = $self->DBGetVN(id => \@vns, order => 'v.id');
  $self->DBVNCache(@vns);
  my $after = $self->DBGetVN(id => \@vns, order => 'v.id');
  my @upd = map {
    $before->[$_]{rgraph} && (
         $before->[$_]{c_released} != $after->[$_]{c_released}
      || $before->[$_]{c_languages} ne $after->[$_]{c_languages}
    ) ? $before->[$_]{id} : ();
  } 0..$#$before;
  $self->RunCmd('relgraph '.join(' ', @upd)) if @upd;
}

1;

