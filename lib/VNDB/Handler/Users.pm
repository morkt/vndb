
package VNDB::Handler::Users;

use strict;
use warnings;
use YAWF ':html';


YAWF::register(
  qr{u([1-9]\d*)}       => \&userpage,
  qr{u/login}           => \&login,
  qr{u/logout}          => \&logout,
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


1;
