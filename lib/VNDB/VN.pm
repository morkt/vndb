
package VNDB::VN;

use strict;
use warnings;
use Exporter 'import';
use Digest::MD5;
require bytes;

use vars ('$VERSION', '@EXPORT');
$VERSION = $VNDB::VERSION;
@EXPORT = qw| VNPage VNEdit VNLock VNHide VNBrowse VNXML VNScrXML VNUpdReverse |;


sub VNPage {
  my $self = shift;
  my $id = shift;
  my $page = shift || '';
  my $rev = shift || 0;

  return $self->ResNotFound if $self->ReqParam('rev');
  
  my $what = 'extended relations categories anime screenshots';
  $what .= ' changes' if $rev;
  $what .= ' relgraph' if $page eq 'rg';

  my $v = $self->DBGetVN(
    id => $id,
    what => $what,
    $rev ? ( rev => $rev ) : ()
  )->[0];
  return $self->ResNotFound if !$v->{id};

  my $c = $rev && $rev > 1 && $self->DBGetVN(id => $id, rev => $rev-1, what => $what)->[0];
  $v->{next} = $rev && $v->{latest} > $v->{cid} ? $rev+1 : 0;

  my $rel = $self->DBGetRelease(vid => $id, what => 'producers platforms');

  if(!$page && @$rel && $self->AuthInfo->{id}) {
    my $rl = $self->DBGetRList(
      rids => [ map $_->{id}, @$rel ],
      uid => $self->AuthInfo->{id}
    );
    for my $i (@$rl) {
      my $r = (grep $i->{rid} == $_->{id}, @$rel)[0];
      $r->{rlist} = $i;
    }
  } 

  $self->ResAddTpl(vnpage => {
    vote => $self->AuthInfo->{id} ? $self->DBGetVotes(uid => $self->AuthInfo->{id}, vid => $id)->[0] : {},
    wlist => $self->AuthInfo->{id} ? $self->DBGetWishList(uid => $self->AuthInfo->{id}, vid => $id)->[0] : {},
    vn => $v,
    rel => $rel,
    prev => $c,
    page => $page,
    change => $rev,
    $page eq 'stats' ? (
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

  my $rev = $self->FormCheck({ name => 'rev',  required => 0, default => 0, template => 'int' });
  return $self->ResNotFound if $rev->{_err};
  $rev = $rev->{rev};

  my $v = $self->DBGetVN(id => $id, what => 'extended changes relations categories anime screenshots', $rev ? ( rev => $rev ) : ())->[0] if $id;
  return $self->ResNotFound() if $id && !$v;

  return $self->ResDenied if !$self->AuthCan('edit') || ($v->{locked} && !$self->AuthCan('lock'));
  
  my %b4 = $id ? (
    ( map { $_ => $v->{$_} } qw| title desc alias img_nsfw length l_wp l_encubed l_renai l_vnn | ),
    relations => join('|||', map { $_->{relation}.','.$_->{id}.','.$_->{title} } @{$v->{relations}}),
    categories => join(',', map { $_->[0].$_->[1] } sort { $a->[0] cmp $b->[0] } @{$v->{categories}}),
    anime => join(' ', sort { $a <=> $b } map $_->{id}, @{$v->{anime}}),
    screenshots => join(' ', map sprintf('%d,%d,%d', $$_{id}, $$_{nsfw}?1:0, $$_{rid}||0), @{$v->{screenshots}}),
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
      { name => 'screenshots', required => 0, default => '' },
      { name => 'comm', required => 0, default => '' },
    );
    my $relations = [ map { /^([0-9]+),([0-9]+)/ && $2 != $id ? ( [ $1, $2 ] ) : () } split /\|\|\|/, $frm->{relations} ];
    my $cat = [ map { [ substr($_,0,3), substr($_,3,1) ] } split /,/, $frm->{categories} ];
    my $anime = [ grep /^[0-9]+$/, split / +/, $frm->{anime} ];
    my $screenshots = [ map { local $_=[split /,/];$$_[2]||=undef; $_ } grep /^[0-9]+,[01],[0-9]+$/, split / +/, $frm->{screenshots} ];

    $frm->{img_nsfw} = $frm->{img_nsfw} ? 1 : 0;
    $frm->{anime} = join ' ', sort { $a <=> $b } @$anime; # re-sort
    $frm->{screenshots} = join ' ', map sprintf('%d,%d,%d', $$_[0], $$_[1]?1:0, $$_[2]||0), sort { $$a[0] <=> $$b[0] } @$screenshots;

    return $self->ResRedirect('/v'.$id, 'post')
      if $id && !$self->ReqParam('img') && 13 == scalar grep { $b4{$_} eq $frm->{$_} } keys %b4;

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
      screenshots => $screenshots,
    );

    if(!$frm->{_err}) {
      my($oid, $nrev, $cid) = ($id, 1, 0);
      ($nrev, $cid) = $self->DBEditVN($id, %args)  if $id;  # edit
      ($id, $cid) = $self->DBAddVN(%args) if !$id;          # add

     # update reverse relations and relation graph
      if((!$oid && $#$relations >= 0) || ($oid && $frm->{relations} ne $b4{relations})) {
        my %old = $oid ? (map { $_->{id} => $_->{relation} } @{$v->{relations}}) : ();
        my %new = map { $_->[1] => $_->[0] } @$relations; 
        $self->VNUpdReverse(\%old, \%new, $id, $cid, $nrev);
      }
     # also regenerate relation graph if the title changes
      elsif(@$relations && $frm->{title} ne $b4{title}) {
        $self->RunCmd('relgraph '.$id);
      }

     # check for new anime data
      $self->RunCmd('anime') if $oid && $frm->{anime} ne $b4{anime} || !$oid && $frm->{anime};

      $self->RunCmd('ircnotify v'.$id.'.'.$nrev);
      return $self->ResRedirect('/v'.$id.'.'.$nrev, 'post');
    }
  }

  if($id) {
    $frm->{$_} ||= $b4{$_} for (keys %b4);
    $frm->{comm} = sprintf 'Reverted to revision v%d.%d', $v->{id}, $v->{rev} if $v->{cid} != $v->{latest};
  } 

  $self->AddHid($frm);
  $frm->{_hid} = {map{$_=>1} qw| info cat img com |}
    if !$frm->{_hid} && !$id;
  $self->ResAddTpl(vnedit => {
    form => $frm,
    id => $id,
    vn => $v,
    rel => scalar $self->DBGetRelease(vid => $id),
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
  return $self->ResNotFound if $f->{_err};
  $f->{s} = 'title' if $f->{s} eq 'votes';

  $f->{q} ||= $f->{sq};

  my(@cati, @cate, @plat, @lang);
  my $q = $f->{q};
  if($chr eq 'search') {
   # VNDBID
    return $self->ResRedirect('/'.$1.$2.(!$3 ? '' : $1 eq 'd' ? '#'.$3 : '.'.$3), 'temp')
      if $q =~ /^([vrptud])([0-9]+)(?:\.([0-9]+))?$/;
    
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
    order => {title => 'vr.title', released => 'v.c_released', 
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


sub VNScrXML {
  my $self = shift;
  return $self->ResDenied if !$self->AuthCan('edit');

 # check the status of recently uploaded screenshots
  if($self->ReqMethod ne 'POST') {
    my $ids = $self->FormCheck(
      { name => 'id', required => 1, template => 'int', multi => 1 }
    );
    return $self->ResNotFound if $ids->{_err};
    my $r = $self->DBGetScreenshot($ids->{id});
    return $self->ResNotFound if !@$r;
    my $x = $self->ResStartXML;
    $x->startTag('images');
    $x->emptyTag('image', id => $_->{id}, status => $_->{status}, width => $_->{width}, height => $_->{height})
      for (@$r);
    $x->endTag('images');
    return;
  }

 # upload new screenshot
  my $i = $self->FormCheck(
    { name => 'itemnumber', required => 1, template => 'int' }
  );
  return $self->ResNotFound if $i->{_err};
  $i = $i->{itemnumber};

  my $tmp = sprintf '%s/00/tmp.%d.jpg', $self->{sfpath}, $$*int(rand(1000)+1);
  $self->ReqSaveUpload('scrAddFile'.$i, $tmp);

  my $id = 0;
  $id = -2 if !-s $tmp;
  if(!$id) {
    my $l;
    open(my $T, '<:raw:bytes', $tmp) || die $1;
    read $T, $l, 2;
    close($T);
    $id = -1 if $l ne pack('H*', 'ffd8') && $l ne pack('H*', '8950');
  }
  
  if($id) {
    unlink $tmp;
  } else {
    $id = $self->DBAddScreenshot;
    my $new = sprintf '%s/%02d/%d.jpg', $self->{sfpath}, $id%100, $id;
    rename $tmp, $new or die $!;
    chmod 0666, $new;
    $self->RunCmd('screenshot');
  }

  my $x = $self->ResStartXML;
  $x->pi('xml-stylesheet', 'href="'.$self->{static_url}.'/files/blank.css" type="text/css"');
  $x->emptyTag('image', id => $id);
}


# Update reverse relations
sub VNUpdReverse { # old, new, id, cid, rev
  my($self, $old, $new, $id, $cid, $rev) = @_;
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
    my $r = $self->DBGetVN(id => $i, what => 'extended relations categories anime screenshots')->[0];
    my @newrel;
    $_->{id} != $id && push @newrel, [ $_->{relation}, $_->{id} ]
    for (@{$r->{relations}});
    push @newrel, [ $upd{$i}, $id ] if $upd{$i} != -1;
    $self->DBEditVN($i,
      relations => \@newrel,
      comm => 'Reverse relation update caused by revision v'.$id.'.'.$rev,
      causedby => $cid,
      uid => 1,         # Multi - hardcoded
      anime => [ map $_->{id}, @{$r->{anime}} ],
      screenshots => [ map [ $_->{id}, $_->{nsfw}, $_->{rid} ], @{$r->{screenshots}} ],
      ( map { $_ => $r->{$_} } qw| title desc alias categories img_nsfw length l_wp l_encubed l_renai l_vnn image | )
    );
  }

  $self->RunCmd('relgraph '.join(' ', $id, keys %upd));
}



1;

