
package VNDB::Handler::Users;

use strict;
use warnings;
use YAWF ':html';
use Digest::MD5 'md5_hex';


YAWF::register(
  qr{u([1-9]\d*)}       => \&userpage,
  qr{u/login}           => \&login,
  qr{u/logout}          => \&logout,
  qr{u/newpass}         => \&newpass,
  qr{u/newpass/sent}    => \&newpass_sent,
  qr{u/register}        => \&register,
  qr{u([1-9]\d*)/edit}  => \&edit,
);


sub userpage {
  my($self, $uid) = @_;

  my $u = $self->dbUserGet(uid => $uid)->[0];
  return 404 if !$u->{id};

  $self->htmlHeader(title => ucfirst($u->{username})."'s Profile");
  $self->htmlMainTabs('u', $u);
  div class => 'mainbox';
   h1 ucfirst($u->{username})."'s Profile";
  end;
  $self->htmlFooter;
}


sub login {
  my $self = shift;

  return $self->resRedirect('/') if $self->authInfo->{id};

  my $frm;
  if($self->reqMethod eq 'POST') {
    $frm = $self->formValidate(
      { name => 'usrname', required => 1, minlength => 2, maxlength => 15, template => 'pname' },
      { name => 'usrpass', required => 1, minlength => 4, maxlength => 15, template => 'asciiprint' },
    );

    (my $ref = $self->reqHeader('Referer')||'/') =~ s/^\Q$self->{url}//;
    return if !$frm->{_err} && $self->authLogin($frm->{usrname}, $frm->{usrpass}, $ref);
    $frm->{_err} = [ 'login_failed' ] if !$frm->{_err};
  }

  $self->htmlHeader(title => 'Login');
  div class => 'mainbox';
   h1 'Login';
   $self->htmlForm({ frm => $frm, action => '/u/login' }, Login => [
    [ input  => name => 'Username', short => 'usrname' ],
    [ static => content => '<a href="/u/register">No account yet?</a>' ],
    [ passwd => name => 'Password', short => 'usrpass' ],
    [ static => content => '<a href="/u/newpass">Forgot your password?</a>' ],
   ]);
  end;
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
      $self->mail(
        sprintf(join('', <DATA>), $u->{username}, $pass),
        To => $u->{mail},
        From => 'VNDB <noreply@vndb.org>',
        Subject => 'New password for '.$u->{username}
      );
      return $self->resRedirect('/u/newpass/sent', 'post');
    }
  }

  $self->htmlHeader(title => 'Forgot Password');
  div class => 'mainbox';
   h1 'Forgot Password';
   p "Forgot your password and can't login to VNDB anymore?\n"
    ."Don't worry! Just give us the email address you used to register on VNDB,\n"
    ."and we'll send you a new password within a few minutes!";
   $self->htmlForm({ frm => $frm, action => '/u/newpass' }, 'Reset Password' => [
    [ input  => name => 'Email', short => 'mail' ],
   ]);
  end;
  $self->htmlFooter;
}


