
#
#  Multi::Anime  -  Fetches anime info from AniDB
#

package Multi::Anime;

use strict;
use warnings;
use Multi::Core;
use AnyEvent::Socket;
use AnyEvent::Util;


sub LOGIN_ACCEPTED         () { 200 }
sub LOGIN_ACCEPTED_NEW_VER () { 201 }
sub ANIME                  () { 230 }
sub NO_SUCH_ANIME          () { 330 }
sub NOT_LOGGED_IN          () { 403 }
sub LOGIN_FIRST            () { 501 }
sub CLIENT_BANNED          () { 504 }
sub INVALID_SESSION        () { 506 }
sub BANNED                 () { 555 }
sub ANIDB_OUT_OF_SERVICE   () { 601 }
sub SERVER_BUSY            () { 602 }

my @handled_codes = (
  LOGIN_ACCEPTED, LOGIN_ACCEPTED_NEW_VER, ANIME, NO_SUCH_ANIME, NOT_LOGGED_IN,
  LOGIN_FIRST,CLIENT_BANNED, INVALID_SESSION, BANNED, ANIDB_OUT_OF_SERVICE, SERVER_BUSY
);


my %O = (
  apihost => 'api.anidb.net',
  apiport => 9000,
  # AniDB UDP API options
  client => 'multi',
  clientver => 1,
  # Misc settings
  msgdelay => 10,
  timeout => 30,
  timeoutdelay => 0.4, # $delay = $msgdelay ** (1 + $tm*$timeoutdelay)
  maxtimeoutdelay => 2*3600,
  check_delay => 3600,
  cachetime => '3 months',
);


my %C = (
  sock => undef,
  tw => undef,# timer guard
  s => '',    # session key, '' = not logged in
  tm => 0,    # number of repeated timeouts
  lm => 0,    # timestamp of last outgoing message
  aid => 0,   # anime ID of the last sent ANIME command
  tag => int(rand()*50000),
  # anime types as returned by AniDB (lowercased)
  anime_types => {
    'unknown'     => undef, # NULL
    'tv series'   => 'tv',
    'ova'         => 'ova',
    'movie'       => 'mov',
    'other'       => 'oth',
    'web'         => 'web',
    'tv special'  => 'spe',
    'music video' => 'mv',
  },
);


sub run {
  shift;
  %O = (%O, @_);
  die "No AniDB user/pass configured!" if !$O{user} || !$O{pass};

  AnyEvent::Socket::resolve_sockaddr $O{apihost}, $O{apiport}, 'udp', 0, undef, sub {
    my($fam, $type, $proto, $saddr) = @{$_[0]};
    socket $C{sock}, $fam, $type, $proto or die "Can't create UDP socket: $!";
    connect $C{sock}, $saddr or die "Can't connect() UDP socket: $!";
    fh_nonblocking $C{sock}, 1;

    my($p, $h) = AnyEvent::Socket::unpack_sockaddr($saddr);
    AE::log info => sprintf "AniDB API client started, communicating with %s:%d", format_address($h), $p;

    push_watcher pg->listen(anime => on_notify => \&check_anime);
    push_watcher schedule 0, $O{check_delay}, \&check_anime;
    push_watcher AE::io $C{sock}, 0, \&receivemsg;

    check_anime();
  };
}


sub unload {
  undef $C{tw};
}


sub check_anime {
  return if $C{aid};
  pg_cmd 'SELECT id FROM anime WHERE lastfetch IS NULL OR lastfetch < NOW() - $1::interval LIMIT 1', [ $O{cachetime} ], sub {
    my $res = shift;
    return if pg_expect $res, 1 or $C{aid} or !$res->rows;
    $C{aid} = $res->value(0,0);
    nextcmd();
  };
}


sub nextcmd {
  return if $C{tw}; # don't send a command if we're waiting for a reply or timeout.
  return if !$C{aid}; # don't send a command if we've got nothing to fetch...

  my %cmd = !$C{s} ?
    ( # not logged in, get a session
      command => 'AUTH',
      user => $O{user},
      pass => $O{pass},
      protover => 3,
      client => $O{client},
      clientver => $O{clientver},
      enc => 'UTF-8',
    ) : ( # logged in, get anime
      command => 'ANIME',
      aid => $C{aid},
      acode => 3973121, # aid, ANN id, NFO id, year, type, romaji, kanji
    );

  # XXX: We don't have a writability watcher, but since we're only ever sending
  # out one packet at a time, I assume (or rather, hope) that the kernel buffer
  # always has space for it. If not, the timeout code will retry the command
  # anyway.
  my $cmd = fmtcmd(%cmd);
  AE::log debug => "Sending command: $cmd";
  my $n = syswrite $C{sock}, fmtcmd(%cmd);
  AE::log warn => sprintf "Didn't write command: only sent %d of %d bytes: %s", $n, length($cmd), $! if $n != length($cmd);

  $C{tw} = AE::timer $O{timeout}, 0, \&handletimeout;
  $C{lm} = AE::now;
}


