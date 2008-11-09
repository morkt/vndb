#!/usr/bin/perl


package VNDB;

use strict;
use warnings;


use Cwd 'abs_path';
our $ROOT;
BEGIN { ($ROOT = abs_path $0) =~ s{/util/vndb\.pl$}{}; }


use lib $ROOT.'/yawf/lib';
use lib $ROOT.'/lib';


use YAWF ':html';


our(%O, %S);


# load settings from global.pl
require $ROOT.'/data/global.pl';


YAWF::init(
  %O,
  namespace => 'VNDB',
  object_data => \%S,
  pre_request_handler => \&reqinit,
  error_404_handler => \&handle404,
);


sub reqinit {
  my $self = shift;
  $self->authInit;
}


sub handle404 {
  my $self = shift;
  $self->htmlHeader;
  div class => 'mainbox';
   h1 'Page not found';
   div class => 'warning';
    h2 'Oops!';
    p "It seems the page you were looking for does not exists,\n".
      "you may want to try using the menu on your left to find what you are looking for.";
   end;
  end;
  $self->htmlFooter;
}

