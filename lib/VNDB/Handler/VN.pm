
package VNDB::Handler::VN;

use strict;
use warnings;
use YAWF ':html';


YAWF::register(
  qr{v([1-9]\d*)}       => \&page,
);


sub page {
  my($self, $vid) = @_;

  my $v = $self->dbVNGet(id => $vid)->[0];
  return 404 if !$v->{id};

  $self->htmlHeader(title => $v->{title});
  $self->htmlMainTabs('v', $v);
  div class => 'mainbox';
   h1 $v->{title};
   h2 class => 'alttitle', $v->{original} if $v->{original};
  end;
  $self->htmlFooter;
}


1;

