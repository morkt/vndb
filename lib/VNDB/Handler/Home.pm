
package VNDB::Handler::Home;


use strict;
use warnings;
use YAWF ':html';


YAWF::register(
  qr{^$},       \&homepage,
);


sub homepage {
  my $self = shift;
  $self->htmlHeader(title => 'The Visual Novel Database');

  div class => 'mainbox';
   h1 'The Visual Novel Database';
  end;

  $self->htmlFooter;
}

1;

