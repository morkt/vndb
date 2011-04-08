
package VNDB::Handler::Users;

use strict;
use warnings;
use TUWF ':html', 'xml_escape';
use VNDB::Func;
use POSIX 'floor';


TUWF::register(
  qr{u([1-9]\d*)}             => \&userpage,
  qr{u/login}                 => \&login,
  qr{u([1-9]\d*)/logout}      => \&logout,
  qr{u/newpass}               => \&newpass,
  qr{u/newpass/sent}          => \&newpass_sent,
  qr{u/register}              => \&register,
  qr{u([1-9]\d*)/edit}        => \&edit,
  qr{u([1-9]\d*)/posts}       => \&posts,
  qr{u([1-9]\d*)/del(/[od])?} => \&delete,
  qr{u/(all|[0a-z])}          => \&list,
  qr{u([1-9]\d*)/notifies}    => \&notifies,
  qr{u([1-9]\d*)/notify/([1-9]\d*)} => \&readnotify,
);


sub userpage {
  my($self, $uid) = @_;

  my $u = $self->dbUserGet(uid => $uid, what => 'stats hide_list')->[0];
  return $self->resNotFound if !$u->{id};

  my $votes = $u->{c_votes} && $self->dbVoteStats(uid => $uid);

  my $title = mt '_userpage_title', $u->{username};
  $self->htmlHeader(title => $title, noindex => 1);
  $self->htmlMainTabs('u', $u);
  div class => 'mainbox userpage';
   h1 $title;

   table;
    my $i = 0;

    Tr ++$i % 2 ? (class => 'odd') : ();
     td class => 'key', mt '_userpage_username';
     td;
      txt ucfirst($u->{username}).' (';
      a href => "/u$uid", "u$uid";
      txt ')';
     end;
    end;

    Tr ++$i % 2 ? (class => 'odd') : ();
     td mt '_userpage_registered';
     td $self->{l10n}->date($u->{registered});
    end;

    Tr ++$i % 2 ? (class => 'odd') : ();
     td mt '_userpage_edits';
     td;
      if($u->{c_changes}) {
        a href => "/u$uid/hist", $u->{c_changes};
      } else {
        txt '-';
      }
     end;
    end;

    Tr ++$i % 2 ? (class => 'odd') : ();
     td mt '_userpage_votes';
     td;
      if($u->{hide_list}) {
        txt mt '_userpage_hidden';
      } elsif($votes) {
        my($total, $count) = (0, 0);
        for (1..@$votes) {
          $total += $_*$votes->[$_-1];
          $count += $votes->[$_-1];
        }
        lit mt '_userpage_votes_item', "/u$uid/votes", $count, sprintf '%.2f', $total/$count;
      } else {
        txt '-';
      }
     end;
    end;

    Tr ++$i % 2 ? (class => 'odd') : ();
     td mt '_userpage_tags';
     td;
      if(!$u->{c_tags}) {
        txt '-';
      } else {
        txt mt '_userpage_tags_item', $u->{c_tags}, $u->{tagcount}, $u->{tagvncount};
        txt ' ';
        a href => "/g/links?u=$uid"; lit mt('_userpage_tags_browse').' &raquo;'; end;
      }
     end;
    end;

    Tr ++$i % 2 ? (class => 'odd') : ();
     td mt '_userpage_list';
     td $u->{hide_list} ? mt('_userpage_hidden') :
       mt('_userpage_list_item', $u->{releasecount}, $u->{vncount});
    end;

    Tr ++$i % 2 ? (class => 'odd') : ();
     td mt '_userpage_forum';
     td;
      lit mt '_userpage_forum_item',$u->{postcount}, $u->{threadcount};
      if($u->{postcount}) {
        txt ' ';
        a href => "/u$uid/posts"; lit mt('_userpage_forum_browse').' &raquo;'; end;
      }
     end;
    end;
   end 'table';
  end 'div';

  if(!$u->{hide_list} && $votes) {
    div class => 'mainbox';
     h1 mt '_userpage_votestats';
     $self->htmlVoteStats(u => $u, $votes);
    end;
  }

  if($u->{c_changes}) {
    my $list = $self->dbRevisionGet(what => 'item user', uid => $uid, results => 5);
    h1 class => 'boxtitle';
     a href => "/u$uid/hist", mt '_userpage_changes';
    end;
    $self->htmlBrowseHist($list, { p => 1 }, 0, "/u$uid/hist");
  }
  $self->htmlFooter;
}


