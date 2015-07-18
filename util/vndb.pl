#!/usr/bin/perl


package VNDB;

use strict;
use warnings;


use Cwd 'abs_path';
our $ROOT;
BEGIN { ($ROOT = abs_path $0) =~ s{/util/vndb\.pl$}{}; }


use lib $ROOT.'/lib';


use TUWF ':html';
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


$TUWF::OBJ->{$_} = $S{$_} for (keys %S);
TUWF::set(
  %O,
  pre_request_handler => \&reqinit,
  error_404_handler => \&handle404,
  log_format => \&logformat,
  # for compatibility with YAWF
  validate_templates => {
    mail       => { regex => qr/^[^@<>\s\(\),]+@[^@.<>\s\(\),]+(?:\.[^@.<>\s\(\),]+)+$/ },
    url        => { regex => qr/^(http|https):\/\/[\w\-_]+(\.[\w\-_]+)+([\w\-\.,@?^=%&:\/~\+\*#]*[\w\-\@?^=%&\/~\+#\*])?$/ },
    asciiprint => { regex => qr/^[\x20-\x7E]*$/ },
    int        => { regex => qr/^-?[0-9]+$/ },
    pname      => { regex => qr/^[a-z0-9-]*$/ },
  },
);
TUWF::load_recursive('VNDB::Util', 'VNDB::DB', 'VNDB::Handler');
TUWF::run();


sub reqinit {
  my $self = shift;

  # check authentication cookies
  $self->authInit;

  # Determine language
  my $cookie = $self->reqCookie('l10n');
  $cookie = '' if !$cookie || !grep $_ eq $cookie, VNDB::L10N::languages;
  my $handle = VNDB::L10N->get_handle(); # falls back to English
  my $browser = $handle->language_tag();
  my $rmcookie = 0;

  # when logged in, the setting is kept in the DB even if it's the same as what
  # the browser requests. This is to ensure a user gets the same language even
  # when switching PCs
  if($self->authInfo->{id}) {
    my $db = $self->authPref('l10n');
    if($db && !grep $_ eq $db, VNDB::L10N::languages) {
      $self->authPref(l10n => undef);
      $db = '';
    }
    $rmcookie = 1 if $cookie;
    if(!$db && $cookie && $cookie ne $browser) {
      $self->authPref(l10n => $cookie);
      $db = $cookie;
    }
    $handle = VNDB::L10N->get_handle($db) if $db && $db ne $browser;
  }

  else {
    $rmcookie = 1 if $cookie && $cookie eq $browser;
    $handle = VNDB::L10N->get_handle($cookie) if $cookie && $browser ne $cookie;
  }
  $self->resCookie(l10n => undef) if $rmcookie;
  $self->{l10n} = $handle;

  # load some stats (used for about all pageviews, anyway)
  $self->{stats} = $self->dbStats;

  return 1;
}


sub handle404 {
  my $self = shift;
  $self->resStatus(404);
  $self->htmlHeader(title => 'Page Not Found');
  div class => 'mainbox';
   h1 'Page not found';
   div class => 'warning';
    h2 'Oops!';
    p;
     txt 'It seems the page you were looking for does not exist,';
     br;
     txt 'you may want to try using the menu on your left to find what you are looking for.';
    end;
   end;
  end;
  $self->htmlFooter;
}


# log user IDs (necessary for determining performance issues, user preferences
# have a lot of influence in this)
sub logformat {
  my($self, $uri, $msg) = @_;
  sprintf "[%s] %s %s: %s\n", scalar localtime(), $uri,
    $self->authInfo->{id} ? 'u'.$self->authInfo->{id} : '-', $msg;
}

