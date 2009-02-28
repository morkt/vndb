
package VNDB::Handler::Users;

use strict;
use warnings;
use YAWF ':html';
use Digest::MD5 'md5_hex';
use VNDB::Func;


YAWF::register(
  qr{u([1-9]\d*)}             => \&userpage,
  qr{u/login}                 => \&login,
  qr{u/logout}                => \&logout,
  qr{u/newpass}               => \&newpass,
  qr{u/newpass/sent}          => \&newpass_sent,
  qr{u/register}              => \&register,
  qr{u([1-9]\d*)/edit}        => \&edit,
  qr{u([1-9]\d*)/del(/[od])?} => \&delete,
  qr{u/(all|[0a-z])}          => \&list,
);


sub userpage {
  my($self, $uid) = @_;

  my $u = $self->dbUserGet(uid => $uid, what => 'stats')->[0];
  return 404 if !$u->{id};

  my $votes = $u->{c_votes} && $self->dbVoteStats(uid => $uid);

  $self->htmlHeader(title => ucfirst($u->{username})."'s profile");
  $self->htmlMainTabs('u', $u);
  div class => 'mainbox userpage';
   h1 ucfirst($u->{username})."'s profile";

   table;
    Tr;
     td class => 'key', ' ';
     td ' ';
    end;
    my $i = 0;

    Tr ++$i % 2 ? (class => 'odd') : ();
     td 'Username';
     td;
      txt ucfirst($u->{username}).' (';
      a href => "/u$uid", "u$uid";
      txt ')';
     end;
    end;

    Tr ++$i % 2 ? (class => 'odd') : ();
     td 'Registered';
     td date $u->{registered};
    end;

    Tr ++$i % 2 ? (class => 'odd') : ();
     td 'Edits';
     td;
      if($u->{c_changes}) {
        a href => "/u$uid/hist", $u->{c_changes};
      } else {
        txt '-';
      }
     end;
    end;

    Tr ++$i % 2 ? (class => 'odd') : ();
     td 'Votes';
     td;
      if(!$u->{show_list}) {
        txt 'hidden';
      } elsif($votes) {
        my($total, $count) = (0, 0);
        for (1..@$votes) {
          $total += $_*$votes->[$_-1];
          $count += $votes->[$_-1];
        }
        a href => "/u$uid/list?v=1", $count;
        txt sprintf ' (%.2f average)', $total/$count;
      } else {
        txt '-';
      }
     end;
    end;

    Tr ++$i % 2 ? (class => 'odd') : ();
     td 'List stats';
     td !$u->{show_list} ? 'hidden' :
       sprintf '%d release%s of %d visual novel%s',
         $u->{releasecount}, $u->{releasecount} != 1 ? 's' : '',
         $u->{vncount}, $u->{vncount} != 1 ? 's' : '';
    end;

    Tr ++$i % 2 ? (class => 'odd') : ();
     td 'Forum stats';
     td sprintf '%d post%s, %d new thread%s',
       $u->{postcount}, $u->{postcount} != 1 ? 's' : '',
       $u->{threadcount}, $u->{threadcount} != 1 ? 's' : '';
    end;
   end;
  end;

  if($u->{show_list} && $votes) {
    div class => 'mainbox';
     h1 'Vote statistics';
     $self->htmlVoteStats(u => $u, $votes);
    end;
  }

  if($u->{c_changes}) {
    my $list = $self->dbRevisionGet(what => 'item user', uid => $uid, results => 5, hidden => 1);
    h1 class => 'boxtitle';
     a href => "/u$uid/hist", 'Recent changes';
    end;
    $self->htmlHistory($list, { p => 1 }, 0, "/u$uid/hist");
  }
  $self->htmlFooter;
}


