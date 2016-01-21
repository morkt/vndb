
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
  qr{u([1-9]\d*)/setpass}     => \&setpass,
  qr{u/register}              => \&register,
  qr{u/register/done}         => \&register_done,
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
  my $list_visible = !$u->{hide_list} || ($self->authInfo->{id}||0) == $u->{id} || $self->authCan('usermod');

  my $title = "$u->{username}'s profile";
  $self->htmlHeader(title => $title, noindex => 1);
  $self->htmlMainTabs('u', $u);
  div class => 'mainbox userpage';
   h1 $title;

   table class => 'stripe';

    Tr;
     td class => 'key', 'Username';
     td;
      txt ucfirst($u->{username}).' (';
      a href => "/u$uid", "u$uid";
      txt ')';
     end;
    end;

    Tr;
     td 'Registered';
     td fmtdate $u->{registered};
    end;

    Tr;
     td 'Edits';
     td;
      if($u->{c_changes}) {
        a href => "/u$uid/hist", $u->{c_changes};
      } else {
        txt '-';
      }
     end;
    end;

    Tr;
     td 'Votes';
     td;
      if(!$list_visible) {
        txt 'hidden';
      } elsif($votes) {
        my($total, $count) = (0, 0);
        for (1..@$votes) {
          $count += $votes->[$_-1][0];
          $total += $votes->[$_-1][1];
        }
        a href => "/u$uid/votes", $count;
        txt sprintf ' (%.2f average)', $total/$count/10;
      } else {
        txt '-';
      }
     end;
    end;

    Tr;
     td 'Tags';
     td;
      if(!$u->{c_tags}) {
        txt '-';
      } else {
        txt sprintf '%d vote%s on %d distinct tag%s and %d visual novel%s. ',
          $u->{c_tags},     $u->{c_tags}     == 1 ? '' : 's',
          $u->{tagcount},   $u->{tagcount}   == 1 ? '' : 's',
          $u->{tagvncount}, $u->{tagvncount} == 1 ? '' : 's';
        a href => "/g/links?u=$uid"; lit 'Browse tags &raquo;'; end;
      }
     end;
    end;

    Tr;
     td 'List stats';
     td !$list_visible ? 'hidden' :
       sprintf '%d release%s of %d visual novel%s.',
         $u->{releasecount}, $u->{releasecount} == 1 ? '' : 's',
         $u->{vncount},      $u->{vncount}      == 1 ? '' : 's';
    end;

    Tr;
     td 'Forum stats';
     td;
      txt sprintf '%d post%s, %d new thread%s. ',
        $u->{postcount},   $u->{postcount}   == 1 ? '' : 's',
        $u->{threadcount}, $u->{threadcount} == 1 ? '' : 's';
      if($u->{postcount}) {
        a href => "/u$uid/posts"; lit 'Browse posts &raquo;'; end;
      }
     end;
    end;
   end 'table';
  end 'div';

  if($votes && $list_visible) {
    div class => 'mainbox';
     h1 'Vote statistics';
     $self->htmlVoteStats(u => $u, $votes);
    end;
  }

  if($u->{c_changes}) {
    my $list = $self->dbRevisionGet(uid => $uid, results => 5);
    h1 class => 'boxtitle';
     a href => "/u$uid/hist", 'Recent changes';
    end;
    $self->htmlBrowseHist($list, { p => 1 }, 0, "/u$uid/hist");
  }
  $self->htmlFooter;
}


