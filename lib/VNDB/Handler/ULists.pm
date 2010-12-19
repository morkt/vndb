
package VNDB::Handler::ULists;

use strict;
use warnings;
use YAWF ':html', ':xml';
use VNDB::Func;


YAWF::register(
  qr{v([1-9]\d*)/vote},  \&vnvote,
  qr{v([1-9]\d*)/wish},  \&vnwish,
  qr{v([1-9]\d*)/list},  \&vnlist_e,
  qr{r([1-9]\d*)/list},  \&rlist_e,
  qr{xml/rlist.xml},     \&rlist_e,
  qr{([uv])([1-9]\d*)/votes}, \&votelist,
  qr{u([1-9]\d*)/wish},  \&wishlist,
  qr{u([1-9]\d*)/list},  \&vnlist,
);


sub vnvote {
  my($self, $id) = @_;

  my $uid = $self->authInfo->{id};
  return $self->htmlDenied() if !$uid;

  return if !$self->authCheckCode;
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

  return if !$self->authCheckCode;
  my $f = $self->formValidate(
    { name => 's', enum => [ -1, @{$self->{wishlist_status}} ] }
  );
  return 404 if $f->{_err};

  $self->dbWishListDel($uid, $id) if $f->{s} == -1;
  $self->dbWishListAdd($id, $uid, $f->{s}) if $f->{s} != -1;

  $self->resRedirect('/v'.$id, 'temp');
}


sub vnlist_e {
  my($self, $id) = @_;

  my $uid = $self->authInfo->{id};
  return $self->htmlDenied() if !$uid;

  return if !$self->authCheckCode;
  my $f = $self->formValidate(
    { name => 'e', enum => [ -1, @{$self->{vnlist_status}} ] }
  );
  return 404 if $f->{_err};

  $self->dbVNListDel($uid, $id) if $f->{e} == -1;
  $self->dbVNListAdd($uid, $id, $f->{e}) if $f->{e} != -1;

  $self->resRedirect('/v'.$id, 'temp');
}


sub rlist_e {
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

  return if !$self->authCheckCode;
  my $f = $self->formValidate(
    { name => 'e', required => 1, enum => [ -1, @{$self->{rlist_status}} ] }
  );
  return 404 if $f->{_err};

  $self->dbRListDel($uid, $rid) if $f->{e} == -1;
  $self->dbRListAdd($uid, $rid, $f->{e}) if $f->{e} >= 0;

  if($id) {
    (my $ref = $self->reqHeader('Referer')||"/r$id") =~ s/^\Q$self->{url}//;
    $self->resRedirect($ref, 'temp');
  } else {
    # doesn't really matter what we return, as long as it's XML
    $self->resHeader('Content-type' => 'text/xml');
    xml;
    tag 'done', '';
  }
}