sub newpass_sent {
  my $self = shift;
  return $self->resRedirect('/') if $self->authInfo->{id};
  $self->htmlHeader(title => 'New Password');
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
      { name => 'usrpass',  minlength => 4, maxlength => 15, template => 'asciiprint' },
      { name => 'usrpass2', minlength => 4, maxlength => 15, template => 'asciiprint' },
    );
    push @{$frm->{_err}}, 'passmatch'  if $frm->{usrpass} ne $frm->{usrpass2};
    push @{$frm->{_err}}, 'usrexists'  if $frm->{usrname} eq 'anonymous' || !$frm->{_err} && $self->dbUserGet(username => $frm->{usrname})->[0]{id};
    push @{$frm->{_err}}, 'mailexists' if !$frm->{_err} && $self->dbUserGet(mail => $frm->{mail})->[0]{id};

    if(!$frm->{_err}) {
      $self->dbUserAdd($frm->{usrname}, md5_hex($frm->{usrpass}), $frm->{mail});
      return $self->authLogin($frm->{usrname}, $frm->{usrpass}, '/');
    }
  }

  $self->htmlHeader(title => 'Create an Account');
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

   $self->htmlForm({ frm => $frm, action => '/u/register' }, 'New Account' => [
     [ input  => short => 'usrname', name => 'Username' ],
     [ static => content => 'Requested username. Must be lowercase and can only consist of alphanumeric characters.' ],
     [ input  => short => 'mail', name => 'Email' ],
     [ static => content => 'Your email address will only be used in case you lose your password. We will never send'
        .' spam or newsletters unless you explicitly ask us for it.<br /><br />' ],
     [ passwd => short => 'usrpass', name => 'Password' ],
     [ passwd => short => 'usrpass2', name => 'Confirm pass.' ],
   ]);
  end;
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
      { name => 'usrpass',  required => 0, minlength => 4, maxlength => 15, template => 'asciiprint' },
      { name => 'usrpass2', required => 0, minlength => 4, maxlength => 15, template => 'asciiprint' },
      { name => 'flags_list', required => 0, default => 0 },
      { name => 'flags_nsfw', required => 0, default => 0 },
    );
    push @{$frm->{_err}}, 'passmatch' if ($frm->{usrpass} || $frm->{usrpass2}) && $frm->{usrpass} ne $frm->{usrpass2};
    if(!$frm->{_err}) {
      my %o;
      $o{username} = $frm->{usrname} if $frm->{usrname};
      $o{rank} = $frm->{rank} if $frm->{rank};
      $o{mail} = $frm->{mail};
      $o{passwd} = md5_hex($frm->{usrpass}) if $frm->{usrpass};
      $o{flags} = $frm->{flags_list} ? $self->{user_flags}{list} : 0;
      $o{flags} += $self->{user_flags}{nsfw} if $frm->{flags_nsfw};
      $self->dbUserEdit($uid, %o);
      return $self->resRedirect("/u$uid/edit?d=1", 'post') if $uid != $self->authInfo->{id} || !$frm->{usrpass};
      return $self->authLogin($frm->{usrname}||$u->{username}, $frm->{usrpass}, "/u$uid/edit?d=1");
    }
  }

  # fill out default values
  $frm->{usrname}    ||= $u->{username};
  $frm->{rank}       ||= $u->{rank};
  $frm->{mail}       ||= $u->{mail};
  $frm->{flags_list} = $u->{flags} & $self->{user_flags}{list} if !defined $frm->{flags_list};
  $frm->{flags_nsfw} = $u->{flags} & $self->{user_flags}{nsfw} if !defined $frm->{flags_nsfw};

  # create the page
  my $title = $self->authInfo->{id} != $uid ? "Edit $u->{username}'s Account" : 'My Account';
  $self->htmlHeader(title => $title);
  $self->htmlMainTabs('u', $u, 'edit');
  div class => 'mainbox';
   h1 $title;
   if($self->reqParam('d')) {
     div class => 'notice';
      p 'Settings successfully saved.';
     end;
   }
   $self->htmlForm({ frm => $frm, action => "/u$uid/edit" }, 'Edit Account' => [
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
     [ input  => short => 'usrpass', name => 'Password' ],
     [ passwd => short => 'usrpass2', name => 'Confirm pass.' ],

     [ part   => title => 'Options' ],
     [ check  => short => 'flags_list', name =>
        qq|Allow other people to see my visual novel list (<a href="/u$uid/list">/u$uid/list</a>) |.
        qq|and wishlist (<a href="/u$uid/wish">/u$uid/wish</a>)| ],
     [ check  => short => 'flags_nsfw', name => 'Disable warnings for images that are not safe for work.' ],
   ]);
  end;
  $self->htmlFooter;
}


1;


# Contents of the password-reset email
__DATA__
Hello %s,

Your password has been reset, you can now login at http://vndb.org/ with the
following information:

Username: %1$s
Password: %s

Now don't forget your password again! :-)

vndb.org