sub login {
  my $self = shift;

  return $self->resRedirect('/') if $self->authInfo->{id};

  my $tm = $self->dbThrottleGet(norm_ip($self->reqIP));
  if($tm-time() > $self->{login_throttle}[1]) {
    $self->htmlHeader(title => 'Login');
    div class => 'mainbox';
     h1 'Login';
     div class => 'warning';
      h2 'Maximum failed login attempts reached.';
      p;
       txt 'Login has been temporarily disabled for your IP address. You can wait a few hours and try again,'
          .' or you can try from a different IP address. If you forgot your password, you can still use the ';
       a href => '/u/newpass', 'password reset';
       txt ' functionality. If you still have trouble logging in, send a mail to ';
       a href => 'mailto:contact@vndb.org', 'contact@vndb.org';
       txt '.';
      end;
     end;
    end 'div';
    $self->htmlFooter;
    return;
  }

  my $ref = $self->formValidate({ param => 'ref', required => 0, default => '/'})->{ref};

  my $frm;
  if($self->reqMethod eq 'POST') {
    return if !$self->authCheckCode;
    $frm = $self->formValidate(
      { post => 'usrname', required => 1, minlength => 2, maxlength => 15 },
      { post => 'usrpass', required => 1, minlength => 4, maxlength => 64, template => 'ascii' },
    );

    if(!$frm->{_err}) {
      $frm->{usrname} = lc $frm->{usrname};
      return if $self->authLogin($frm->{usrname}, $frm->{usrpass}, $ref);
      $frm->{_err} = [ 'Invalid username or password' ];
      $self->dbThrottleSet(norm_ip($self->reqIP), $tm+$self->{login_throttle}[0]);
    }
  }

  $self->htmlHeader(noindex => 1, title => 'Login');
  $self->htmlForm({ frm => $frm, action => '/u/login' }, login => [ 'Login',
    [ hidden => short => 'ref', value => $ref ],
    [ input  => short => 'usrname', name => 'Username' ],
    [ static => content => '<a href="/u/register">No account yet?</a>' ],
    [ passwd => short => 'usrpass', name => 'Password' ],
    [ static => content => '<a href="/u/newpass">Forgot your password?</a>' ],
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
    $frm = $self->formValidate({ post => 'mail', template => 'email' });
    if(!$frm->{_err}) {
      $u = $self->dbUserGet(mail => $frm->{mail})->[0];
      $frm->{_err} = [ 'No user found with that email address' ] if !$u || !$u->{id};
    }
    if(!$frm->{_err}) {
      my %o;
      my $token;
      ($token, $o{passwd}) = $self->authPrepareReset();
      $self->dbUserEdit($u->{id}, %o);
      my $body = sprintf
         "Hello %s,\n\nYour VNDB.org login has been disabled, you can now set a new password by following the link below:\n\n"
        ."%s\n\nNow don't forget your password again! :-)\n\nvndb.org",
        $u->{username}, $self->reqBaseURI()."/u$u->{id}/setpass?t=$token";
      $self->mail($body,
        To => $frm->{mail},
        From => 'VNDB <noreply@vndb.org>',
        Subject => "Password reset for $u->{username}",
      );
      return $self->resRedirect('/u/newpass/sent', 'post');
    }
  }

  $self->htmlHeader(title => 'Forgot password', noindex => 1);
  div class => 'mainbox';
   h1 'Forgot password';
   p 'Forgot your password and can\'t login to VNDB anymore?'
    .' Don\'t worry! Just give us the email address you used to register on VNDB,'
    .' and we\'ll send you instructions to set a new password within a few minutes!';
  end;
  $self->htmlForm({ frm => $frm, action => '/u/newpass' }, newpass => [ 'Reset password',
    [ input  => short => 'mail', name => 'Email' ],
  ]);
  $self->htmlFooter;
}


sub newpass_sent {
  my $self = shift;
  return $self->resRedirect('/') if $self->authInfo->{id};
  $self->htmlHeader(title => 'New password', noindex => 1);
  div class => 'mainbox';
   h1 'New password';
   div class => 'notice';
    p 'Your password has been reset and instructions to set a new one should reach your mailbox in a few minutes.';
   end;
  end;
  $self->htmlFooter;
}


sub setpass {
  my($self, $uid) = @_;
  return $self->resRedirect('/') if $self->authInfo->{id};

  my $t = $self->formValidate({get => 't', regex => qr/^[a-f0-9]{40}$/i });
  return $self->resNotFound if $t->{_err};
  $t = $t->{t};

  my $u = $self->dbUserGet(uid => $uid, what => 'extended')->[0];
  return $self->resNotFound if !$u || !$self->authValidateReset($u->{passwd}, $t);

  my $frm;
  if($self->reqMethod eq 'POST') {
    return if !$self->authCheckCode("/u$u->{id}/setpass?t=$t");
    $frm = $self->formValidate(
      { post => 'usrpass',  minlength => 4, maxlength => 64, template => 'ascii' },
      { post => 'usrpass2', minlength => 4, maxlength => 64, template => 'ascii' },
    );
    push @{$frm->{_err}}, 'Passwords do not match' if $frm->{usrpass} ne $frm->{usrpass2};

    if(!$frm->{_err}) {
      my %o = (email_confirmed => 1);
      $o{passwd} = $self->authPreparePass($frm->{usrpass});
      $self->dbUserEdit($uid, %o);
      return $self->authCreateSession($u->{username}, "/u$uid");
    }
  }

  $self->htmlHeader(title => "Set password for $u->{username}", noindex => 1);
  $self->htmlForm({ frm => $frm, action => "/u$u->{id}/setpass?t=$t" }, setpass => [ "Set password for $u->{username}",
    [ static => nolabel => 1, content => 'Now you can set a password for your account.'
        .' You will be logged in automatically after your password has been saved.' ],
    [ passwd => short => 'usrpass',  name => 'Password' ],
    [ passwd => short => 'usrpass2', name => 'Confirm password' ],
  ]);
  $self->htmlFooter;
}


sub register {
  my $self = shift;
  return $self->resRedirect('/') if $self->authInfo->{id};

  my $frm;
  if($self->reqMethod eq 'POST') {
    return if !$self->authCheckCode;
    $frm = $self->formValidate(
      { post => 'usrname',  template => 'uname' },
      { post => 'mail',     template => 'email' },
      { post => 'type',     enum => [1..3] },
      { post => 'answer',   template => 'uint' },
    );
    my $num = $self->{stats}{[qw|vn releases producers|]->[ $frm->{type} - 1 ]};
    push @{$frm->{_err}}, 'Question was not correctly answered. Are you sure you are a human?'
      if !$frm->{_err} && ($frm->{answer} > $num*1.005 || $frm->{answer} < $num*0.995);
    push @{$frm->{_err}}, 'Someone already has this username, please choose another name'
      if $frm->{usrname} eq 'anonymous' || !$frm->{_err} && $self->dbUserGet(username => $frm->{usrname})->[0]{id};
    push @{$frm->{_err}}, 'Someone already registered with that email address'
      if !$frm->{_err} && $self->dbUserGet(mail => $frm->{mail})->[0]{id};

    # Use /32 match for IPv4 and /48 for IPv6. The /48 is fairly broad, so some
    # users may have to wait a bit before they can register...
    my $ip = $self->reqIP;
    push @{$frm->{_err}}, 'You can only register one account from the same IP within 24 hours'
      if !$frm->{_err} && $self->dbUserGet(ip => $ip =~ /:/ ? "$ip/48" : $ip, registered => time-24*3600)->[0]{id};

    if(!$frm->{_err}) {
      my($token, $pass) = $self->authPrepareReset();
      my $uid = $self->dbUserAdd($frm->{usrname}, $pass, $frm->{mail});
      my $body = sprintf "Hello %s,\n\n"
        ."Someone has registered an account on VNDB.org with your email address. To confirm your registration, follow the link below.\n\n"
        ."%s\n\n"
        ."If you don't remember creating an account on VNDB.org recently, please ignore this e-mail.\n\n"
        ."vndb.org",
        $frm->{usrname}, $self->reqBaseURI()."/u$uid/setpass?t=$token";
      $self->mail($body,
        To => $frm->{mail},
        From => 'VNDB <noreply@vndb.org>',
        Subject => "Confirm registration for $frm->{usrname}",
      );
      return $self->resRedirect('/u/register/done', 'post');
    }
  }

  $self->htmlHeader(title => 'Create an account', noindex => 1);

  my $type = $frm->{type} || floor(rand 3)+1;
  $self->htmlForm({ frm => $frm, action => '/u/register' }, register => [ 'Create an account',
    [ hidden => short => 'type', value => $type ],
    [ input  => short => 'usrname', name => 'Username' ],
    [ static => content => 'Preferred username. Must be lowercase and can only consist of alphanumeric characters.' ],
    [ input  => short => 'mail', name => 'Email' ],
    [ static => content => 'Your email address will only be used in case you lose your password.'
        .' We will never send spam or newsletters unless you explicitly ask us for it or we get hacked.<br /><br />' ],
    [ static => content => sprintf '<br /><br />How many %s do we have in the database? (Hint: look to your left)',
        ['visual novels', 'releases', 'producers']->[$type-1] ],
    [ input  => short => 'answer', name => 'Answer' ],
  ]);
  $self->htmlFooter;
}


sub register_done {
  my $self = shift;
  return $self->resRedirect('/') if $self->authInfo->{id};
  $self->htmlHeader(title => 'Account created', noindex => 1);
  div class => 'mainbox';
   h1 'Account created';
   div class => 'notice';
    p 'Your account has been created! In a few minutes, you should receive an email with instructions to set your password.';
   end;
  end;
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
        { post => 'usrname',   template => 'uname' },
        { post => 'perms',     required => 0, multi => 1, enum => [ keys %{$self->{permissions}} ] },
        { post => 'ign_votes', required => 0, default => 0 },
      ) : (),
      { post => 'mail',       template => 'email' },
      { post => 'curpass',    required => 0, minlength => 4, maxlength => 64, template => 'ascii', default => '' },
      { post => 'usrpass',    required => 0, minlength => 4, maxlength => 64, template => 'ascii' },
      { post => 'usrpass2',   required => 0, minlength => 4, maxlength => 64, template => 'ascii' },
      { post => 'hide_list',  required => 0, default => 0,  enum => [0,1] },
      { post => 'show_nsfw',  required => 0, default => 0,  enum => [0,1] },
      { post => 'traits_sexual', required => 0, default => 0,  enum => [0,1] },
      { post => 'tags_all',   required => 0, default => 0,  enum => [0,1] },
      { post => 'tags_cat',   required => 0, multi => 1, enum => [qw|cont ero tech|] },
      { post => 'spoilers',   required => 0, default => 0, enum => [0..2] },
      { post => 'skin',       required => 0, default => $self->{skin_default}, enum => [ keys %{$self->{skins}} ] },
      { post => 'customcss',  required => 0, maxlength => 2000, default => '' },
    );
    push @{$frm->{_err}}, 'Passwords do not match'
      if ($frm->{usrpass} || $frm->{usrpass2}) && (!$frm->{usrpass} || !$frm->{usrpass2} || $frm->{usrpass} ne $frm->{usrpass2});
    push @{$frm->{_err}}, 'Invalid password'
      if !($self->authInfo->{id} != $u->{id} && $self->authCan('usermod'))
          && ($frm->{usrpass} || $frm->{usrpass2}) && !$self->authCheck($u->{username}, $frm->{curpass});

    if(!$frm->{_err}) {
      $frm->{skin} = '' if $frm->{skin} eq $self->{skin_default};
      $self->dbUserPrefSet($uid, $_ => $frm->{$_}) for (qw|skin customcss show_nsfw traits_sexual tags_all hide_list spoilers|);

      my $tags_cat = join(',', sort @{$frm->{tags_cat}}) || 'none';
      $self->dbUserPrefSet($uid, tags_cat => $tags_cat eq $self->{default_tags_cat} ? '' : $tags_cat);
      my %o;
      if($self->authCan('usermod')) {
        $o{username} = $frm->{usrname} if $frm->{usrname};
        $o{perm} = 0;
        $o{perm} |= $self->{permissions}{$_} for(@{ delete $frm->{perms} });
      }
      $o{mail} = $frm->{mail};
      $o{passwd} = $self->authPreparePass($frm->{usrpass}) if $frm->{usrpass};
      $o{ign_votes} = $frm->{ign_votes} ? 1 : 0 if $self->authCan('usermod');
      $self->dbUserEdit($uid, %o);
      return $self->resRedirect("/u$uid/edit?d=1", 'post');
    }
  }

  # fill out default values
  $frm->{usrname} ||= $u->{username};
  $frm->{mail}    ||= $u->{mail};
  $frm->{perms}   ||= [ grep $u->{perm} & $self->{permissions}{$_}, keys %{$self->{permissions}} ];
  $frm->{$_} //= $u->{prefs}{$_} for(qw|skin customcss show_nsfw traits_sexual tags_all hide_list spoilers|);
  $frm->{tags_cat} ||= [ split /,/, $u->{prefs}{tags_cat}||$self->{default_tags_cat} ];
  $frm->{ign_votes} = $u->{ign_votes} if !defined $frm->{ign_votes};
  $frm->{skin}    ||= $self->{skin_default};
  $frm->{usrpass} = $frm->{usrpass2} = $frm->{curpass} = '';

  # create the page
  $self->htmlHeader(title => 'My account', noindex => 1);
  $self->htmlMainTabs('u', $u, 'edit');
  if($self->reqGet('d')) {
    div class => 'mainbox';
     h1 'Settings saved';
     div class => 'notice';
      p 'Settings successfully saved.';
     end;
    end
  }
  $self->htmlForm({ frm => $frm, action => "/u$uid/edit" }, useredit => [ 'My account',
    [ part   => title => 'General info' ],
    $self->authCan('usermod') ? (
      [ input  => short => 'usrname', name => 'Username' ],
      [ select => short => 'perms', name => 'Permissions', multi => 1, size => (scalar keys %{$self->{permissions}}), options => [
        map [ $_, $_ ], sort keys %{$self->{permissions}} ] ],
      [ check  => short => 'ign_votes', name => 'Ignore votes in VN statistics' ],
    ) : (
      [ static => label => 'Username', content => $frm->{usrname} ],
    ),
    [ input  => short => 'mail', name => 'Email' ],

    [ part   => title => 'Change password' ],
    [ static => content => 'Leave blank to keep your current password' ],
    [ passwd => short => 'curpass', name => 'Current Password' ],
    [ passwd => short => 'usrpass', name => 'New Password' ],
    [ passwd => short => 'usrpass2', name => 'Confirm password' ],

    [ part   => title => 'Options' ],
    [ check  => short => 'hide_list', name =>
       qq{Don't allow other people to see my visual novel list (<a href="/u$uid/list">/u$uid/list</a>),
          votes (<a href="/u$uid/votes">/u$uid/votes</a>) and wishlist (<a href="/u$uid/wish">/u$uid/wish</a>).} ],
    [ check  => short => 'show_nsfw', name => 'Disable warnings for images that are not safe for work.' ],
    [ check  => short => 'traits_sexual', name => 'Show sexual traits by default on character pages.' ],
    [ check  => short => 'tags_all', name => 'Show all tags by default on visual novel pages.' ],
    [ select => short => 'tags_cat', name => 'Tag categories', multi => 1, size => 3,
      options => [ map [ $_, $self->{tag_categories}{$_} ], keys %{$self->{tag_categories}} ] ],
    [ select => short => 'spoilers', name => 'Spoiler level', options => [
       [0, 'Hide spoilers'], [1, 'Show only minor spoilers'], [2, 'Show all spoilers']  ]],
    [ select => short => 'skin', name => 'Preferred skin', width => 300, options => [
      map [ $_, $self->{skins}{$_}[0].($self->debug?" [$_]":'') ], sort { $self->{skins}{$a}[0] cmp $self->{skins}{$b}[0] } keys %{$self->{skins}} ] ],
    [ textarea => short => 'customcss', name => 'Additional <a href="http://en.wikipedia.org/wiki/Cascading_Style_Sheets">CSS</a>' ],
  ]);
  $self->htmlFooter;
}