sub login {
  my $self = shift;

  return $self->resRedirect('/') if $self->authInfo->{id};

  my $frm;
  if($self->reqMethod eq 'POST') {
    $frm = $self->formValidate(
      { post => 'usrname', required => 1, minlength => 2, maxlength => 15 },
      { post => 'usrpass', required => 1, minlength => 4, maxlength => 64, template => 'asciiprint' },
    );

    (my $ref = $self->reqHeader('Referer')||'/') =~ s/^\Q$self->{url}//;
    $ref = '/' if $ref =~ /^\/u\//;
    return if !$frm->{_err} && $self->authLogin($frm->{usrname}, $frm->{usrpass}, $ref);
    $frm->{_err} = [ 'login_failed' ] if !$frm->{_err};
  }

  $self->htmlHeader(noindex => 1, title => mt '_login_title');
  $self->htmlForm({ frm => $frm, action => '/u/login' }, login => [ mt('_login_title'),
    [ input  => short => 'usrname', name => mt '_login_username' ],
    [ static => content => '<a href="/u/register">'.mt('_login_register').'</a>' ],
    [ passwd => short => 'usrpass', name => mt '_login_password' ],
    [ static => content => '<a href="/u/newpass">'.mt('_login_forgotpass').'</a>' ],
  ]);
  $self->htmlFooter;
}


sub logout {
  my $self = shift;
  my $uid = shift;
  return $self->resNotFound if !$self->authInfo->{id} || $self->authInfo->{id} != $uid;
  $self->authLogout;
}


