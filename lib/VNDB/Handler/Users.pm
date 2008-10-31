
package VNDB::Handler::Users;

use strict;
use warnings;
use YAWF ':html';


YAWF::register(
  qr{u([1-9]\d*)}       => \&userpage,
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


sub logout {
  shift->authLogout;
}


1;
