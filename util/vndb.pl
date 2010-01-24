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


# load and (if required) regenerate the skins
# NOTE: $S{skins} can be modified in data/config.pl, allowing deletion of skins or forcing only one skin
$S{skins} = readskins();


# automatically regenerate script.js when required and possible
checkjs();


# load lang.dat
VNDB::L10N::loadfile();


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

  # Determine language
  # if the cookie or parameter "l10n" is set, use that.
  #   otherwise, interpret the Accept-Language header or fall back to English
  # if the cookie is set and is the same as either the Accept-Language header or the fallback, remove it
  my $conf = $self->reqParam('l10n') || $self->reqCookie('l10n');
  $conf = '' if !$conf || !grep $_ eq $conf, VNDB::L10N::languages;

  $self->{l10n} = VNDB::L10N->get_handle(); # this uses I18N::LangTags::Detect
  if($self->{l10n}->language_tag() eq $conf && $self->reqCookie('l10n')) {
    $self->resHeader('Set-Cookie', "l10n= ; expires=Sat, 01-Jan-2000 00:00:00 GMT; path=/; domain=$self->{cookie_domain}");
  } elsif($self->reqParam('l10n') && $conf && $conf ne ($self->reqCookie('l10n')||'') && $self->{l10n}->language_tag() ne $conf) {
    $self->resHeader('Set-Cookie', "l10n=$conf; expires=Sat, 01-Jan-2030 00:00:00 GMT; path=/; domain=$self->{cookie_domain}");
  }
  $self->{l10n} = VNDB::L10N->get_handle($conf) if $conf && $self->{l10n}->language_tag() ne $conf;


  # check authentication cookies
  $self->authInit;

  # check for IE6
  if($self->reqHeader('User-Agent') && $self->reqHeader('User-Agent') =~ /MSIE 6/
    && !$self->reqCookie('ie-sucks') && $self->reqPath ne 'we-dont-like-ie6') {
    # act as if we're opening /we-dont-like-ie6 (ugly hack, until YAWF supports preventing URL handlers from firing)
    $ENV{HTTP_REFERER} = $ENV{REQUEST_URI};
    $ENV{REQUEST_URI} = '/we-dont-like-ie6';
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


sub readskins {
  my %skins; # dirname => skin name
  my @regen;
  my $lasttemplate = [stat "$ROOT/data/style.css"]->[9];
  my $skin = SkinFile->new("$ROOT/static/s");
  for my $n ($skin->list) {
    $skins{$n} = [ $skin->get($n, 'name'), $skin->get($n, 'userid') ];
    next if !$skins{$n}[0];

    my $f = "$ROOT/static/s/$n";
    my $css = -f "$f/style.css" && [stat "$f/style.css"]->[9] || 0;
    my $boxbg = -f "$f/boxbg.png" && [stat "$f/boxbg.png"]->[9] || 0;
    my $lastgen = $css < $boxbg ? $css : $boxbg;
    push @regen, $n if (!$lastgen && -x $f && (!$css && !$boxbg || $css && -w "$f/style.css" || $boxbg && -w "$f/boxbg.png"))
      || ([stat "$f/conf"]->[9] > $lastgen || $lasttemplate > $lastgen) && -w "$f/style.css" && -w "$f/boxbg.png";
  }
  system "$ROOT/util/skingen.pl", @regen if @regen;
  return \%skins;
}


sub checkjs {
  my $script = "$ROOT/static/f/script.js";
  my $lastmod = [stat $script]->[9];
  system "$ROOT/util/jsgen.pl" if
       (!-e $script && -x "$ROOT/static/f")
    || (-e $script && -w $script && (
           $lastmod < [stat "$ROOT/data/script.js"]->[9]
        || $lastmod < [stat "$ROOT/data/lang.txt"]->[9]
        || (-e "$ROOT/data/config.pl" && $lastmod < [stat "$ROOT/data/config.pl"]->[9])
        || $lastmod < [stat "$ROOT/data/global.pl"]->[9]
        || $lastmod < [stat "$ROOT/util/jsgen.pl"]->[9]
       ));
}

