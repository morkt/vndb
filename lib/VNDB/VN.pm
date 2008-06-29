
package VNDB::VN;

use strict;
use warnings;
use Exporter 'import';
use Digest::MD5;
require bytes;

use vars ('$VERSION', '@EXPORT');
$VERSION = $VNDB::VERSION;
@EXPORT = qw| VNPage VNEdit VNLock VNHide VNBrowse VNXML VNUpdReverse |;


sub VNPage {
  my $self = shift;
  my $id = shift;
  my $page = shift || '';

  my $r = $self->FormCheck(
    { name => 'rev',  required => 0, default => 0, template => 'int' },
    { name => 'diff', required => 0, default => 0, template => 'int' },
  );
  
  my $v = $self->DBGetVN(
    id => $id,
    what => 'extended relations categories anime'.($r->{rev} ? ' changes' : ''),
    $r->{rev} ? ( rev => $r->{rev} ) : ()
  )->[0];
  return $self->ResNotFound if !$v->{id};

  $r->{diff} ||= $v->{prev} if $r->{rev};
  my $c = $r->{diff} && $self->DBGetVN(id => $id, rev => $r->{diff}, what => 'extended changes relations categories anime')->[0];
  $v->{next} = $self->DBGetHist(type => 'v', id => $id, next => $v->{cid}, showhid => 1)->[0]{id} if $r->{rev};

  if($page eq 'rg' && $v->{rgraph}) {
    open(my $F, '<:utf8', sprintf '%s/%02d/%d.cmap', $self->{mappath}, $v->{rgraph}%100, $v->{rgraph}) || die $!;
    $v->{rmap} = join('', (<$F>));
    close($F);
  }

  $self->ResAddTpl(vnpage => {
    vote => $self->AuthInfo->{id} ? $self->DBGetVotes(uid => $self->AuthInfo->{id}, vid => $id)->[0] : {},
    list => $self->AuthInfo->{id} ? $self->DBGetVNList(uid => $self->AuthInfo->{id}, vid => $id)->[0] : {},
    rel => scalar $self->DBGetRelease(vid => $id, what => 'producers platforms'),
    vn => $v,
    prev => $c,
    page => $page,
    change => $r->{diff}||$r->{rev},
    $page eq 'stats' ? (
      lists => {
        latest => scalar $self->DBGetVNList(vid => $id, results => 7, hide => 1),
        graph => $self->DBVNListStats(vid => $id),
      },
      votes => {
        latest => scalar $self->DBGetVotes(vid => $id, results => 10, hide => 1),
        graph => $self->DBVoteStats(vid => $id),
      },
    ) : (),
  });
}


