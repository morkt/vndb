
package VNDB::Handler::ULists;

use strict;
use warnings;
use YAWF ':html';
use VNDB::Func;


YAWF::register(
  qr{v([1-9]\d*)/vote},  \&vnvote,
  qr{v([1-9]\d*)/wish},  \&vnwish,
  qr{u([1-9]\d*)/wish},  \&wishlist,
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


sub wishlist {
  my($self, $uid) = @_;

  my $own = $self->authInfo->{id} && $self->authInfo->{id} == $uid;
  my $u = $self->dbUserGet(uid => $uid)->[0];
  return 404 if !$u || !$own && !$u->{show_list};

  my $f = $self->formValidate(
    { name => 'p', required => 0, default => 1, template => 'int' },
    { name => 'o', required => 0, default => 'a', enum => [ 'a', 'd' ] },
    { name => 's', required => 0, default => 'title', enum => [qw|title added|] },
    { name => 'f', required => 0, default => -1, enum => [ -1..$#{$self->{wishlist_status}} ] },
  );
  return 404 if $f->{_err};

  if($own && $self->reqMethod eq 'POST') {
    my $frm = $self->formValidate(
      { name => 'sel', required => 0, default => 0, multi => 1, template => 'int' },
      { name => 'wishbatch', required => 1, enum => [ -1..$#{$self->{wishlist_status}} ] },
    );
    if(!$frm->{_err} && @{$frm->{sel}} && $frm->{sel}[0]) {
      $self->dbWishListDel($uid, $frm->{sel}) if $frm->{wishbatch} == -1;
      $self->dbWishListAdd($frm->{sel}, $uid, $frm->{wishbatch}) if $frm->{wishbatch} >= 0;
    }
  }

  my($list, $np) = $self->dbWishListGet(
    uid => $uid,
    order => $f->{s}.' '.($f->{o} eq 'a' ? 'ASC' : 'DESC'),
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
      [ Priority => ''      ],
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
    footer   => sub {
      return if !$own;
      Tr;
       td colspan => 3;
        Select name => 'wishbatch', id => 'wishbatch';
         option '-- with selected --';
         optgroup label => 'Change priority';
          option value => $_, $self->{wishlist_status}[$_]
            for (0..$#{$self->{wishlist_status}});
         end;
         option value => -1, 'remove from wishlist';
        end;
       end;
      end;
    },
  );
  end if $own;
  $self->htmlFooter;
}


1;

