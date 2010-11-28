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
use VNDB::L10N;
use SkinFile;


our(%O, %S);


# load the skins
# NOTE: $S{skins} can be modified in data/config.pl, allowing deletion of skins or forcing only one skin
my $skin = SkinFile->new("$ROOT/static/s");
$S{skins} = { map +($_ => [ $skin->get($_, 'name'), $skin->get($_, 'userid') ]), $skin->list };


# load lang.dat
VNDB::L10N::loadfile();


# load settings from global.pl
require $ROOT.'/data/global.pl';


# automatically regenerate the skins and script.js and whatever else should be done
system "make -sC $ROOT" if $S{regen_static};


YAWF::init(
  %O,
  namespace => 'VNDB',
  object_data => \%S,
  pre_request_handler => \&reqinit,
  error_404_handler => \&handle404,
);


sub reqinit {
  my $self = shift;

  # Determine language
  # if the cookie is set, use that. Otherwise, interpret the Accept-Language header or fall back to English.
  # if the cookie is set and is the same as either the Accept-Language header or the fallback, remove it
  my $conf = $self->reqCookie('l10n');
  $conf = '' if !$conf || !grep $_ eq $conf, VNDB::L10N::languages;

  $self->{l10n} = VNDB::L10N->get_handle(); # this uses I18N::LangTags::Detect
  $self->resHeader('Set-Cookie', "l10n= ; expires=Sat, 01-Jan-2000 00:00:00 GMT; path=/; domain=$self->{cookie_domain}")
    if $conf && $self->{l10n}->language_tag() eq $conf;
  $self->{l10n} = VNDB::L10N->get_handle($conf) if $conf && $self->{l10n}->language_tag() ne $conf;


  # check authentication cookies
  $self->authInit;

  # check for IE6
  if($self->reqHeader('User-Agent') && $self->reqHeader('User-Agent') =~ /MSIE [67]/
    && !$self->reqCookie('ie-sucks') && $self->reqPath ne 'we-dont-like-ie') {
    # act as if we're opening /we-dont-like-ie6 (ugly hack, until YAWF supports preventing URL handlers from firing)
    $ENV{HTTP_REFERER} = $ENV{REQUEST_URI};
    $ENV{REQUEST_URI} = '/we-dont-like-ie';
  }

  # load some stats (used for about all pageviews, anyway)
  $self->{stats} = $self->dbStats;
}


sub handle404 {
  my $self = shift;
  $self->resStatus(404);
  $self->htmlHeader(title => 'Page Not Found');
  div class => 'mainbox';
   h1 'Page not found';
   div class => 'warning';
    h2 'Oops!';
    p "It seems the page you were looking for does not exist,\n".
      "you may want to try using the menu on your left to find what you are looking for.";
   end;
  end;
  $self->htmlFooter;
}