sub VNEdit {
  my $self = shift;
  my $id = shift; # 0 = new

  my $rev = $self->FormCheck({ name => 'rev',  required => 0, default => 0, template => 'int' })->{rev};

  my $v = $self->DBGetVN(id => $id, what => 'extended changes relations categories anime', $rev ? ( rev => $rev ) : ())->[0] if $id;
  return $self->ResNotFound() if $id && !$v;

  return $self->ResDenied if !$self->AuthCan('edit') || ($v->{locked} && !$self->AuthCan('lock'));
  
  my %b4 = $id ? (
    ( map { $_ => $v->{$_} } qw| title desc alias img_nsfw length l_wp l_encubed l_renai l_vnn | ),
    relations => join('|||', map { $_->{relation}.','.$_->{id}.','.$_->{title} } @{$v->{relations}}),
    categories => join(',', map { $_->[0].$_->[1] } sort { $a->[0] cmp $b->[0] } @{$v->{categories}}),
    anime => join(' ', sort { $a <=> $b } map $_->{id}, @{$v->{anime}}),
  ) : ();

  my $frm = {};
  if($self->ReqMethod() eq 'POST') {
    $frm = $self->FormCheck(
      { name => 'title', required => 1, maxlength => 250 },
      { name => 'alias', required => 0, maxlength => 500, default => '' },
      { name => 'desc', required => 1, maxlength => 10240 },
      { name => 'length', required => 0, enum => [ 0..($#$VNDB::VNLEN+1) ], default => 0 },
      { name => 'l_wp',  required => 0, default => '', maxlength => 150 },
      { name => 'l_encubed', required => 0, default => '', maxlength => 100 },
      { name => 'l_renai', required => 0, default => '', maxlength => 100 },
      { name => 'l_vnn',  required => 0, default => 0, template => 'int' },
      { name => 'anime', required => 0, default => '' },
      { name => 'img_nsfw', required => 0 },
      { name => 'categories', required => 0, default => '' },
      { name => 'relations', required => 0, default => '' },
      { name => 'comm', required => 1, minlength => 10, maxlength => 1000 },
    );
    $frm->{img_nsfw} = $frm->{img_nsfw} ? 1 : 0;
    $frm->{anime} = join(' ', sort { $a <=> $b } grep /^[0-9]+$/, split(/\s+/, $frm->{anime})); # re-sort

    return $self->ResRedirect('/v'.$id, 'post')
      if $id && !$self->ReqParam('img') && 12 == scalar grep { $b4{$_} eq $frm->{$_} } keys %b4;

    my $relations = [ map { /^([0-9]+),([0-9]+)/ && $2 != $id ? ( [ $1, $2 ] ) : () } split /\|\|\|/, $frm->{relations} ];
    my $cat = [ map { [ substr($_,0,3), substr($_,3,1) ] } split /,/, $frm->{categories} ];
    my $anime = [ split / /, $frm->{anime} ];

   # upload image
    my $imgid = 0;
    if($self->ReqParam('img')) {
      my $tmp = sprintf '%s/00/tmp.%d.jpg', $self->{imgpath}, $$*int(rand(1000)+1);
      $self->ReqSaveUpload('img', $tmp);

      my $l;
      open(my $T, '<:raw:bytes', $tmp) || die $1;
      read $T, $l, 2;
      close($T);

      $frm->{_err} = $frm->{_err} ? [ @{$frm->{_err}}, 'nojpeg' ] : [ 'nojpeg' ]
        if $l ne pack('H*', 'ffd8') && $l ne pack('H*', '8950');
      $frm->{_err} = $frm->{_err} ? [ @{$frm->{_err}}, 'toolarge' ] : [ 'toolarge' ]
        if !$frm->{_err} && -s $tmp > 512*1024; # 500 KB max.
      
      if($frm->{_err}) {
        unlink $tmp;
      } else {
        $imgid = $self->DBIncId('covers_seq');
        my $new = sprintf '%s/%02d/%d.jpg', $self->{imgpath}, $imgid%100, $imgid;
        rename $tmp, $new or die $!;
        chmod 0666, $new;
        $self->RunCmd(sprintf 'coverimage %d', $imgid);
        $imgid = -1*$imgid;
      }
    } elsif($id) {
      $imgid = $v->{image};
    }

    my %args = (
      ( map { $_ => $frm->{$_} } qw| title desc alias comm length l_wp l_encubed l_renai l_vnn img_nsfw| ),
      image => $imgid,
      anime => $anime,
      relations => $relations,
      categories => $cat,
    );

    if(!$frm->{_err}) {
      my($oid, $cid) = ($id, 0);
      $cid = $self->DBEditVN($id, %args)  if $id;    # edit
      ($id, $cid) = $self->DBAddVN(%args) if !$id;   # add

     # update reverse relations and relation graph
      if((!$oid && $#$relations >= 0) || ($oid && $frm->{relations} ne $b4{relations})) {
        my %old = $oid ? (map { $_->{id} => $_->{relation} } @{$v->{relations}}) : ();
        my %new = map { $_->[1] => $_->[0] } @$relations; 
        $self->VNUpdReverse(\%old, \%new, $id, $cid);
      }
     # also regenerate relation graph if the title changes
      elsif(@$relations && $frm->{title} ne $b4{title}) {
        $self->RunCmd('relgraph '.$id);
      }

     # check for new anime data
      $self->RunCmd('anime check') if $oid && $frm->{anime} ne $b4{anime} || !$oid && $frm->{anime};

      return $self->ResRedirect('/v'.$id.'?rev='.$cid, 'post');
    }
  }

  if($id) {
    $frm->{$_} ||= $b4{$_} for (keys %b4);
    $frm->{comm} = sprintf 'Reverted to revision %d by %s.', $v->{cid}, $v->{username} if $v->{cid} != $v->{latest};
  } 

  $self->AddHid($frm);
  $frm->{_hid} = {map{$_=>1} qw| info cat img com |}
    if !$frm->{_hid} && !$id;
  $self->ResAddTpl(vnedit => {
    form => $frm,
    id => $id,
    vn => $v,
  });
}


sub VNLock {
  my $self = shift;
  my $id = shift;

  my $v = $self->DBGetVN(id => $id)->[0];
  return $self->ResNotFound() if !$v;
  return $self->ResDenied if !$self->AuthCan('lock');
  $self->DBLockItem('vn', $id, $v->{locked}?0:1);
  $self->DBLockItem('releases', $_->{id}, $v->{locked}?0:1)
    for (@{$self->DBGetRelease(vid => $id)});
  return $self->ResRedirect('/v'.$id, 'perm');
}


sub VNHide {
  my $self = shift;
  my $id = shift;

  my $v = $self->DBGetVN(id => $id, what => 'relations')->[0];
  return $self->ResNotFound() if !$v;
  return $self->ResDenied if !$self->AuthCan('del');
  $self->DBHideVN($id, $v->{hidden}?0:1);
  #$self->VNUpdReverse({ map { $_->{id} => $_->{relation} } @{$v->{relations}} }, {}, $id, 0)
  #  if @{$v->{relations}};
  return $self->ResRedirect('/v'.$id, 'perm');
}


sub VNBrowse {
  my $self = shift;
  my $chr = shift;
  $chr = 'all' if !defined $chr;

  my $f = $self->FormCheck(
    { name => 's', required => 0, default => 'title', enum => [ qw|title released votes| ] },
    { name => 'o', required => 0, default => 'a', enum => [ 'a','d' ] },
    { name => 'q', required => 0, default => '' },
    { name => 'sq', required => 0, default => '' },
    { name => 'p', required => 0, template => 'int', default => 1},
  );

  $f->{q} ||= $f->{sq};

  my(@cati, @cate, @plat, @lang);
  my $q = $f->{q};
  if($chr eq 'search') {
   # VNDBID
    return $self->ResRedirect('/'.$1, 'temp')
      if $q =~ /^([vrpud][0-9]+)$/;
    
    if(!($q =~ s/^title://)) {
     # categories
      my %catl = map {
        my $ic = $_;
        map { $ic.$_ => $VNDB::CAT->{$ic}[1]{$_} } keys %{$VNDB::CAT->{$ic}[1]}
      } keys %$VNDB::CAT;

      $q =~ s/-(?:$catl{$_}|c:$_)//ig && push @cate, $_ for keys %catl;
      $q =~ s/(?:$catl{$_}|c:$_)//ig && push @cati, $_ for keys %catl;

     # platforms
      $_ ne 'oth' && $q =~ s/(?:$VNDB::PLAT->{$_}|p:$_)//ig && push @plat, $_ for keys %$VNDB::PLAT;

     # languages
      $q =~ s/($VNDB::LANG->{$_}|l:$_)//ig && push @lang, $_ for keys %$VNDB::LANG;
    }
  }
  $q =~ s/ +$//;
  $q =~ s/^ +//;

  my($r, $np) = $chr ne 'search' || $q || @lang || @plat || @cati || @cate ? ($self->DBGetVN(
    $chr =~ /^[a-z0]$/ ? ( char => $chr ) : (),
    $q ? ( search => $q ) : (),
    @cati ? ( cati => \@cati ) : (),
    @cate ? ( cate => \@cate ) : (),
    @lang ? ( lang => \@lang ) : (),
    @plat ? ( platform => \@plat ) : (),
    results => 50,
    page => $f->{p},
    order => {title => 'vr.title', released => 'v.c_released', votes => 'v.c_votes'
      }->{$f->{s}}.{a=>' ASC',d=>' DESC'}->{$f->{o}},
  )) : ([], 0);

  $self->ResRedirect('/v'.$r->[0]{id}, 'temp')
    if $chr eq 'search' && $#$r == 0;
  
  $self->ResAddTpl(vnbrowse => {
    vn => $r,
    npage => $np,
    page => $f->{p},
    chr => $chr,
    $chr eq 'search' ? (
      cat => $self->DBCategoryCount,
      langc => $self->DBLanguageCount,
    ) : (),
    order => [ $f->{s}, $f->{o} ],
  },
  searchquery => $f->{q});
}


sub VNXML {
  my $self = shift;

  my $q = $self->FormCheck(
    { name => 'q', required => 0, maxlength => 100 }
  )->{q};

  my $r = [];
  if($q) {
    ($r,undef) = $self->DBGetVN(results => 10,
      $q =~ /^v([0-9]+)$/ ? (id => $1) : (search => $q));
  }

  my $x = $self->ResStartXML;
  $x->startTag('vn', results => $#$r+1, query => $q);
  for (@$r) {
    $x->startTag('item');
    $x->dataElement(id => $_->{id});
    $x->dataElement(title => $_->{title});
    $x->endTag('item');
  }
  $x->endTag('vn');
}


# Update reverse relations
sub VNUpdReverse { # old, new, id, cid
  my($self, $old, $new, $id, $cid) = @_;
  my %upd;
  for (keys %$old, keys %$new) {
    if(exists $$old{$_} and !exists $$new{$_}) {
      $upd{$_} = -1;
    } elsif((!exists $$old{$_} and exists $$new{$_}) || ($$old{$_} != $$new{$_})) {
      $upd{$_} = $$new{$_};
      if($VNDB::VRELW->{$upd{$_}}) { $upd{$_}-- }
      elsif($VNDB::VRELW->{$upd{$_}+1}) { $upd{$_}++ }
    }
  }

  for my $i (keys %upd) {
    my $r = $self->DBGetVN(id => $i, what => 'extended relations categories anime')->[0];
    my @newrel;
    $_->{id} != $id && push @newrel, [ $_->{relation}, $_->{id} ]
    for (@{$r->{relations}});
    push @newrel, [ $upd{$i}, $id ] if $upd{$i} != -1;
    $self->DBEditVN($i,
      relations => \@newrel,
      comm => 'Reverse relation update caused by revision '.$cid.' of v'.$id,
      causedby => $cid,
      uid => 1,         # Multi - hardcoded
      anime => [ map $_->{id}, @{$r->{anime}} ],
      ( map { $_ => $r->{$_} } qw| title desc alias categories img_nsfw length l_wp l_encubed l_renai l_vnn image | )
    );
  }

  $self->RunCmd('relgraph '.join(' ', $id, keys %upd));
}



1;

