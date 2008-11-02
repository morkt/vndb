
package VNDB::Handler::Misc;


use strict;
use warnings;
use YAWF ':html';


YAWF::register(
  qr{},         \&homepage,
  qr{nospam},   \&nospam,
);


sub homepage {
  my $self = shift;
  $self->htmlHeader(title => 'The Visual Novel Database');

  div class => 'mainbox';
   h1 'The Visual Novel Database';
  end;

  $self->htmlFooter;
}


sub nospam {
  my $self = shift;
  $self->htmlHeader(title => 'Could not send form');

  div class => 'mainbox';
   h1 'Could not send form';
   div class => 'warning';
    h2 'Error';
    p 'The form could not be sent, please make sure you have Javascript enabled in your browser.';
   end;
  end;

  $self->htmlFooter;
}


1;