sub newpass {
  my $self = shift;

  return $self->resRedirect('/') if $self->authInfo->{id};

  my($frm, $u);
  if($self->reqMethod eq 'POST') {
    return if !$self->authCheckCode;
    $frm = $self->formValidate(
      { post => 'mail', required => 1, template => 'mail' },
    );
    if(!$frm->{_err}) {
      $u = $self->dbUserGet(mail => $frm->{mail})->[0];
      $frm->{_err} = [ 'nomail' ] if !$u || !$u->{id};
    }
    if(!$frm->{_err}) {
      my @chars = ( 'A'..'Z', 'a'..'z', 0..9 );
      my $pass = join '', map $chars[int rand $#chars+1], 0..8;
      my %o;
      ($o{passwd}, $o{salt}) = $self->authPreparePass($pass);
      $self->dbUserEdit($u->{id}, %o);
      $self->mail(mt('_newpass_mail_body', $u->{username}, $pass),
        To => $frm->{mail},
        From => 'VNDB <noreply@vndb.org>',
        Subject => mt('_newpass_mail_subject', $u->{username}),
      );
      return $self->resRedirect('/u/newpass/sent', 'post');
    }
  }

  $self->htmlHeader(title => mt('_newpass_title'), noindex => 1);
  div class => 'mainbox';
   h1 mt '_newpass_title';
   p mt '_newpass_msg';
  end;
  $self->htmlForm({ frm => $frm, action => '/u/newpass' }, newpass => [ mt('_newpass_reset_title'),
    [ input  => short => 'mail', name => mt '_newpass_mail' ],
  ]);
  $self->htmlFooter;
}


sub newpass_sent {
  my $self = shift;
  return $self->resRedirect('/') if $self->authInfo->{id};
  $self->htmlHeader(title => mt('_newpass_sent_title'), noindex => 1);
  div class => 'mainbox';
   h1 mt '_newpass_sent_title';
   div class => 'notice';
    h2 mt '_newpass_sent_subtitle';
    p;
     lit mt '_newpass_sent_msg';
    end;
   end;
  end;
  $self->htmlFooter;
}


sub register {
  my $self = shift;
  return $self->resRedirect('/') if $self->authInfo->{id};

  my $frm;
  if($self->reqMethod eq 'POST') {
    return if !$self->authCheckCode;
    $frm = $self->formValidate(
      { post => 'usrname',  template => 'pname', minlength => 2, maxlength => 15 },
      { post => 'mail',     template => 'mail' },
      { post => 'usrpass',  minlength => 4, maxlength => 64, template => 'asciiprint' },
      { post => 'usrpass2', minlength => 4, maxlength => 64, template => 'asciiprint' },
      { post => 'type',     regex => [ qr/^[1-3]$/ ] },
      { post => 'answer',   template => 'int' },
    );
    my $num = $self->{stats}{[qw|vn releases producers|]->[ $frm->{type} - 1 ]};
    push @{$frm->{_err}}, 'notanswer'  if !$frm->{_err} && ($frm->{answer} > $num || $frm->{answer} < $num*0.995);
    push @{$frm->{_err}}, 'passmatch'  if $frm->{usrpass} ne $frm->{usrpass2};
    push @{$frm->{_err}}, 'usrexists'  if $frm->{usrname} eq 'anonymous' || !$frm->{_err} && $self->dbUserGet(username => $frm->{usrname})->[0]{id};
    push @{$frm->{_err}}, 'mailexists' if !$frm->{_err} && $self->dbUserGet(mail => $frm->{mail})->[0]{id};
    push @{$frm->{_err}}, 'oneaday'    if !$frm->{_err} && $self->dbUserGet(ip => $self->reqIP, registered => time-24*3600)->[0]{id};

    if(!$frm->{_err}) {
      my ($pass, $salt) = $self->authPreparePass($frm->{usrpass});
      $self->dbUserAdd($frm->{usrname}, $pass, $salt, $frm->{mail});
      return $self->authLogin($frm->{usrname}, $frm->{usrpass}, '/');
    }
  }

  $self->htmlHeader(title => mt('_register_title'), noindex => 1);
  div class => 'mainbox';
   h1 mt '_register_title';
   h2 mt '_register_why';
   p;
    lit mt '_register_why_msg';
   end;
  end;

  my $type = $frm->{type} || floor(rand 3)+1;
  $self->htmlForm({ frm => $frm, action => '/u/register' }, register => [ mt('_register_form_title'),
    [ hidden => short => 'type', value => $type ],
    [ input  => short => 'usrname', name => mt '_register_username' ],
    [ static => content => mt '_register_username_msg' ],
    [ input  => short => 'mail', name => mt '_register_mail' ],
    [ static => content => mt('_register_mail_msg').'<br /><br />' ],
    [ passwd => short => 'usrpass', name => mt('_register_password') ],
    [ passwd => short => 'usrpass2', name => mt('_register_confirm') ],
    [ static => content => '<br /><br />'.mt('_register_question', $type-1) ],
    [ input  => short => 'answer', name => mt '_register_answer' ],
  ]);
  $self->htmlFooter;
}


sub edit {
  my($self, $uid) = @_;

  # are we allowed to edit this user?
  return $self->htmlDenied if !$self->authInfo->{id} || $self->authInfo->{id} != $uid && !$self->authCan('usermod');

  # fetch user info (cached if uid == loggedin uid)
  my $u = $self->authInfo->{id} == $uid ? $self->authInfo : $self->dbUserGet(uid => $uid, what => 'extended prefs')->[0];
  return $self->resNotFound if !$u->{id};

  # check POST data
  my $frm;
  if($self->reqMethod eq 'POST') {
    return if !$self->authCheckCode;
    $frm = $self->formValidate(
      $self->authCan('usermod') ? (
        { post => 'usrname',   template => 'pname', minlength => 2, maxlength => 15 },
        { post => 'rank',      enum => [ 1..$#{$self->{user_ranks}} ] },
        { post => 'ign_votes', required => 0, default => 0 },
      ) : (),
      { post => 'mail',       template => 'mail' },
      { post => 'usrpass',    required => 0, minlength => 4, maxlength => 64, template => 'asciiprint' },
      { post => 'usrpass2',   required => 0, minlength => 4, maxlength => 64, template => 'asciiprint' },
      { post => 'hide_list',  required => 0, default => 0,  enum => [0,1] },
      { post => 'show_nsfw',  required => 0, default => 0,  enum => [0,1] },
      { post => 'skin',       required => 0, default => '', enum => [ '', keys %{$self->{skins}} ] },
      { post => 'customcss',  required => 0, maxlength => 2000, default => '' },
    );
    push @{$frm->{_err}}, 'passmatch'
      if ($frm->{usrpass} || $frm->{usrpass2}) && (!$frm->{usrpass} || !$frm->{usrpass2} || $frm->{usrpass} ne $frm->{usrpass2});
    if(!$frm->{_err}) {
      $self->dbUserPrefSet($uid, $_ => $frm->{$_}) for (qw|skin customcss show_nsfw hide_list |);
      my %o;
      $o{username} = $frm->{usrname} if $frm->{usrname};
      $o{rank} = $frm->{rank} if $frm->{rank};
      $o{mail} = $frm->{mail};
      ($o{passwd}, $o{salt}) = $self->authPreparePass($frm->{usrpass}) if $frm->{usrpass};
      $o{ign_votes} = $frm->{ign_votes} ? 1 : 0 if $self->authCan('usermod');
      $self->dbUserEdit($uid, %o);
      $self->dbSessionDel($uid) if $frm->{usrpass};
      return $self->resRedirect("/u$uid/edit?d=1", 'post') if $uid != $self->authInfo->{id} || !$frm->{usrpass};
      return $self->authLogin($frm->{usrname}||$u->{username}, $frm->{usrpass}, "/u$uid/edit?d=1");
    }
  }

  # fill out default values
  $frm->{usrname}    ||= $u->{username};
  $frm->{$_} ||= $u->{$_} for(qw|rank mail|);
  $frm->{$_} //= $u->{prefs}{$_} for(qw|skin customcss show_nsfw hide_list|);
  $frm->{ign_votes} = $u->{ign_votes} if !defined $frm->{ign_votes};

  # create the page
  $self->htmlHeader(title => mt('_usere_title'), noindex => 1);
  $self->htmlMainTabs('u', $u, 'edit');
  if($self->reqGet('d')) {
    div class => 'mainbox';
     h1 mt '_usere_saved_title';
     div class => 'notice';
      p mt '_usere_saved_msg';
     end;
    end
  }
  $self->htmlForm({ frm => $frm, action => "/u$uid/edit" }, useredit => [ mt('_usere_title'),
    [ part   => title => mt '_usere_geninfo' ],
    $self->authCan('usermod') ? (
      [ input  => short => 'usrname', name => mt('_usere_username') ],
      [ select => short => 'rank', name => mt('_usere_rank'), options => [
        map [ $_, mt '_urank_'.$_ ], 1..$#{$self->{user_ranks}} ] ],
      [ check  => short => 'ign_votes', name => mt '_usere_ignvotes' ],
    ) : (
      [ static => label => mt('_usere_username'), content => $frm->{usrname} ],
    ),
    [ input  => short => 'mail', name => mt '_usere_mail' ],

    [ part   => title => mt '_usere_changepass' ],
    [ static => content => mt '_usere_changepass_msg' ],
    [ passwd => short => 'usrpass', name => mt '_usere_password' ],
    [ passwd => short => 'usrpass2', name => mt '_usere_confirm' ],

    [ part   => title => mt '_usere_options' ],
    [ check  => short => 'hide_list', name => mt '_usere_flist', "/u$uid/list", "/u$uid/votes", "/u$uid/wish" ],
    [ check  => short => 'show_nsfw', name => mt '_usere_fnsfw' ],
    [ select => short => 'skin', name => mt('_usere_skin'), width => 300, options => [
      map [ $_ eq $self->{skin_default} ? '' : $_, $self->{skins}{$_}[0].($self->debug?" [$_]":'') ], sort { $self->{skins}{$a}[0] cmp $self->{skins}{$b}[0] } keys %{$self->{skins}} ] ],
    [ textarea => short => 'customcss', name => mt '_usere_css' ],
  ]);
  $self->htmlFooter;
}


sub posts {
  my($self, $uid) = @_;

  # fetch user info (cached if uid == loggedin uid)
  my $u = $self->authInfo->{id} && $self->authInfo->{id} == $uid ? $self->authInfo : $self->dbUserGet(uid => $uid, what => 'hide_list')->[0];
  return $self->resNotFound if !$u->{id};

  my $f = $self->formValidate(
    { get => 'p', required => 0, default => 1, template => 'int' }
  );

  my($posts, $np) = $self->dbPostGet(uid => $uid, hide => 1, what => 'thread', page => $f->{p}, sort => 'date', reverse => 1);

  my $title = mt '_uposts_title', $u->{username};
  $self->htmlHeader(title => $title, noindex => 1);
  $self->htmlMainTabs(u => $u, 'posts');
  div class => 'mainbox';
   h1 $title;
   if(!@$posts) {
     p mt '_uposts_noresults', $u->{username};
   }
  end;

  $self->htmlBrowse(
    items    => $posts,
    class    => 'uposts',
    options  => $f,
    nextpage => $np,
    pageurl  => "/u$uid/posts",
    header   => [
      [ '' ],
      [ '' ],
      [ mt '_uposts_col_date' ],
      [ mt '_uposts_col_title' ],
    ],
    row     => sub {
      my($s, $n, $l) = @_;
      Tr $n % 2 ? (class => 'odd') : ();
       td class => 'tc1'; a href => "/t$l->{tid}.$l->{num}", 't'.$l->{tid}; end;
       td class => 'tc2'; a href => "/t$l->{tid}.$l->{num}", '.'.$l->{num}; end;
       td class => 'tc3', $self->{l10n}->date($l->{date});
       td class => 'tc4';
        a href => "/t$l->{tid}.$l->{num}", $l->{title};
        b class => 'grayedout'; lit bb2html $l->{msg}, 150; end;
       end;
      end;
    },
  ) if @$posts;
  $self->htmlFooter;
}


sub delete {
  my($self, $uid, $act) = @_;
  return $self->htmlDenied if !$self->authCan('usermod');

  # rarely used admin function, won't really need translating

  # confirm
  if(!$act) {
    my $code = $self->authGetCode("/u$uid/del/o");
    my $u = $self->dbUserGet(uid => $uid, what => 'hide_list')->[0];
    return $self->resNotFound if !$u->{id};
    $self->htmlHeader(title => 'Delete user', noindex => 1);
    $self->htmlMainTabs('u', $u, 'del');
    div class => 'mainbox';
     div class => 'warning';
      h2 'Delete user';
      p;
       lit qq|Are you sure you want to remove <a href="/u$uid">$u->{username}</a>'s account?<br /><br />|
          .qq|<a href="/u$uid/del/o?formcode=$code">Yes, I'm not kidding!</a>|;
      end;
     end;
    end;
    $self->htmlFooter;
  }
  # delete
  elsif($act eq '/o') {
    return if !$self->authCheckCode;
    $self->dbUserDel($uid);
    $self->resRedirect("/u$uid/del/d", 'post');
  }
  # done
  elsif($act eq '/d') {
    $self->htmlHeader(title => 'Delete user', noindex => 1);
    div class => 'mainbox';
     div class => 'notice';
      p 'User deleted.';
     end;
    end;
    $self->htmlFooter;
  }
}


sub list {
  my($self, $char) = @_;

  my $f = $self->formValidate(
    { get => 's', required => 0, default => 'username', enum => [ qw|username registered votes changes tags| ] },
    { get => 'o', required => 0, default => 'a', enum => [ 'a','d' ] },
    { get => 'p', required => 0, default => 1, template => 'int' },
    { get => 'q', required => 0, default => '', maxlength => 50 },
  );
  return $self->resNotFound if $f->{_err};

  $self->htmlHeader(noindex => 1, title => mt '_ulist_title');

  div class => 'mainbox';
   h1 mt '_ulist_title';
   form action => '/u/all', 'accept-charset' => 'UTF-8', method => 'get';
    $self->htmlSearchBox('u', $f->{q});
   end;
   p class => 'browseopts';
    for ('all', 'a'..'z', 0) {
      a href => "/u/$_", $_ eq $char ? (class => 'optselected') : (), $_ eq 'all' ? mt('_char_all') : $_ ? uc $_ : '#';
    }
   end;
  end;

  my($list, $np) = $self->dbUserGet(
    sort => $f->{s}, reverse => $f->{o} eq 'd',
    what => 'hide_list',
    $char ne 'all' ? (
      firstchar => $char ) : (),
    results => 50,
    page => $f->{p},
    search => $f->{q},
  );

  $self->htmlBrowse(
    items    => $list,
    options  => $f,
    nextpage => $np,
    pageurl  => "/u/$char?o=$f->{o};s=$f->{s};q=$f->{q}",
    sorturl  => "/u/$char?q=$f->{q}",
    header   => [
      [ mt('_ulist_col_username'),   'username'   ],
      [ mt('_ulist_col_registered'), 'registered' ],
      [ mt('_ulist_col_votes'),      'votes'      ],
      [ mt('_ulist_col_edits'),      'changes'    ],
      [ mt('_ulist_col_tags'),       'tags'       ],
    ],
    row     => sub {
      my($s, $n, $l) = @_;
      Tr $n % 2 ? (class => 'odd') : ();
       td class => 'tc1';
        a href => '/u'.$l->{id}, $l->{username};
       end;
       td class => 'tc2', $self->{l10n}->date($l->{registered});
       td class => 'tc3'.($l->{hide_list} && $self->authCan('usermod') ? ' linethrough' : '');
        lit $l->{hide_list} && !$self->authCan('usermod') ? '-' : !$l->{c_votes} ? 0 :
          qq|<a href="/u$l->{id}/votes">$l->{c_votes}</a>|;
       end;
       td class => 'tc4';
        lit !$l->{c_changes} ? 0 : qq|<a href="/u$l->{id}/hist">$l->{c_changes}</a>|;
       end;
       td class => 'tc5';
        lit !$l->{c_tags} ? 0 : qq|<a href="/g/links?u=$l->{id}">$l->{c_tags}</a>|;
       end;
      end 'tr';
    },
  );
  $self->htmlFooter;
}


sub notifies {
  my($self, $uid) = @_;

  my $u = $self->authInfo;
  return $self->htmlDenied if !$u->{id} || $uid != $u->{id};

  my $f = $self->formValidate(
    { get => 'p', required => 0, default => 1, template => 'int' },
    { get => 'r', required => 0, default => 0, enum => [0,1] },
  );
  return $self->resNotFound if $f->{_err};

  # changing the notification settings
  my $saved;
  if($self->reqMethod() eq 'POST' && $self->reqPost('set')) {
    return if !$self->authCheckCode;
    my $frm = $self->formValidate(
      { post => 'notify_nodbedit', required => 0, default => 1, enum => [0,1] },
      { post => 'notify_announce', required => 0, default => 0, enum => [0,1] }
    );
    return $self->resNotFound if $frm->{_err};
    $self->authPref($_, $frm->{$_}) for ('notify_nodbedit', 'notify_announce');
    $saved = 1;

  # updating notifications
  } elsif($self->reqMethod() eq 'POST') {
    return if !$self->authCheckCode;
    my $frm = $self->formValidate(
      { post => 'notifysel', multi => 1, required => 0, template => 'int' },
      { post => 'markread', required => 0 },
      { post => 'remove', required => 0 }
    );
    return $self->resNotFound if $frm->{_err};
    my @ids = grep $_, @{$frm->{notifysel}};
    $self->dbNotifyMarkRead(@ids) if @ids && $frm->{markread};
    $self->dbNotifyRemove(@ids) if @ids && $frm->{remove};
    $self->authInfo->{notifycount} = $self->dbUserGet(uid => $uid, what => 'notifycount')->[0]{notifycount};
  }

  my($list, $np) = $self->dbNotifyGet(
    uid => $uid,
    page => $f->{p},
    results => 25,
    what => 'titles',
    read => $f->{r} == 1 ? undef : 0,
    reverse => $f->{r} == 1,
  );

  $self->htmlHeader(title => mt('_usern_title'), noindex => 1);
  $self->htmlMainTabs(u => $u);
  div class => 'mainbox';
   h1 mt '_usern_title';
   p class => 'browseopts';
    a !$f->{r} ? (class => 'optselected') : (), href => "/u$uid/notifies?r=0", mt '_usern_o_unread';
    a  $f->{r} ? (class => 'optselected') : (), href => "/u$uid/notifies?r=1", mt '_usern_o_alsoread';
   end;
   p mt '_usern_nonotifies' if !@$list;
  end;

  my $code = $self->authGetCode("/u$uid/notifies");

  if(@$list) {
    form action => "/u$uid/notifies?r=$f->{r};formcode=$code", method => 'post';
    $self->htmlBrowse(
      items    => $list,
      options  => $f,
      nextpage => $np,
      class    => 'notifies',
      pageurl  => "/u$uid/notifies?r=$f->{r}",
      header   => [
        [ '' ],
        [ mt '_usern_col_type' ],
        [ mt '_usern_col_age' ],
        [ mt '_usern_col_id' ],
        [ mt '_usern_col_act' ],
      ],
      row     => sub {
        my($s, $n, $l) = @_;
        Tr class => join ' ', $n%2?'odd':'', $l->{read}?'':'unread';
         td class => 'tc1';
          input type => 'checkbox', name => 'notifysel', value => "$l->{id}";
         end;
         td class => 'tc2', mt "_usern_type_$l->{ntype}";
         td class => 'tc3', $self->{l10n}->age($l->{date});
         td class => 'tc4';
          a href => "/u$uid/notify/$l->{id}", "$l->{ltype}$l->{iid}".($l->{subid}?".$l->{subid}":'');
         end;
         td class => 'tc5', onclick => qq|javascript:location.href="/u$uid/notify/$l->{id}"|;
          lit mt '_usern_n_'.(
            $l->{ltype} eq 't' ? ($l->{subid} == 1 ? 't_new' : 't_reply')
            : 'item_edit'),
            sprintf('<i>%s</i>', xml_escape $l->{c_title}), sprintf('<i>%s</i>', xml_escape $l->{username});
         end;
        end 'tr';
      },
      footer => sub {
        Tr;
         td colspan => 5;
          input type => 'checkbox', class => 'checkall', name => 'notifysel', value => 0;
          txt ' ';
          input type => 'submit', name => 'markread', value => mt '_usern_but_markread';
          input type => 'submit', name => 'remove', value => mt '_usern_but_remove';
          b class => 'grayedout', ' '.mt '_usern_autodel';
         end;
        end;
      }
    );
    end;
  }

  form method => 'post', action => "/u$uid/notifies?formcode=$code";
  div class => 'mainbox';
   h1 mt '_usern_set_title';
   div class => 'notice', mt '_usern_set_saved' if $saved;
   p;
    for('nodbedit', 'announce') {
      my $def = $_ eq 'nodbedit'? 0 : 1;
      input type => 'checkbox', name => "notify_$_", id => "notify_$_", value => $def,
        ($self->authPref("notify_$_")||0) == $def ? (checked => 'checked') : ();
      label for => "notify_$_", ' '.mt("_usern_set_$_");
      br;
    }
    input type => 'submit', name => 'set', value => mt '_usern_set_submit';
   end;
  end;
  end 'form';
  $self->htmlFooter;
}


sub readnotify {
  my($self, $uid, $nid) = @_;
  return $self->htmlDenied if !$self->authInfo->{id} || $uid != $self->authInfo->{id};
  my $n = $self->dbNotifyGet(uid => $uid, id => $nid)->[0];
  return $self->resNotFound if !$n->{iid};
  $self->dbNotifyMarkRead($n->{id}) if !$n->{read};
  # NOTE: for t+.+ IDs, this will create a double redirect, which is rather awkward...
  $self->resRedirect("/$n->{ltype}$n->{iid}".($n->{subid}?".$n->{subid}":''), 'perm');
}


1;