sub votelist {
  my($self, $type, $id) = @_;

  my $obj = $type eq 'v' ? $self->dbVNGet(id => $id)->[0] : $self->dbUserGet(uid => $id)->[0];
  return 404 if !$obj->{id};

  my $f = $self->formValidate(
    { name => 'p',  required => 0, default => 1, template => 'int' },
    { name => 'o',  required => 0, default => 'd', enum => ['a', 'd'] },
    { name => 's',  required => 0, default => 'date', enum => [qw|date title vote|] },
    { name => 'c',  required => 0, default => 'all', enum => [ 'all', 'a'..'z', 0 ] },
  );

  my($list, $np) = $self->dbVoteGet(
    $type.'id' => $id,
    what     => $type eq 'v' ? 'user' : 'vn',
    hide     => $type eq 'v',
    hide_ign => $type eq 'v',
    sort     => $f->{s} eq 'title' && $type eq 'v' ? 'username' : $f->{s},
    reverse  => $f->{o} eq 'd',
    results  => 50,
    page     => $f->{p},
    $f->{c} ne 'all' ? ($type eq 'u' ? 'vn_char' : 'user_char', $f->{c}) : (),
  );

  my $title = mt $type eq 'v' ? '_votelist_title_vn' : '_votelist_title_user', $obj->{title} || $obj->{username};
  $self->htmlHeader(noindex => 1, title => $title);
  $self->htmlMainTabs($type => $obj, 'votes');
  div class => 'mainbox';
   h1 $title;
   p class => 'browseopts';
    for ('all', 'a'..'z', 0) {
      a href => "/$type$id/votes?c=$_", $_ eq $f->{c} ? (class => 'optselected') : (), $_ eq 'all' ? mt('_char_all') : $_ ? uc $_ : '#';
    }
   end;
   p mt '_votelist_novotes' if !@$list;
  end;

  @$list && $self->htmlBrowse(
    class    => 'votelist',
    items    => $list,
    options  => $f,
    nextpage => $np,
    pageurl  => "/$type$id/votes?c=$f->{c};o=$f->{o};s=$f->{s}",
    sorturl  => "/$type$id/votes?c=$f->{c}",
    header   => [
      [ mt('_votelist_col_date'),  'date'  ],
      [ mt('_votelist_col_vote'),  'vote'  ],
      [ mt('_votelist_col_'.($type eq 'v'?'user':'vn')), 'title' ],
    ],
    row      => sub {
      my($s, $n, $l) = @_;
      Tr $n % 2 ? (class => 'odd') : ();
       td class => 'tc1', $self->{l10n}->date($l->{date});
       td class => 'tc2', $l->{vote};
       td class => 'tc3';
        a href => $type eq 'v' ? ("/u$l->{uid}", $l->{username}) : ("/v$l->{vid}", shorten $l->{title}, 100);
       end;
      end;
    },
  );

  $self->htmlFooter;
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
    { name => 'f', required => 0, default => -1, enum => [ -1, @{$self->{wishlist_status}} ] },
  );
  return 404 if $f->{_err};

  if($own && $self->reqMethod eq 'POST') {
    return if !$self->authCheckCode;
    my $frm = $self->formValidate(
      { name => 'sel', required => 0, default => 0, multi => 1, template => 'int' },
      { name => 'batchedit', required => 1, enum => [ -1, @{$self->{wishlist_status}} ] },
    );
    if(!$frm->{_err} && @{$frm->{sel}} && $frm->{sel}[0]) {
      $self->dbWishListDel($uid, $frm->{sel}) if $frm->{batchedit} == -1;
      $self->dbWishListAdd($frm->{sel}, $uid, $frm->{batchedit}) if $frm->{batchedit} >= 0;
    }
  }

  my($list, $np) = $self->dbWishListGet(
    uid => $uid,
    sort => $f->{s}, reverse => $f->{o} eq 'd',
    $f->{f} != -1 ? (wstat => $f->{f}) : (),
    what => 'vn',
    results => 50,
    page => $f->{p},
  );

  my $title = $own ? mt('_wishlist_title_my') : mt('_wishlist_title_other', $u->{username});
  $self->htmlHeader(title => $title, noindex => 1);
  $self->htmlMainTabs('u', $u, 'wish');
  div class => 'mainbox';
   h1 $title;
   if(!@$list && $f->{f} == -1) {
      p mt '_wishlist_noresults';
     end;
     return $self->htmlFooter;
   }
   p class => 'browseopts';
    a $f->{f} == $_ ? (class => 'optselected') : (), href => "/u$uid/wish?f=$_",
        $_ == -1 ? mt '_wishlist_prio_all' : mt "_wish_$_"
      for (-1, @{$self->{wishlist_status}});
   end;
  end;

  if($own) {
    my $code = $self->authGetCode("/u$uid/wish");
    form action => "/u$uid/wish?formcode=$code;f=$f->{f};o=$f->{o};s=$f->{s};p=$f->{p}", method => 'post';
  }

  $self->htmlBrowse(
    class    => 'wishlist',
    items    => $list,
    nextpage => $np,
    options  => $f,
    pageurl  => "/u$uid/wish?f=$f->{f};o=$f->{o};s=$f->{s}",
    sorturl  => "/u$uid/wish?f=$f->{f}",
    header   => [
      [ mt('_wishlist_col_title') => 'title' ],
      [ mt('_wishlist_col_prio')  => 'wstat' ],
      [ mt('_wishlist_col_added') => 'added' ],
    ],
    row      => sub {
      my($s, $n, $i) = @_;
      Tr $n % 2 == 0 ? (class => 'odd') : ();
       td class => 'tc1';
        input type => 'checkbox', name => 'sel', value => $i->{vid}
          if $own;
        a href => "/v$i->{vid}", title => $i->{original}||$i->{title}, ' '.shorten $i->{title}, 70;
       end;
       td class => 'tc2', mt "_wish_$i->{wstat}";
       td class => 'tc3', $self->{l10n}->date($i->{added}, 'compact');
      end;
    },
    $own ? (footer => sub {
      Tr;
       td colspan => 3;
        Select name => 'batchedit', id => 'batchedit';
         option mt '_wishlist_select';
         optgroup label => mt '_wishlist_changeprio';
          option value => $_, mt "_wish_$_"
            for (@{$self->{wishlist_status}});
         end;
         option value => -1, mt '_wishlist_remove';
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
    return if !$self->authCheckCode;
    my $frm = $self->formValidate(
      { name => 'vid', required => 0, default => 0, multi => 1, template => 'int' },
      { name => 'rid', required => 0, default => 0, multi => 1, template => 'int' },
      { name => 'vns', required => 1, enum => [ -2, -1, @{$self->{vnlist_status}} ] },
      { name => 'rel', required => 1, enum => [ -2, -1, @{$self->{rlist_status}} ] },
    );
    my @vid = grep $_ > 0, @{$frm->{vid}};
    my @rid = grep $_ > 0, @{$frm->{rid}};
    if(!$frm->{_err} && @vid && $frm->{vns} > -2) {
      $self->dbVNListDel($uid, \@vid) if $frm->{vns} == -1;
      $self->dbVNListAdd($uid, \@vid, $frm->{vns}) if $frm->{vns} >= 0;
    }
    if(!$frm->{_err} && @rid && $frm->{rel} > -2) {
      $self->dbRListDel($uid, \@rid) if $frm->{rel} == -1;
      $self->dbRListAdd($uid, \@rid, $frm->{rel}) if $frm->{rel} >= 0;
    }
  }

  my($list, $np) = $self->dbVNListList(
    uid => $uid,
    results => 50,
    page => $f->{p},
    sort => $f->{s}, reverse => $f->{o} eq 'd',
    voted => $f->{v} == 0 ? undef : $f->{v} < 0 ? 0 : $f->{v},
    $f->{c} ne 'all' ? (char => $f->{c}) : (),
  );

  my $title = $own ? mt '_rlist_title_my' : mt '_rlist_title_other', $u->{username};
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
      a href => $url->(c => $_), $_ eq $f->{c} ? (class => 'optselected') : (), $_ eq 'all' ? mt('_char_all') : $_ ? uc $_ : '#';
    }
   end;
   p class => 'browseopts';
    a href => $url->(v =>  0),  0 == $f->{v} ? (class => 'optselected') : (), mt '_rlist_voted_all';
    a href => $url->(v =>  1),  1 == $f->{v} ? (class => 'optselected') : (), mt '_rlist_voted_only';
    a href => $url->(v => -1), -1 == $f->{v} ? (class => 'optselected') : (), mt '_rlist_voted_none';
   end;
  end;

  _vnlist_browse($self, $own, $list, $np, $f, $url, $uid);
  $self->htmlFooter;
}

