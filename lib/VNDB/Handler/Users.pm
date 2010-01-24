
package VNDB::Handler::Users;

use strict;
use warnings;
use YAWF ':html';
use VNDB::Func;


YAWF::register(
  qr{u([1-9]\d*)}             => \&userpage,
  qr{u/login}                 => \&login,
  qr{u/logout}                => \&logout,
  qr{u/newpass}               => \&newpass,
  qr{u/newpass/sent}          => \&newpass_sent,
  qr{u/register}              => \&register,
  qr{u([1-9]\d*)/edit}        => \&edit,
  qr{u([1-9]\d*)/posts}       => \&posts,
  qr{u([1-9]\d*)/del(/[od])?} => \&delete,
  qr{u/(all|[0a-z])}          => \&list,
);


sub userpage {
  my($self, $uid) = @_;

  my $u = $self->dbUserGet(uid => $uid, what => 'stats')->[0];
  return 404 if !$u->{id};

  my $votes = $u->{c_votes} && $self->dbVoteStats(uid => $uid);

  my $title = mt '_userpage_title', $u->{username};
  $self->htmlHeader(title => $title);
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
      if(!$u->{show_list}) {
        txt mt '_userpage_hidden';
      } elsif($votes) {
        my($total, $count) = (0, 0);
        for (1..@$votes) {
          $total += $_*$votes->[$_-1];
          $count += $votes->[$_-1];
        }
        lit mt '_userpage_votes_item', "/u$uid/list?v=1", $count, sprintf '%.2f', $total/$count;
      } else {
        txt '-';
      }
     end;
    end;

    Tr ++$i % 2 ? (class => 'odd') : ();
     td mt '_userpage_tags';
     td !$u->{c_tags} ? '-' : mt '_userpage_tags_item', $u->{c_tags}, $u->{tagcount}, $u->{tagvncount};
    end;

    Tr ++$i % 2 ? (class => 'odd') : ();
     td mt '_userpage_list';
     td !$u->{show_list} ? mt('_userpage_hidden') :
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
   end;
  end;

  if($u->{show_list} && $votes) {
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
      { name => 'usrname', required => 1, minlength => 2, maxlength => 15 },
      { name => 'usrpass', required => 1, minlength => 4, maxlength => 64, template => 'asciiprint' },
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
  shift->authLogout;
}


sub newpass {
  my $self = shift;

  return $self->resRedirect('/') if $self->authInfo->{id};

  my($frm, $u);
  if($self->reqMethod eq 'POST') {
    $frm = $self->formValidate(
      { name => 'mail', required => 1, template => 'mail' },
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
  #return $self->resRedirect('/') if $self->authInfo->{id};

  my $frm;
  if($self->reqMethod eq 'POST') {
    $frm = $self->formValidate(
      { name => 'usrname', template => 'pname', minlength => 2, maxlength => 15 },
      { name => 'mail', template => 'mail' },
      { name => 'usrpass',  minlength => 4, maxlength => 64, template => 'asciiprint' },
      { name => 'usrpass2', minlength => 4, maxlength => 64, template => 'asciiprint' },
    );
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

  $self->htmlForm({ frm => $frm, action => '/u/register' }, register => [ mt('_register_form_title'),
    [ input  => short => 'usrname', name => mt '_register_username' ],
    [ static => content => mt '_register_username_msg' ],
    [ input  => short => 'mail', name => mt '_register_mail' ],
    [ static => content => mt('_register_mail_msg').'<br /><br />' ],
    [ passwd => short => 'usrpass', name => mt('_register_password') ],
    [ passwd => short => 'usrpass2', name => mt('_register_confirm') ],
  ]);
  $self->htmlFooter;
}


sub edit {
  my($self, $uid) = @_;

  # are we allowed to edit this user?
  return $self->htmlDenied if !$self->authInfo->{id} || $self->authInfo->{id} != $uid && !$self->authCan('usermod');

  # fetch user info (cached if uid == loggedin uid)
  my $u = $self->authInfo->{id} == $uid ? $self->authInfo : $self->dbUserGet(uid => $uid, what => 'extended')->[0];
  return 404 if !$u->{id};

  # check POST data
  my $frm;
  if($self->reqMethod eq 'POST') {
    $frm = $self->formValidate(
      $self->authCan('usermod') ? (
        { name => 'usrname', template => 'pname', minlength => 2, maxlength => 15 },
        { name => 'rank', enum => [ 1..$#{$self->{user_ranks}} ] },
        { name => 'ign_votes', required => 0, default => 0 },
      ) : (),
      { name => 'mail', template => 'mail' },
      { name => 'usrpass',  required => 0, minlength => 4, maxlength => 64, template => 'asciiprint' },
      { name => 'usrpass2', required => 0, minlength => 4, maxlength => 64, template => 'asciiprint' },
      { name => 'flags_list', required => 0, default => 0 },
      { name => 'flags_nsfw', required => 0, default => 0 },
      { name => 'skin',     enum => [ '', keys %{$self->{skins}} ], required => 0, default => '' },
      { name => 'customcss', required => 0, maxlength => 2000, default => '' },
    );
    push @{$frm->{_err}}, 'passmatch'
      if ($frm->{usrpass} || $frm->{usrpass2}) && (!$frm->{usrpass} || !$frm->{usrpass2} || $frm->{usrpass} ne $frm->{usrpass2});
    if(!$frm->{_err}) {
      my %o;
      $o{username} = $frm->{usrname} if $frm->{usrname};
      $o{rank} = $frm->{rank} if $frm->{rank};
      $o{mail} = $frm->{mail};
      $o{skin} = $frm->{skin};
      $o{customcss} = $frm->{customcss};
      ($o{passwd}, $o{salt}) = $self->authPreparePass($frm->{usrpass}) if $frm->{usrpass};
      $o{show_list} = $frm->{flags_list} ? 1 : 0;
      $o{show_nsfw} = $frm->{flags_nsfw} ? 1 : 0;
      $o{ign_votes} = $frm->{ign_votes} ? 1 : 0 if $self->authCan('usermod');
      $self->dbUserEdit($uid, %o);
      $self->dbSessionDel($uid) if $frm->{usrpass};
      return $self->resRedirect("/u$uid/edit?d=1", 'post') if $uid != $self->authInfo->{id} || !$frm->{usrpass};
      return $self->authLogin($frm->{usrname}||$u->{username}, $frm->{usrpass}, "/u$uid/edit?d=1");
    }
  }

  # fill out default values
  $frm->{usrname}    ||= $u->{username};
  $frm->{$_} ||= $u->{$_} for(qw|rank mail skin customcss|);
  $frm->{flags_list} = $u->{show_list} if !defined $frm->{flags_list};
  $frm->{flags_nsfw} = $u->{show_nsfw} if !defined $frm->{flags_nsfw};
  $frm->{ign_votes} = $u->{ign_votes} if !defined $frm->{ign_votes};

  # create the page
  $self->htmlHeader(title => mt('_usere_title'), noindex => 1);
  $self->htmlMainTabs('u', $u, 'edit');
  if($self->reqParam('d')) {
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
    [ check  => short => 'flags_list', name => mt '_usere_flist', "/u$uid/list", "/u$uid/wish" ],
    [ check  => short => 'flags_nsfw', name => mt '_usere_fnsfw' ],
    [ select => short => 'skin', name => mt('_usere_skin'), width => 300, options => [
      map [ $_ eq $self->{skin_default} ? '' : $_, $self->{skins}{$_}.($self->debug?" [$_]":'') ], sort { $self->{skins}{$a} cmp $self->{skins}{$b} } keys %{$self->{skins}} ] ],
    [ textarea => short => 'customcss', name => mt '_usere_css' ],
  ]);
  $self->htmlFooter;
}


sub posts {
  my($self, $uid) = @_;

  # fetch user info (cached if uid == loggedin uid)
  my $u = $self->authInfo->{id} && $self->authInfo->{id} == $uid ? $self->authInfo : $self->dbUserGet(uid => $uid)->[0];
  return 404 if !$u->{id};

  my $f = $self->formValidate(
    { name => 'p', required => 0, default => 1, template => 'int' }
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
      sub { td; a href => '#', id => 'expandlist', mt '_js_expand'; txt mt '_uposts_col_title'; end; }
    ],
    row     => sub {
      my($s, $n, $l) = @_;
      Tr $n % 2 ? (class => 'odd') : ();
       td class => 'tc1'; a href => "/t$l->{tid}.$l->{num}", 't'.$l->{tid}; end;
       td class => 'tc2'; a href => "/t$l->{tid}.$l->{num}", '.'.$l->{num}; end;
       td class => 'tc3', $self->{l10n}->date($l->{date});
       td class => 'tc4'; a href => "/t$l->{tid}.$l->{num}", $l->{title}; end;
      end;
      Tr class => $n % 2 ? 'collapse msgsum odd hidden' : 'collapse msgsum hidden';
       td colspan => 4;
        lit bb2html $l->{msg}, 150;
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
    my $u = $self->dbUserGet(uid => $uid)->[0];
    return 404 if !$u->{id};
    $self->htmlHeader(title => 'Delete user', noindex => 1);
    $self->htmlMainTabs('u', $u, 'del');
    div class => 'mainbox';
     div class => 'warning';
      h2 'Delete user';
      p;
       lit qq|Are you sure you want to remove <a href="/u$uid">$u->{username}</a>'s account?<br /><br />|
          .qq|<a href="/u$uid/del/o">Yes, I'm not kidding!</a>|;
      end;
     end;
    end;
    $self->htmlFooter;
  }
  # delete
  elsif($act eq '/o') {
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
    { name => 's', required => 0, default => 'username', enum => [ qw|username registered votes changes tags| ] },
    { name => 'o', required => 0, default => 'a', enum => [ 'a','d' ] },
    { name => 'p', required => 0, default => 1, template => 'int' },
    { name => 'q', required => 0, default => '', maxlength => 50 },
  );
  return 404 if $f->{_err};

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
       td class => 'tc3'.(!$l->{show_list} && $self->authCan('usermod') ? ' linethrough' : '');
        lit !$l->{show_list} && !$self->authCan('usermod') ? '-' : !$l->{c_votes} ? 0 :
          qq|<a href="/u$l->{id}/list">$l->{c_votes}</a>|;
       end;
       td class => 'tc4';
        lit !$l->{c_changes} ? 0 : qq|<a href="/u$l->{id}/hist">$l->{c_changes}</a>|;
       end;
       td class => 'tc5';
        lit !$l->{c_tags} ? 0 : qq|<a href="/u$l->{id}/tags">$l->{c_tags}</a>|;
       end;
      end;
    },
  );
  $self->htmlFooter;
}


1;

