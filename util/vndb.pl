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


# load and (if required) regenerate the skins
# NOTE: $S{skins} can be modified in data/config.pl, allowing deletion of skins or forcing only one skin
$S{skins} = readskins();


# load settings from global.pl
require $ROOT.'/data/global.pl';


YAWF::init(
  %O,
  namespace => 'VNDB',
  object_data => \%S,
  pre_request_handler => \&reqinit,
  post_request_handler => \&reqdone,
  error_404_handler => \&handle404,
);


sub reqinit {
  my $self = shift;
  $self->authInit;

  # check for IE6
  if($self->reqHeader('User-Agent') && $self->reqHeader('User-Agent') =~ /MSIE 6/
    && !$self->reqCookie('ie-sucks') && $self->reqPath ne 'we-dont-like-ie6') {
    # act as if we're opening /we-dont-like-ie6 (ugly hack, until YAWF supports preventing URL handlers from firing)
    $ENV{HTTP_REFERER} = $ENV{REQUEST_URI};
    $ENV{REQUEST_URI} = '/we-dont-like-ie6';
  }
}


sub reqdone {
  my $self = shift;
  $self->dbCommit;
  $self->multiCmd;
}


sub handle404 {
  my $self = shift;
  $self->resStatus(404);
  $self->htmlHeader(title => 'Page Not Found');
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


sub readskins {
  my %skins; # dirname => skin name
  my $regen = 0;
  my $lasttemplate = [stat "$ROOT/data/skingen/style.css"]->[9];
  for my $f (glob "$ROOT/static/s/*") {
    my $n = $1 if $f =~ m{([^/]+)$};
    open my $F, '<', "$f/conf" or die $!;
    while(<$F>) {
      chomp;
      s{[\t\s]*//.*$}{};
      next if !/^name[\t\s]+(.+)$/;
      $skins{$n} = $1;
      last;
    }
    close $F;

    my $lastgen = [stat "$f/style.css"]->[9];
    $regen = 1 if (!-f "$f/style.css" && -x $f)
      || ([stat "$f/conf"]->[9] > $lastgen || $lasttemplate > $lastgen) && -w "$f/style.css";
  }
  # note: this only works if the current process has write access to the skins
  `$ROOT/util/skingen.pl` if $regen;
  return \%skins;
}