sub login {
  my $self = shift;

  return $self->resRedirect('/') if $self->authInfo->{id};

  my $frm;
  if($self->reqMethod eq 'POST') {
    $frm = $self->formValidate(
      { name => 'usrname', required => 1, minlength => 2, maxlength => 15, template => 'pname' },
      { name => 'usrpass', required => 1, minlength => 4, maxlength => 64, template => 'asciiprint' },
    );

    (my $ref = $self->reqHeader('Referer')||'/') =~ s/^\Q$self->{url}//;
    $ref = '/' if $ref =~ /^\/u\//;
    return if !$frm->{_err} && $self->authLogin($frm->{usrname}, $frm->{usrpass}, $ref);
    $frm->{_err} = [ 'login_failed' ] if !$frm->{_err};
  }

  $self->htmlHeader(title => 'Login', noindex => 1);
  $self->htmlForm({ frm => $frm, action => '/u/login' }, Login => [
    [ input  => name => 'Username', short => 'usrname' ],
    [ static => content => '<a href="/u/register">No account yet?</a>' ],
    [ passwd => name => 'Password', short => 'usrpass' ],
    [ static => content => '<a href="/u/newpass">Forgot your password?</a>' ],
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
      $self->dbUserEdit($u->{id}, passwd => md5_hex($pass));
      my $body = <<'__';
Hello %s,

Your password has been reset, you can now login at http://vndb.org/ with the
following information:

Username: %1$s
Password: %s

Now don't forget your password again! :-)

vndb.org
__
      $self->mail(
        sprintf($body, $u->{username}, $pass),
        To => $u->{mail},
        From => 'VNDB <noreply@vndb.org>',
        Subject => 'New password for '.$u->{username}
      );
      return $self->resRedirect('/u/newpass/sent', 'post');
    }
  }

  $self->htmlHeader(title => 'Forgot Password', noindex => 1);
  div class => 'mainbox';
   h1 'Forgot Password';
   p "Forgot your password and can't login to VNDB anymore?\n"
    ."Don't worry! Just give us the email address you used to register on VNDB,\n"
    ."and we'll send you a new password within a few minutes!";
  end;
  $self->htmlForm({ frm => $frm, action => '/u/newpass' }, 'Reset Password' => [
    [ input  => name => 'Email', short => 'mail' ],
  ]);
  $self->htmlFooter;
}


sub newpass_sent {
  my $self = shift;
  return $self->resRedirect('/') if $self->authInfo->{id};
  $self->htmlHeader(title => 'New Password', noindex => 1);
  div class => 'mainbox';
   h1 'New Password';
   div class => 'notice';
    h2 'Password Reset';
    p;
     txt "Your password has been reset and your new password should reach your mailbox in a few minutes.\n"
        ."You can always change your password again after logging in.\n\n";
     lit '<a href="/u/login">Login</a> - <a href="/">Home</a>';
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
      $self->dbUserAdd($frm->{usrname}, md5_hex($frm->{usrpass}), $frm->{mail});
      return $self->authLogin($frm->{usrname}, $frm->{usrpass}, '/');
    }
  }

  $self->htmlHeader(title => 'Create an Account', noindex => 1);
  div class => 'mainbox';
   h1 'Create an Account';
   h2 'Why should I register?';
   p 'Creating an account is completely painless, the only thing we need to know is your prefered username '
    .'and a password. You can just use any email address that isn\'t yours, as we don\'t even confirm '
    .'that the address you gave us is really yours. Keep in mind, however, that you would probably '
    .'want to remember your password if you do choose to give us an invalid email address...';

   p 'Anyway, having an account here has a few advantages over being just a regular visitor:';
   ul;
    li 'You can contribute to the database by editing any entries and adding new ones';
    li 'Keep track of all visual novels and releases you have, you\'d like to play, are playing, or have finished playing';
    li 'Vote on the visual novels you liked or disliked';
    li 'Contribute to the discussions on the boards';
    li 'And boast about the fact that you have an account on the best visual novel database in the world!';
   end;
  end;

  $self->htmlForm({ frm => $frm, action => '/u/register' }, 'New Account' => [
    [ input  => short => 'usrname', name => 'Username' ],
    [ static => content => 'Requested username. Must be lowercase and can only consist of alphanumeric characters.' ],
    [ input  => short => 'mail', name => 'Email' ],
    [ static => content => 'Your email address will only be used in case you lose your password. We will never send'
        .' spam or newsletters unless you explicitly ask us for it.<br /><br />' ],
    [ passwd => short => 'usrpass', name => 'Password' ],
    [ passwd => short => 'usrpass2', name => 'Confirm pass.' ],
  ]);
  $self->htmlFooter;
}