sub _vnlist_browse {
  my($self, $own, $list, $np, $f, $url, $uid) = @_;

  form action => $url->().';formcode='.$self->authGetCode("/u$uid/list"), method => 'post'
    if $own;

  $self->htmlBrowse(
    class    => 'rlist',
    items    => $list,
    nextpage => $np,
    options  => $f,
    sorturl  => $url->(),
    pageurl  => $url->('page'),
    header   => [
      [ '' ],
      sub { td class => 'tc2', id => 'expandall'; lit '&#9656;'; end; },
      [ mt('_rlist_col_title') => 'title' ],
      [ '' ], [ '' ],
      [ mt('_rlist_col_status') ],
      [ mt('_rlist_col_releases').'*' ],
      [ mt('_rlist_col_vote')  => 'vote'  ],
    ],
    row      => sub {
      my($s, $n, $i) = @_;
      Tr $n % 2 == 0 ? (class => 'odd') : ();
       td class => 'tc1'; input type => 'checkbox', name => 'vid', value => $i->{vid} if $own; end;
       if(@{$i->{rels}}) {
         td class => 'tc2 collapse_but', id => "vid$i->{vid}"; lit '&#9656;'; end;
       } else {
         td class => 'tc2', '';
       }
       td class => 'tc3_5', colspan => 3;
        a href => "/v$i->{vid}", title => $i->{original}||$i->{title}, shorten $i->{title}, 70;
       end;
       td class => 'tc6', $i->{status} ? mt '_vnlist_status_'.$i->{status} : '';
       td class => 'tc7';
        my $obtained = grep $_->{status}==2, @{$i->{rels}};
        my $total = scalar @{$i->{rels}};
        my $txt = sprintf '%d/%d', $obtained, $total;
        $txt = qq|<b class="done">$txt</b>| if $total && $obtained == $total;
        $txt = qq|<b class="todo">$txt</b>| if $obtained < $total;
        lit $txt;
       end;
       td class => 'tc8', $i->{vote} || '-';
      end;

      for (@{$i->{rels}}) {
        Tr class => "collapse relhid collapse_vid$i->{vid}".($n%2 ? '':' odd');
         td class => 'tc1', '';
         td class => 'tc2';
          input type => 'checkbox', name => 'rid', value => $_->{rid} if $own;
         end;
         td class => 'tc3', $self->{l10n}->datestr($_->{released});
         td class => 'tc4';
          cssicon "lang $_", mt "_lang_$_" for @{$_->{languages}};
          cssicon "rt$_->{type}", mt "_rtype_$_->{type}";
         end;
         td class => 'tc5';
          a href => "/r$_->{rid}", title => $_->{original}||$_->{title}, shorten $_->{title}, 50;
         end;
         td class => 'tc6', $_->{status} ? mt '_rlist_status_'.$_->{status} : '';
         td class => 'tc7_8', colspan => 2, '';
        end;
      }
    },

    $own ? (footer => sub {
      Tr;
       td class => 'tc1'; input type => 'checkbox', name => 'vid', value => -1, class => 'checkall'; end;
       td class => 'tc2'; input type => 'checkbox', name => 'rid', value => -1, class => 'checkall'; end;
       td class => 'tc3_6', colspan => 4;
        Select id => 'vns', name => 'vns';
         option value => -2, mt '_rlist_withvn';
         optgroup label => mt '_rlist_changestat';
          option value => $_, mt "_vnlist_status_$_"
            for (@{$self->{vnlist_status}});
         end;
         option value => -1, mt '_rlist_del';
        end;
        Select id => 'rel', name => 'rel';
         option value => -2, mt '_rlist_withrel';
         optgroup label => mt '_rlist_changestat';
          option value => $_, mt "_rlist_status_$_"
            for (@{$self->{rlist_status}});
         end;
         option value => -1, mt '_rlist_del';
        end;
        input type => 'submit', value => mt '_rlist_update';
       end;
       td class => 'tc7_8', colspan => 2, mt '_rlist_releasenote';
      end;
    }) : (),
  );

  end if $own;
}

1;

