
package VNDB::Handler::ULists;

use strict;
use warnings;
use YAWF ':html', ':xml';
use VNDB::Func;


YAWF::register(
  qr{v([1-9]\d*)/vote},  \&vnvote,
  qr{v([1-9]\d*)/wish},  \&vnwish,
  qr{r([1-9]\d*)/list},  \&rlist,
  qr{xml/rlist.xml},     \&rlist,
  qr{u([1-9]\d*)/wish},  \&wishlist,
  qr{u([1-9]\d*)/list},  \&vnlist,
);


sub vnvote {
  my($self, $id) = @_;

  my $uid = $self->authInfo->{id};
  return $self->htmlDenied() if !$uid;

  my $f = $self->formValidate(
    { name => 'v', enum => [ -1, 1..10 ] }
  );
  return 404 if $f->{_err};

  $self->dbVoteDel($uid, $id) if $f->{v} == -1;
  $self->dbVoteAdd($id, $uid, $f->{v}) if $f->{v} > 0;

  $self->resRedirect('/v'.$id, 'temp');
}


sub vnwish {
  my($self, $id) = @_;

  my $uid = $self->authInfo->{id};
  return $self->htmlDenied() if !$uid;

  my $f = $self->formValidate(
    { name => 's', enum => [ -1..$#{$self->{wishlist_status}} ] }
  );
  return 404 if $f->{_err};

  $self->dbWishListDel($uid, $id) if $f->{s} == -1;
  $self->dbWishListAdd($id, $uid, $f->{s}) if $f->{s} != -1;

  $self->resRedirect('/v'.$id, 'temp');
}


sub rlist {
  my($self, $id) = @_;

  my $rid = $id;
  if(!$rid) {
    my $f = $self->formValidate(
      { name => 'id', required => 1, template => 'int' }
    );
    return 404 if $f->{_err};
    $rid = $f->{id};
  }

  my $uid = $self->authInfo->{id};
  return $self->htmlDenied() if !$uid;

  my $f = $self->formValidate(
    { name => 'e', required => 1, enum => [ 'del', map("r$_", 0..$#{$self->{vn_rstat}}), map("v$_", 0..$#{$self->{vn_vstat}}) ] },
  );
  return 404 if $f->{_err};

  $self->dbVNListDel($uid, $rid) if $f->{e} eq 'del';
  $self->dbVNListAdd(
    rid => $rid,
    uid => $uid,
    $f->{e} =~ /^([rv])(\d+)$/ && $1 eq 'r' ? (rstat => $2) : (vstat => $2)
  ) if $f->{e} ne 'del';

  if($id) {
    (my $ref = $self->reqHeader('Referer')||"/r$id") =~ s/^\Q$self->{url}//;
    $self->resRedirect($ref, 'temp');
  } else {
    $self->resHeader('Content-type' => 'text/xml');
    my $st = $self->dbVNListGet(uid => $self->authInfo->{id}, rid => [$rid])->[0];
    xml;
    tag 'rlist', uid => $self->authInfo->{id}, rid => $rid;
     txt $st ? liststat $st : '--';
    end;
  }
}


sub wishlist {
  my($self, $uid) = @_;

  my $own = $self->authInfo->{id} && $self->authInfo->{id} == $uid;
  my $u = $self->dbUserGet(uid => $uid)->[0];
  return 404 if !$u || !$own && !($u->{show_list} || $self->authCan('usermod'));

  my $f = $self->formValidate(
    { name => 'p', required => 0, default => 1, template => 'int' },
    { name => 'o', required => 0, default => 'd', enum => [ 'a', 'd' ] },
    { name => 's', required => 0, default => 'wstat', enum => [qw|title added wstat|] },
    { name => 'f', required => 0, default => -1, enum => [ -1..$#{$self->{wishlist_status}} ] },
  );
  return 404 if $f->{_err};

  if($own && $self->reqMethod eq 'POST') {
    my $frm = $self->formValidate(
      { name => 'sel', required => 0, default => 0, multi => 1, template => 'int' },
      { name => 'batchedit', required => 1, enum => [ -1..$#{$self->{wishlist_status}} ] },
    );
    if(!$frm->{_err} && @{$frm->{sel}} && $frm->{sel}[0]) {
      $self->dbWishListDel($uid, $frm->{sel}) if $frm->{batchedit} == -1;
      $self->dbWishListAdd($frm->{sel}, $uid, $frm->{batchedit}) if $frm->{batchedit} >= 0;
    }
  }

  my($list, $np) = $self->dbWishListGet(
    uid => $uid,
    order => $f->{s}.' '.($f->{o} eq 'a' ? ($f->{s} eq 'wstat' ? 'DESC' : 'ASC' ) : ($f->{s} eq 'wstat' ? 'ASC' : 'DESC')).($f->{s} eq 'wstat' ? ', title ASC' : ''),
    $f->{f} != -1 ? (wstat => $f->{f}) : (),
    what => 'vn',
    results => 50,
    page => $f->{p},
  );

  my $title = $own ? 'My wishlist' : "\u$u->{username}'s wishlist";
  $self->htmlHeader(title => $title, noindex => 1);
  $self->htmlMainTabs('u', $u, 'wish');
  div class => 'mainbox';
   h1 $title;
   if(!@$list && $f->{f} == -1) {
      p 'Wishlist empty...';
     end;
     return $self->htmlFooter;
   }
   p class => 'browseopts';
    a $f->{f} == $_ ? (class => 'optselected') : (), href => "/u$uid/wish?f=$_",
        $_ == -1 ? 'All priorities' : ucfirst $self->{wishlist_status}[$_]
      for (-1..$#{$self->{wishlist_status}});
   end;
  end;

  form action => "/u$uid/wish?f=$f->{f};o=$f->{o};s=$f->{s};p=$f->{p}", method => 'post'
    if $own;

  $self->htmlBrowse(
    class    => 'wishlist',
    items    => $list,
    nextpage => $np,
    options  => $f,
    pageurl  => "/u$uid/wish?f=$f->{f};o=$f->{o};s=$f->{s}",
    sorturl  => "/u$uid/wish?f=$f->{f}",
    header   => [
      [ Title    => 'title' ],
      [ Priority => 'wstat' ],
      [ Added    => 'added' ],
    ],
    row      => sub {
      my($s, $n, $i) = @_;
      Tr $n % 2 == 0 ? (class => 'odd') : ();
       td class => 'tc1';
        input type => 'checkbox', name => 'sel', value => $i->{vid}
          if $own;
        a href => "/v$i->{vid}", title => $i->{original}||$i->{title}, ' '.shorten $i->{title}, 70;
       end;
       td class => 'tc2', ucfirst $self->{wishlist_status}[$i->{wstat}];
       td class => 'tc3', date $i->{added}, 'compact';
      end;
    },
    $own ? (footer => sub {
      Tr;
       td colspan => 3;
        Select name => 'batchedit', id => 'batchedit';
         option '-- with selected --';
         optgroup label => 'Change priority';
          option value => $_, $self->{wishlist_status}[$_]
            for (0..$#{$self->{wishlist_status}});
         end;
         option value => -1, 'remove from wishlist';
        end;
       end;
      end;
    }) : (),
  );
  end if $own;
  $self->htmlFooter;
}


sub vnlist {
  my($self, $uid) = @_;

  my $own = $self->authInfo->{id} && $self->authInfo->{id} == $uid;
  my $u = $self->dbUserGet(uid => $uid)->[0];
  return 404 if !$u || !$own && !($u->{show_list} || $self->authCan('usermod'));

  my $f = $self->formValidate(
    { name => 'p',  required => 0, default => 1, template => 'int' },
    { name => 'o',  required => 0, default => 'a', enum => [ 'a', 'd' ] },
    { name => 's',  required => 0, default => 'title', enum => [ 'title', 'vote' ] },
    { name => 'c',  required => 0, default => 'all', enum => [ 'all', 'a'..'z', 0 ] },
    { name => 'v',  required => 0, default => 0, enum => [ -1..1  ] },
  );
  return 404 if $f->{_err};

  if($own && $self->reqMethod eq 'POST') {
    my $frm = $self->formValidate(
      { name => 'sel', required => 0, default => 0, multi => 1, template => 'int' },
      { name => 'batchedit', required => 1, enum => [ 'del', map("r$_", 0..$#{$self->{vn_rstat}}), map("v$_", 0..$#{$self->{vn_vstat}}) ] },
    );
    if(!$frm->{_err} && @{$frm->{sel}} && $frm->{sel}[0]) {
      $self->dbVNListDel($uid, $frm->{sel}) if $frm->{batchedit} eq 'del';
      $self->dbVNListAdd(
        rid => $frm->{sel},
        uid => $uid,
        $frm->{batchedit} =~ /^([rv])(\d+)$/ && $1 eq 'r' ? (rstat => $2) : (vstat => $2)
      ) if $frm->{batchedit} ne 'del';
    }
  }


  my($list, $np) = $self->dbVNListList(
    uid => $uid,
    results => 50,
    page => $f->{p},
    order => $f->{s}.' '.($f->{o} eq 'd' ? 'DESC' : 'ASC'),
    voted => $f->{v},
    $f->{c} ne 'all' ? (char => $f->{c}) : (),
  );

  my $title = $own ? 'My visual novel list' : "\u$u->{username}'s visual novel list";
  $self->htmlHeader(title => $title, noindex => 1);
  $self->htmlMainTabs('u', $u, 'list');

  # url generator
  my $url = sub {
    my($n, $v) = @_;
    $n ||= '';
    local $_ = "/u$uid/list";
    $_ .= '?c='.($n eq 'c' ? $v : $f->{c});
    $_ .= ';v='.($n eq 'v' ? $v : $f->{v});
    if($n eq 'page') {
      $_ .= ';o='.($n eq 'o' ? $v : $f->{o});
      $_ .= ';s='.($n eq 's' ? $v : $f->{s});
    }
    return $_;
  };

  div class => 'mainbox';
   h1 $title;
   p class => 'browseopts';
    for ('all', 'a'..'z', 0) {
      a href => $url->(c => $_), $_ eq $f->{c} ? (class => 'optselected') : (), $_ ? uc $_ : '#';
    }
   end;
   p class => 'browseopts';
    a href => $url->(v =>  0),  0 == $f->{v} ? (class => 'optselected') : (), 'All';
    a href => $url->(v =>  1),  1 == $f->{v} ? (class => 'optselected') : (), 'Only voted';
    a href => $url->(v => -1), -1 == $f->{v} ? (class => 'optselected') : (), 'Hide voted';
   end;
  end;

  _vnlist_browse($self, $own, $list, $np, $f, $url);
  $self->htmlFooter;
}

sub _vnlist_browse {
  my($self, $own, $list, $np, $f, $url) = @_;

  form action => $url->(), method => 'post'
    if $own;

  $self->htmlBrowse(
    class    => 'rlist',
    items    => $list,
    nextpage => $np,
    options  => $f,
    sorturl  => $url->(),
    pageurl  => $url->('page'),
    header   => [
      [ Title    => 'title', 3 ],
      sub { td class => 'tc2', id => 'relhidall'; lit '<i>&#9656;</i>Releases*'; end; },
      [ Vote     => 'vote'  ],
    ],
    row      => sub {

      my($s, $n, $i) = @_;
      Tr $n % 2 == 0 ? (class => 'odd') : ();
       td class => 'tc1', colspan => 3;
        a href => "/v$i->{vid}", title => $i->{original}||$i->{title}, shorten $i->{title}, 70;
       end;
       td class => 'tc2'.(@{$i->{rels}} ? ' relhid_but' : ''), id => 'vid'.$i->{vid};
        lit '<i>&#9656;</i>';
        my $obtained = grep $_->{rstat}==2, @{$i->{rels}};
        my $finished = grep $_->{vstat}==2, @{$i->{rels}};
        my $txt = sprintf '%d/%d/%d', $obtained, $finished, scalar @{$i->{rels}};
        $txt = qq|<b class="done">$txt</b>| if $finished > $obtained || $finished && $finished == $obtained;
        $txt = qq|<b class="todo">$txt</b>| if $obtained > $finished;
        lit $txt;
       end;
       td class => 'tc3', $i->{vote} || '-';
      end;

      for (@{$i->{rels}}) {
        Tr class => "relhid vid$i->{vid}";
         td class => 'tc1'.($own ? ' own' : '');
          input type => 'checkbox', name => 'sel', value => $_->{rid}
            if $own;
          lit datestr $_->{released};
         end;
         td class => 'tc2';
          cssicon "lang $_", $self->{languages}{$_} for @{$_->{languages}};
          cssicon substr(lc $self->{release_types}[$_->{type}], 0, 3), $self->{release_types}[$_->{type}].' release';
         end;
         td class => 'tc3';
          a href => "/r$_->{rid}", title => $_->{original}||$_->{title}, shorten $_->{title}, 50;
         end;
         td colspan => 2, class => 'tc4';
          lit liststat($_);
         end;
        end;
      }
    },

    $own ? (footer => sub {
      Tr;
       td class => 'tc1', colspan => 3;
        Select id => 'batchedit', name => 'batchedit';
         option '- with selected -';
         optgroup label => 'Change release status';
          option value => "r$_", $self->{vn_rstat}[$_]
            for (0..$#{$self->{vn_rstat}});
         end;
         optgroup label => 'Change play status';
          option value => "v$_", $self->{vn_vstat}[$_]
            for (0..$#{$self->{vn_vstat}});
         end;
         option value => 'del', 'remove from list';
        end;
       end;
       td class => 'tc2', colspan => 2, '* Obtained/finished/total';
      end;
    }) : (),
  );

  end if $own;
}

1;

