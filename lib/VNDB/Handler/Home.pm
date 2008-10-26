
package VNDB::Handler::Home;


use strict;
use warnings;
use YAWF ':html';


YAWF::register(
  qr{^$},       \&homepage,
);


sub homepage {
  my $self = shift;

  lit 'Output';
}

1;