sub edit {
  my($self, $uid) = @_;

  # are we allowed to edit this user?
  return $self->htmlDenied if !$self->authInfo->{id} || $self->authInfo->{id} != $uid && !$self->authCan('usermod');

  # fetch user info (cached if uid == loggedin uid)
  my $u = $self->authInfo->{id} == $uid ? $self->authInfo : $self->dbUserGet(uid => $uid)->[0];
  return 404 if !$u->{id};

  # check POST data
  my $frm;
  if($self->reqMethod eq 'POST') {
    $frm = $self->formValidate(
      $self->authCan('usermod') ? (
        { name => 'usrname', template => 'pname', minlength => 2, maxlength => 15 },
        { name => 'rank', enum => [ 1..$#{$self->{user_ranks}} ] },
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
      $o{passwd} = md5_hex($frm->{usrpass}) if $frm->{usrpass};
      $o{show_list} = $frm->{flags_list} ? 1 : 0;
      $o{show_nsfw} = $frm->{flags_nsfw} ? 1 : 0;
      $self->dbUserEdit($uid, %o);
      return $self->resRedirect("/u$uid/edit?d=1", 'post') if $uid != $self->authInfo->{id} || !$frm->{usrpass};
      return $self->authLogin($frm->{usrname}||$u->{username}, $frm->{usrpass}, "/u$uid/edit?d=1");
    }
  }

  # fill out default values
  $frm->{usrname}    ||= $u->{username};
  $frm->{$_} ||= $u->{$_} for(qw|rank mail skin customcss|);
  $frm->{flags_list} = $u->{show_list} if !defined $frm->{flags_list};
  $frm->{flags_nsfw} = $u->{show_nsfw} if !defined $frm->{flags_nsfw};

  # create the page
  my $title = $self->authInfo->{id} != $uid ? "Edit $u->{username}'s Account" : 'My Account';
  $self->htmlHeader(title => $title, noindex => 1);
  $self->htmlMainTabs('u', $u, 'edit');
  if($self->reqParam('d')) {
    div class => 'mainbox';
     h1 'Settings saved';
     div class => 'notice';
      p 'Settings successfully saved.';
     end;
    end
  }
  $self->htmlForm({ frm => $frm, action => "/u$uid/edit" }, $title => [
    [ part   => title => 'General Info' ],
    $self->authCan('usermod') ? (
      [ input  => short => 'usrname', name => 'Username' ],
      [ select => short => 'rank', name => 'Rank', options => [
        map [ $_, $self->{user_ranks}[$_][0] ], 1..$#{$self->{user_ranks}} ] ],
    ) : (
      [ static => label => 'Username', content => $frm->{usrname} ],
    ),
    [ input  => short => 'mail', name => 'Email' ],

    [ part   => title => 'Change Password' ],
    [ static => content => 'Leave blank to keep your current password' ],
    [ passwd => short => 'usrpass', name => 'Password' ],
    [ passwd => short => 'usrpass2', name => 'Confirm pass.' ],

    [ part   => title => 'Options' ],
    [ check  => short => 'flags_list', name =>
        qq|Allow other people to see my visual novel list (<a href="/u$uid/list">/u$uid/list</a>) |.
        qq|and wishlist (<a href="/u$uid/wish">/u$uid/wish</a>)| ],
    [ check  => short => 'flags_nsfw', name => 'Disable warnings for images that are not safe for work.' ],
    [ select => short => 'skin', name => 'Prefered skin', width => 300, options => [
      map [ $_ eq $self->{skin_default} ? '' : $_, $self->{skins}{$_}.($self->debug?" [$_]":'') ], sort { $self->{skins}{$a} cmp $self->{skins}{$b} } keys %{$self->{skins}} ] ],
    [ textarea => short => 'customcss', name => 'Additional <a href="http://en.wikipedia.org/wiki/Cascading_Style_Sheets">CSS</a>' ],
  ]);
  $self->htmlFooter;
}


sub delete {
  my($self, $uid, $act) = @_;
  return $self->htmlDenied if !$self->authCan('usermod');

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
    { name => 's', required => 0, default => 'username', enum => [ qw|username registered votes changes| ] },
    { name => 'o', required => 0, default => 'a', enum => [ 'a','d' ] },
    { name => 'p', required => 0, default => 1, template => 'int' },
  );
  return 404 if $f->{_err};

  $self->htmlHeader(title => 'Browse users');

  div class => 'mainbox';
   h1 'Browse users';
   p class => 'browseopts';
    for ('all', 'a'..'z', 0) {
      a href => "/u/$_", $_ eq $char ? (class => 'optselected') : (), $_ ? uc $_ : '#';
    }
   end;
  end;

  my($list, $np) = $self->dbUserGet(
    order => ($f->{s} eq 'changes' ? 'c_' : $f->{s} eq 'votes' ? 'NOT show_list, c_' : '').$f->{s}.($f->{o} eq 'a' ? ' ASC' : ' DESC'),
    $char ne 'all' ? (
      firstchar => $char ) : (),
    results => 50,
    page => $f->{p},
  );

  $self->htmlBrowse(
    items    => $list,
    options  => $f,
    nextpage => $np,
    pageurl  => "/u/$char?o=$f->{o};s=$f->{s}",
    sorturl  => "/u/$char",
    header   => [
      [ 'Username',   'username'   ],
      [ 'Registered', 'registered' ],
      [ 'Votes',      'votes'      ],
      [ 'Edits',      'changes'    ],
    ],
    row     => sub {
      my($s, $n, $l) = @_;
      Tr $n % 2 ? (class => 'odd') : ();
       td class => 'tc1';
        a href => '/u'.$l->{id}, $l->{username};
       end;
       td class => 'tc2', date $l->{registered};
       td class => 'tc3';
        lit !$l->{show_list} ? '-' : !$l->{c_votes} ? 0 :
          qq|<a href="/u$l->{id}/list">$l->{c_votes}</a>|;
       end;
       td class => 'tc4';
        lit !$l->{c_changes} ? 0 : qq|<a href="/u$l->{id}/hist">$l->{c_changes}</a>|;
       end;
      end;
    },
  );
  $self->htmlFooter;
}


1;