sub posts {
  my($self, $uid) = @_;

  # fetch user info (cached if uid == loggedin uid)
  my $u = $self->authInfo->{id} && $self->authInfo->{id} == $uid ? $self->authInfo : $self->dbUserGet(uid => $uid, what => 'hide_list')->[0];
  return $self->resNotFound if !$u->{id};

  my $f = $self->formValidate(
    { get => 'p', required => 0, default => 1, template => 'page' }
  );
  return $self->resNotFound if $f->{_err};

  my($posts, $np) = $self->dbPostGet(uid => $uid, hide => 1, what => 'thread', page => $f->{p}, sort => 'date', reverse => 1);

  my $title = "Posts made by $u->{username}";
  $self->htmlHeader(title => $title, noindex => 1);
  $self->htmlMainTabs(u => $u, 'posts');
  div class => 'mainbox';
   h1 $title;
   if(!@$posts) {
     p "$u->{username} hasn't made any posts yet.";
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
      [ 'Date' ],
      [ 'Title' ],
    ],
    row     => sub {
      my($s, $n, $l) = @_;
      Tr;
       td class => 'tc1'; a href => "/t$l->{tid}.$l->{num}", 't'.$l->{tid}; end;
       td class => 'tc2'; a href => "/t$l->{tid}.$l->{num}", '.'.$l->{num}; end;
       td class => 'tc3', fmtdate $l->{date};
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
    { get => 'p', required => 0, default => 1, template => 'page' },
    { get => 'q', required => 0, default => '', maxlength => 50 },
  );
  return $self->resNotFound if $f->{_err};

  $self->htmlHeader(noindex => 1, title => 'Browse users');

  div class => 'mainbox';
   h1 'Browse users';
   form action => '/u/all', 'accept-charset' => 'UTF-8', method => 'get';
    $self->htmlSearchBox('u', $f->{q});
   end;
   p class => 'browseopts';
    for ('all', 'a'..'z', 0) {
      a href => "/u/$_", $_ eq $char ? (class => 'optselected') : (), $_ eq 'all' ? 'ALL' : $_ ? uc $_ : '#';
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
      [ 'Username',   'username'   ],
      [ 'Registered', 'registered' ],
      [ 'Votes',      'votes'      ],
      [ 'Edits',      'changes'    ],
      [ 'Tags',       'tags'       ],
    ],
    row     => sub {
      my($s, $n, $l) = @_;
      Tr;
       td class => 'tc1';
        a href => '/u'.$l->{id}, $l->{username};
       end;
       td class => 'tc2', fmtdate $l->{registered};
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
    { get => 'p', required => 0, default => 1, template => 'page' },
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
      { post => 'notifysel', multi => 1, required => 0, template => 'id' },
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

  $self->htmlHeader(title => 'My notifications', noindex => 1);
  $self->htmlMainTabs(u => $u);
  div class => 'mainbox';
   h1 'My notifications';
   p class => 'browseopts';
    a !$f->{r} ? (class => 'optselected') : (), href => "/u$uid/notifies?r=0", 'Unread notifications';
    a  $f->{r} ? (class => 'optselected') : (), href => "/u$uid/notifies?r=1", 'All notifications';
   end;
   p 'No notifications!' if !@$list;
  end;

  my $code = $self->authGetCode("/u$uid/notifies");

  my %ntypes = (
    pm       => 'Private Message',
    dbdel    => 'Entry you contributed to has been deleted',
    listdel  => 'VN in your (wish)list has been deleted',
    dbedit   => 'Entry you contributed to has been edited',
    announce => 'Site announcement',
  );

  if(@$list) {
    form action => "/u$uid/notifies?r=$f->{r};formcode=$code", method => 'post', id => 'notifies';
    $self->htmlBrowse(
      items    => $list,
      options  => $f,
      nextpage => $np,
      class    => 'notifies',
      pageurl  => "/u$uid/notifies?r=$f->{r}",
      header   => [
        [ '' ],
        [ 'Type' ],
        [ 'Age' ],
        [ 'ID' ],
        [ 'Action' ],
      ],
      row     => sub {
        my($s, $n, $l) = @_;
        Tr $l->{read} ? () : (class => 'unread');
         td class => 'tc1';
          input type => 'checkbox', name => 'notifysel', value => "$l->{id}";
         end;
         td class => 'tc2', $ntypes{$l->{ntype}};
         td class => 'tc3', fmtage $l->{date};
         td class => 'tc4';
          a href => "/u$uid/notify/$l->{id}", "$l->{ltype}$l->{iid}".($l->{subid}?".$l->{subid}":'');
         end;
         td class => 'tc5 clickable', id => "notify_$l->{id}";
          lit sprintf
              $l->{ltype} ne 't' ? 'Edit of %s by %s' :
              $l->{subid} == 1   ? 'New thread %s by %s' : 'Reply to %s by %s',
            sprintf('<i>%s</i>', xml_escape $l->{c_title}),
            sprintf('<i>%s</i>', xml_escape $l->{username});
         end;
        end 'tr';
      },
      footer => sub {
        Tr;
         td colspan => 5;
          input type => 'checkbox', class => 'checkall', name => 'notifysel', value => 0;
          txt ' ';
          input type => 'submit', name => 'markread', value => 'mark selected read';
          input type => 'submit', name => 'remove', value => 'remove selected';
          b class => 'grayedout', ' (Read notifications are automatically removed after one month)';
         end;
        end;
      }
    );
    end;
  }

  form method => 'post', action => "/u$uid/notifies?formcode=$code";
  div class => 'mainbox';
   h1 'Settings';
   div class => 'notice', 'Settings successfully saved.' if $saved;
   p;
    for('nodbedit', 'announce') {
      my $def = $_ eq 'nodbedit' ? 0 : 1;
      input type => 'checkbox', name => "notify_$_", id => "notify_$_", value => $def,
        ($self->authPref("notify_$_")||0) == $def ? (checked => 'checked') : ();
      label for => "notify_$_", $_ eq 'nodbedit'
        ? ' Notify me about edits of database entries I contributed to.'
        : ' Notify me about site announcements.';
      br;
    }
    input type => 'submit', name => 'set', value => 'Save';
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

