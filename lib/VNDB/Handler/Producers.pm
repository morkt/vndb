
package VNDB::Handler::Producers;

use strict;
use warnings;
use YAWF ':html';


YAWF::register(
  qr{p([1-9]\d*)}        => \&page,
);


sub page {
  my($self, $pid) = @_;

  my $p = $self->dbProducerGet(id => $pid)->[0];
  return 404 if !$p->{id};

  $self->htmlHeader(title => $p->{name});
  $self->htmlMainTabs(p => $p);
  div class => 'mainbox';
   h1 $p->{name};
   h2 class => 'alttitle', $p->{original} if $p->{original};
  end;
  $self->htmlFooter;
}


1;
