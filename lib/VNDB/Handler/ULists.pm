
package VNDB::Handler::ULists;

use strict;
use warnings;
use TUWF ':html', ':xml';
use VNDB::Func;


TUWF::register(
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
    { get => 'v', regex => qr/^(-1|([1-9]|10)(\.[0-9])?)$/ },
    { get => 'ref', required => 0, default => "/v$id" }
  );
  return $self->resNotFound if $f->{_err} || ($f->{v} != -1 && ($f->{v} > 10 || $f->{v} < 1));

  $self->dbVoteDel($uid, $id) if $f->{v} == -1;
  $self->dbVoteAdd($id, $uid, $f->{v}*10) if $f->{v} > 0;

  $self->resRedirect($f->{ref}, 'temp');
}


sub vnwish {
  my($self, $id) = @_;

  my $uid = $self->authInfo->{id};
  return $self->htmlDenied() if !$uid;

  return if !$self->authCheckCode;
  my $f = $self->formValidate(
    { get => 's', enum => [ -1..$#{$self->{wishlist_status}} ] },
    { get => 'ref', required => 0, default => "/v$id" }
  );
  return $self->resNotFound if $f->{_err};

  $self->dbWishListDel($uid, $id) if $f->{s} == -1;
  $self->dbWishListAdd($id, $uid, $f->{s}) if $f->{s} != -1;

  $self->resRedirect($f->{ref}, 'temp');
}


sub vnlist_e {
  my($self, $id) = @_;

  my $uid = $self->authInfo->{id};
  return $self->htmlDenied() if !$uid;

  return if !$self->authCheckCode;
  my $f = $self->formValidate(
    { get => 'e', enum => [ -1..$#{$self->{vnlist_status}} ] },
    { get => 'ref', required => 0, default => "/v$id" }
  );
  return $self->resNotFound if $f->{_err};

  $self->dbVNListDel($uid, $id) if $f->{e} == -1;
  $self->dbVNListAdd($uid, $id, $f->{e}) if $f->{e} != -1;

  $self->resRedirect($f->{ref}, 'temp');
}


sub rlist_e {
  my($self, $id) = @_;

  my $rid = $id;
  if(!$rid) {
    my $f = $self->formValidate({ get => 'id', required => 1, template => 'id' });
    return $self->resNotFound if $f->{_err};
    $rid = $f->{id};
  }

  my $uid = $self->authInfo->{id};
  return $self->htmlDenied() if !$uid;

  return if !$self->authCheckCode;
  my $f = $self->formValidate(
    { get => 'e', required => 1, enum => [ -1..$#{$self->{rlist_status}} ] },
    { get => 'ref', required => 0, default => "/r$rid" }
  );
  return $self->resNotFound if $f->{_err};

  $self->dbRListDel($uid, $rid) if $f->{e} == -1;
  $self->dbRListAdd($uid, $rid, $f->{e}) if $f->{e} >= 0;

  if($id) {
    $self->resRedirect($f->{ref}, 'temp');
  } else {
    # doesn't really matter what we return, as long as it's XML
    $self->resHeader('Content-type' => 'text/xml');
    xml;
    tag 'done', '';
  }
}


sub votelist {
  my($self, $type, $id) = @_;

  my $obj = $type eq 'v' ? $self->dbVNGet(id => $id)->[0] : $self->dbUserGet(uid => $id, what => 'hide_list')->[0];
  return $self->resNotFound if !$obj->{id};

  my $own = $type eq 'u' && $self->authInfo->{id} && $self->authInfo->{id} == $id;
  return $self->resNotFound if $type eq 'u' && !$own && !(!$obj->{hide_list} || $self->authCan('usermod'));

  my $f = $self->formValidate(
    { get => 'p',  required => 0, default => 1, template => 'page' },
    { get => 'o',  required => 0, default => 'd', enum => ['a', 'd'] },
    { get => 's',  required => 0, default => 'date', enum => [qw|date title vote|] },
    { get => 'c',  required => 0, default => 'all', enum => [ 'all', 'a'..'z', 0 ] },
  );
  return $self->resNotFound if $f->{_err};

  if($own && $self->reqMethod eq 'POST') {
    return if !$self->authCheckCode;
    my $frm = $self->formValidate(
      { post => 'vid', required => 1, multi => 1, template => 'id' },
      { post => 'batchedit', required => 1, enum => [ -2, -1, 1..10 ] },
    );
    my @vid = grep $_ && $_ > 0, @{$frm->{vid}};
    if(!$frm->{_err} && @vid && $frm->{batchedit} > -2) {
      $self->dbVoteDel($id, \@vid) if $frm->{batchedit} == -1;
      $self->dbVoteAdd(\@vid, $id, $frm->{batchedit}*10) if $frm->{batchedit} > 0;
    }
  }

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

  if($own) {
    my $code = $self->authGetCode("/u$id/votes");
    form action => "/u$id/votes?formcode=$code;c=$f->{c};s=$f->{s};p=$f->{p}", method => 'post';
  }

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
      Tr;
       td class => 'tc1';
        input type => 'checkbox', name => 'vid', value => $l->{vid} if $own;
        txt ' '.$self->{l10n}->date($l->{date});
       end;
       td class => 'tc2', fmtvote $l->{vote};
       td class => 'tc3';
        a href => $type eq 'v' ? ("/u$l->{uid}", $l->{username}) : ("/v$l->{vid}", shorten $l->{title}, 100);
       end;
      end;
    },
    $own ? (footer => sub {
      Tr;
       td colspan => 3, class => 'tc1';
        input type => 'checkbox', class => 'checkall', name => 'vid', value => 0;
        txt ' ';
        Select name => 'batchedit', id => 'batchedit';
         option value => -2, '-- with selected --';
         optgroup label => 'Change vote';
          option value => $_, "$_ (".mt("_vote_$_").')' for (reverse 1..10);
         end;
         option value => -1, 'revoke';
        end;
       end;
      end 'tr';
    }) : (),
  );
  end if $own;
  $self->htmlFooter;
}


sub wishlist {
  my($self, $uid) = @_;

  my $own = $self->authInfo->{id} && $self->authInfo->{id} == $uid;
  my $u = $self->dbUserGet(uid => $uid, what => 'hide_list')->[0];
  return $self->resNotFound if !$u || !$own && !(!$u->{hide_list} || $self->authCan('usermod'));

  my $f = $self->formValidate(
    { get => 'p', required => 0, default => 1, template => 'page' },
    { get => 'o', required => 0, default => 'd', enum => [ 'a', 'd' ] },
    { get => 's', required => 0, default => 'wstat', enum => [qw|title added wstat|] },
    { get => 'f', required => 0, default => -1, enum => [ -1..$#{$self->{wishlist_status}} ] },
  );
  return $self->resNotFound if $f->{_err};

  if($own && $self->reqMethod eq 'POST') {
    return if !$self->authCheckCode;
    my $frm = $self->formValidate(
      { post => 'sel', required => 0, default => 0, multi => 1, template => 'id' },
      { post => 'batchedit', required => 1, enum => [ -1..$#{$self->{wishlist_status}} ] },
    );
    $frm->{sel} = [ grep $_, @{$frm->{sel}} ]; # weed out "select all" checkbox
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
        $_ == -1 ? mt '_wishlist_prio_all' : $self->{wishlist_status}[$_]
      for (-1..$#{$self->{wishlist_status}});
   end;
  end 'div';

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
      Tr;
       td class => 'tc1';
        input type => 'checkbox', name => 'sel', value => $i->{vid}
          if $own;
        a href => "/v$i->{vid}", title => $i->{original}||$i->{title}, ' '.shorten $i->{title}, 70;
       end;
       td class => 'tc2', $self->{wishlist_status}[$i->{wstat}];
       td class => 'tc3', $self->{l10n}->date($i->{added}, 'compact');
      end;
    },
    $own ? (footer => sub {
      Tr;
       td colspan => 3;
        input type => 'checkbox', class => 'checkall', name => 'sel', value => 0;
        txt ' ';
        Select name => 'batchedit', id => 'batchedit';
         option mt '_wishlist_select';
         optgroup label => mt '_wishlist_changeprio';
          option value => $_, $self->{wishlist_status}[$_]
            for (0..$#{$self->{wishlist_status}});
         end;
         option value => -1, mt '_wishlist_remove';
        end;
       end;
      end;
    }) : (),
  );
  end 'form' if $own;
  $self->htmlFooter;
}


sub vnlist {
  my($self, $uid) = @_;

  my $own = $self->authInfo->{id} && $self->authInfo->{id} == $uid;
  my $u = $self->dbUserGet(uid => $uid, what => 'hide_list')->[0];
  return $self->resNotFound if !$u || !$own && !(!$u->{hide_list} || $self->authCan('usermod'));

  my $f = $self->formValidate(
    { get => 'p',  required => 0, default => 1, template => 'page' },
    { get => 'o',  required => 0, default => 'a', enum => [ 'a', 'd' ] },
    { get => 's',  required => 0, default => 'title', enum => [ 'title', 'vote' ] },
    { get => 'c',  required => 0, default => 'all', enum => [ 'all', 'a'..'z', 0 ] },
    { get => 'v',  required => 0, default => 0, enum => [ -1..1  ] },
    { get => 't',  required => 0, default => -1, enum => [ -1..$#{$self->{vnlist_status}} ] },
  );
  return $self->resNotFound if $f->{_err};

  if($own && $self->reqMethod eq 'POST') {
    return if !$self->authCheckCode;
    my $frm = $self->formValidate(
      { post => 'vid', required => 0, default => 0, multi => 1, template => 'id' },
      { post => 'rid', required => 0, default => 0, multi => 1, template => 'id' },
      { post => 'not', required => 0, default => '', maxlength => 2000 },
      { post => 'vns', required => 1, enum => [ -2..$#{$self->{vnlist_status}}, 999 ] },
      { post => 'rel', required => 1, enum => [ -2..$#{$self->{rlist_status}} ] },
    );
    my @vid = grep $_ > 0, @{$frm->{vid}};
    my @rid = grep $_ > 0, @{$frm->{rid}};
    if(!$frm->{_err} && @vid && $frm->{vns} > -2) {
      $self->dbVNListDel($uid, \@vid) if $frm->{vns} == -1;
      $self->dbVNListAdd($uid, \@vid, $frm->{vns}) if $frm->{vns} >= 0 && $frm->{vns} < 999;
      $self->dbVNListAdd($uid, \@vid, undef, $frm->{not}) if $frm->{vns} == 999;
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
    $f->{t} >= 0 ? (status => $f->{t}) : (),
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
    $_ .= ';t='.($n eq 't' ? $v : $f->{t});
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
    a href => $url->(v =>  0),  0 == $f->{v} ? (class => 'optselected') : (), mt '_rlist_all';
    a href => $url->(v =>  1),  1 == $f->{v} ? (class => 'optselected') : (), mt '_rlist_voted_only';
    a href => $url->(v => -1), -1 == $f->{v} ? (class => 'optselected') : (), mt '_rlist_voted_none';
   end;
   p class => 'browseopts';
    a href => $url->(t => -1), -1 == $f->{t} ? (class => 'optselected') : (), mt '_rlist_all';
    a href => $url->(t => $_), $_ == $f->{t} ? (class => 'optselected') : (), $self->{vnlist_status}[$_] for 0..$#{$self->{vnlist_status}};
   end;
  end 'div';

  _vnlist_browse($self, $own, $list, $np, $f, $url, $uid);
  $self->htmlFooter;
}

sub _vnlist_browse {
  my($self, $own, $list, $np, $f, $url, $uid) = @_;

  if($own) {
    form action => $url->(), method => 'post';
    input type => 'hidden', class => 'hidden', name => 'not', id => 'not', value => '';
    input type => 'hidden', class => 'hidden', name => 'formcode', id => 'formcode', value => $self->authGetCode("/u$uid/list");
  }

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
      Tr class => 'nostripe'.($n%2 ? ' odd' : '');
       td class => 'tc1'; input type => 'checkbox', name => 'vid', value => $i->{vid} if $own; end;
       if(@{$i->{rels}}) {
         td class => 'tc2 collapse_but', id => "vid$i->{vid}"; lit '&#9656;'; end;
       } else {
         td class => 'tc2', '';
       }
       td class => 'tc3_5', colspan => 3;
        a href => "/v$i->{vid}", title => $i->{original}||$i->{title}, shorten $i->{title}, 70;
        b class => 'grayedout', $i->{notes} if $i->{notes};
       end;
       td class => 'tc6', $i->{status} ? $self->{vnlist_status}[$i->{status}] : '';
       td class => 'tc7';
        my $obtained = grep $_->{status}==2, @{$i->{rels}};
        my $total = scalar @{$i->{rels}};
        my $txt = sprintf '%d/%d', $obtained, $total;
        $txt = qq|<b class="done">$txt</b>| if $total && $obtained == $total;
        $txt = qq|<b class="todo">$txt</b>| if $obtained < $total;
        lit $txt;
       end;
       td class => 'tc8', fmtvote $i->{vote};
      end 'tr';

      for (@{$i->{rels}}) {
        Tr class => "nostripe collapse relhid collapse_vid$i->{vid}".($n%2 ? ' odd':'');
         td class => 'tc1', '';
         td class => 'tc2';
          input type => 'checkbox', name => 'rid', value => $_->{rid} if $own;
         end;
         td class => 'tc3';
          lit $self->{l10n}->datestr($_->{released});
         end;
         td class => 'tc4';
          cssicon "lang $_", $self->{languages}{$_} for @{$_->{languages}};
          cssicon "rt$_->{type}", $_->{type};
         end;
         td class => 'tc5';
          a href => "/r$_->{rid}", title => $_->{original}||$_->{title}, shorten $_->{title}, 50;
         end;
         td class => 'tc6', $_->{status} ? $self->{rlist_status}[$_->{status}] : '';
         td class => 'tc7_8', colspan => 2, '';
        end 'tr';
      }
    },

    $own ? (footer => sub {
      Tr;
       td class => 'tc1'; input type => 'checkbox', name => 'vid', value => 0, class => 'checkall'; end;
       td class => 'tc2'; input type => 'checkbox', name => 'rid', value => 0, class => 'checkall'; end;
       td class => 'tc3_6', colspan => 4;
        Select id => 'vns', name => 'vns';
         option value => -2, mt '_rlist_withvn';
         optgroup label => mt '_rlist_changestat';
          option value => $_, $self->{vnlist_status}[$_]
            for (0..$#{$self->{vnlist_status}});
         end;
         option value => 999, mt '_rlist_setnote';
         option value => -1, mt '_rlist_del';
        end;
        Select id => 'rel', name => 'rel';
         option value => -2, mt '_rlist_withrel';
         optgroup label => mt '_rlist_changestat';
          option value => $_, $self->{rlist_status}[$_]
            for (0..$#{$self->{rlist_status}});
         end;
         option value => -1, mt '_rlist_del';
        end;
        input type => 'submit', value => mt '_rlist_update';
       end;
       td class => 'tc7_8', colspan => 2, mt '_rlist_releasenote';
      end 'tr';
    }) : (),
  );

  end 'form' if $own;
}

1;