sub fmtcmd {
  my %cmd = @_;
  my $cmd = delete $cmd{command};
  $cmd{tag} = ++$C{tag};
  $cmd{s} = $C{s} if $C{s};
  return $cmd.' '.join('&', map {
    $cmd{$_} =~ s/&/&amp;/g;
    $cmd{$_} =~ s/\r?\n/<br \/>/g;
    $_.'='.$cmd{$_}
  } keys %cmd);
}


sub receivemsg {
  my $buf = '';
  my $n = sysread $C{sock}, $buf, 4096;
  return AE::log warn => "sysread() failed: $!" if $n < 0;

  my $time = AE::now-$C{lm};
  AE::log debug => sprintf "Received message in %.2fs: %s", $time, $buf;

  my @r = split /\n/, $buf;
  my($tag, $code, $msg) = ($1, $2, $3) if $r[0] =~ /^([0-9]+) ([0-9]+) (.+)$/;

  return AE::log warn => "Ignoring message due to incorrect tag: $buf"
    if !$tag || $tag != $C{tag};
  return AE::log warn => "Ignoring message with unknown code: $buf"
    if !grep $_ == $code, @handled_codes;

  # Now we have a message we can handle, reset timer
  undef $C{tw};

  # Consider some codes to be equivalent to a timeout
  if($code == CLIENT_BANNED || $code == BANNED || $code == ANIDB_OUT_OF_SERVICE || $code == SERVER_BUSY) {
    # Might want to look into these...
    AE::log warn => "AniDB doesn't seem to like me: $buf" if $code == CLIENT_BANNED || $code == BANNED;
    handletimeout();
    return;
  }

  handlemsg($tag, $code, $msg, @r);
}


sub handlemsg {
  my($tag, $code, $msg, @r) = @_;
  my $f;

  # our session isn't valid, discard it and call nextcmd to get a new one
  if($code == NOT_LOGGED_IN || $code == LOGIN_FIRST || $code == INVALID_SESSION) {
    $C{s} = '';
    $f = \&nextcmd;
    AE::log info => 'Our session was invalid, logging in again...';
  }

  # we received a session ID, call nextcmd again to fetch anime info
  elsif($code == LOGIN_ACCEPTED || $code == LOGIN_ACCEPTED_NEW_VER) {
    $C{s} = $1 if $msg =~ /^\s*([a-zA-Z0-9]{4,8}) /;
    $f = \&nextcmd;
    AE::log info => 'Successfully logged in to AniDB.';
  }

  # we now know something about the anime we requested, update DB
  elsif($code == NO_SUCH_ANIME) {
    AE::log info => "No anime found with id = $C{aid}";
    pg_cmd 'UPDATE anime SET lastfetch = NOW() WHERE id = ?',
      [ $C{aid} ], sub { pg_expect $_[0], 0 };
    $f = \&check_anime;
    $C{aid} = 0;

  } else {
    update_anime($r[1]);
    $f = \&check_anime;
    $C{aid} = 0;
  }

  $C{tw} = AE::timer $O{msgdelay}, 0, sub { undef $C{tw}; $f->() };
}


sub update_anime {
  my $r = shift;

  # aid, ANN id, NFO id, year, type, romaji, kanji
  my @col = split(/\|/, $r, 7);
  for(@col) {
    $_ =~ s/<br \/>/\n/g;
    $_ =~ s/`/'/g;
  }
  $col[1] = undef if !$col[1];
  $col[2] = undef if !$col[2] || $col[2] =~ /^0,/;
  $col[3] = $col[3] =~ /^([0-9]+)/ ? $1 : undef;
  $col[4] = $O{anime_types}{ lc($col[4]) };
  $col[5] = undef if !$col[5];
  $col[6] = undef if !$col[6];

  pg_cmd 'UPDATE anime
    SET id = $1, ann_id = $2, nfo_id = $3, year = $4, type = $5,
        title_romaji = $6, title_kanji = $7, lastfetch = NOW()
    WHERE id = $8',
    [ @col, $C{aid} ],
    sub { pg_expect $_[0], 0 };
  AE::log info => "Fetched anime info for a$C{aid}";
  AE::log warn => "a$C{aid} doesn't have a title or year!"
    if !$col[3] || !$col[5];
}


sub handletimeout {
  $C{tm}++;
  my $delay = $O{msgdelay}**(1 + $C{tm}*$O{timeoutdelay});
  $delay = $O{maxtimeoutdelay} if $delay > $O{maxtimeoutdelay};
  AE::log info => 'Reply timed out, delaying %.0fs.', $delay;
  $C{tw} = AE::timer $delay, 0, sub { undef $C{tw}; nextcmd() };
}

1;
