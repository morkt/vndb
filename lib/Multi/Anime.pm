
#
#  Multi::Anime  -  Fetches anime info from AniDB
#

package Multi::Anime;

use strict;
use warnings;
use POE 'Wheel::UDP', 'Filter::Stream';
use Socket 'inet_ntoa';
use Time::HiRes 'time';


sub TIMEOUT                () { 100 } # not part of the API
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
  TIMEOUT, LOGIN_ACCEPTED, LOGIN_ACCEPTED_NEW_VER, ANIME, NO_SUCH_ANIME, NOT_LOGGED_IN,
  LOGIN_FIRST,CLIENT_BANNED, INVALID_SESSION, BANNED, ANIDB_OUT_OF_SERVICE, SERVER_BUSY
);



sub spawn {
  my $p = shift;
  my %o = @_;

  die "No AniDB user/pass configured!" if !$o{user} || !$o{pass};

  my $addr = delete($o{PeerAddr}) || 'api.anidb.info';
  $addr = gethostbyname($addr) or die "Couldn't resolve domain";
  $addr = inet_ntoa($addr);

  POE::Session->create(
    package_states => [
      $p => [qw| _start shutdown check_anime fetch_anime nextcmd receivepacket |],
    ],
    heap => {
      # POE::Wheels::UDP options
      LocalAddr => '0.0.0.0',
      LocalPort => 9000,
      PeerAddr => $addr,
      PeerPort => 9000,
      # AniDB UDP API options
      client => 'multi',
      clientver => 1,
      # Misc settings
      msgdelay => 10,
      timeout => 30,
      timeoutdelay => 0.4, # $delay = $msgdelay ^ (1 + $tm*$timeoutdelay)
      maxtimeoutdelay => 2*3600, # two hours
      check_delay => 3600,   # one hour
      cachetime => '1 month',

      %o,
      w => undef,
      s => '',    # session key, '' = not logged in
      tm => 0,    # number of repeated timeouts
      lm => 0,    # timestamp of last outgoing message, 0=no running msg
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
    },
  );
}


sub _start {
  $_[KERNEL]->alias_set('anime');
  $_[KERNEL]->sig(shutdown => 'shutdown');

  # listen for 'anime' notifies
  $_[KERNEL]->post(pg => listen => anime => 'check_anime');

  # init the UDP 'connection'
  $_[HEAP]{w} = POE::Wheel::UDP->new(
    (map { $_ => $_[HEAP]{$_} } qw| LocalAddr LocalPort PeerAddr PeerPort |),
    InputEvent => 'receivepacket',
    Filter => POE::Filter::Stream->new(),
  );

  # look for something to do
  $_[KERNEL]->yield('check_anime');
}


sub shutdown {
  undef $_[HEAP]{w};
  $_[KERNEL]->post(pg => unlisten => 'anime');
  $_[KERNEL]->delay('check_anime');
  $_[KERNEL]->delay('nextcmd');
  $_[KERNEL]->delay('receivepacket');
  $_[KERNEL]->alias_remove('anime');
}


sub check_anime {
  return if $_[HEAP]{aid};
  $_[KERNEL]->delay('check_anime');
  $_[KERNEL]->post(pg => query => 'SELECT id FROM anime WHERE lastfetch IS NULL OR lastfetch < NOW() - ?::interval LIMIT 1',
    [ $_[HEAP]{cachetime} ], 'fetch_anime');
}


sub fetch_anime { # num, res
  # nothing to do, check again later
  return $_[KERNEL]->delay('check_anime', $_[HEAP]{check_delay}) if $_[ARG0] == 0;

  # otherwise, fetch info (if we aren't doing so already)
  return if $_[HEAP]{aid};
  $_[HEAP]{aid} = $_[ARG1][0]{id};
  $_[KERNEL]->yield('nextcmd');
}


sub nextcmd {
  my %cmd;
  # not logged in, get a session
  if(!$_[HEAP]{s}) {
    %cmd = (
      command => 'AUTH',
      user => $_[HEAP]{user},
      pass => $_[HEAP]{pass},
      protover => 3,
      client => $_[HEAP]{client},
      clientver => $_[HEAP]{clientver},
      enc => 'UTF-8',
    );
  }
  # logged in, get anime
  else {
    %cmd = (
      command => 'ANIME',
      aid => $_[HEAP]{aid},
      acode => 3973121, # aid, ANN id, NFO id, year, type, romaji, kanji
    );
  }

  # send command
  my $cmd = delete $cmd{command};
  $cmd{tag} = ++$_[HEAP]{tag};
  $cmd{s} = $_[HEAP]{s} if $_[HEAP]{s};
  $cmd .= ' '.join('&', map {
    $cmd{$_} =~ s/&/&amp;/g;
    $cmd{$_} =~ s/\r?\n/<br \/>/g;
    $_.'='.$cmd{$_}
  } keys %cmd);
  $_[HEAP]{w}->put({ payload => [ $cmd ]});

  $_[KERNEL]->delay(receivepacket => $_[HEAP]{timeout}, { payload => [ $_[HEAP]{tag}.' 100 TIMEOUT' ] });
  $_[HEAP]{lm} = time;
}


sub receivepacket { # input, wheelid
  # parse message
  my @r = split /\n/, $_[ARG0]{payload}[0];
  my($tag, $code, $msg) = ($1, $2, $3) if $r[0] =~ /^([0-9]+) ([0-9]+) (.+)$/;
  my $time = time-$_[HEAP]{lm};

  # tag incorrect, ignore message
  return $_[KERNEL]->call(core => log => 'Ignoring incorrect tag of message: %s', $r[0])
    if !$tag || $tag != $_[HEAP]{tag};

  # unhandled code, ignore as well
  return $_[KERNEL]->call(core => log => 'Ignoring unhandled code %d (%s)', $code, $msg)
    if !grep $_ == $code, @handled_codes;

  # at this point, we have a message we can handle, so disable the timeout
  $_[KERNEL]->delay('receivepacket');
  $_[HEAP]{lm} = 0;

  # received a timeout of some sorts, try again later
  if($code == TIMEOUT || $code == CLIENT_BANNED || $code == BANNED || $code == ANIDB_OUT_OF_SERVICE || $code == SERVER_BUSY) {
    $_[HEAP]{tm}++;
    my $delay = $_[HEAP]{msgdelay}**(1 + $_[HEAP]{tm}*$_[HEAP]{timeoutdelay});
    $delay = $_[HEAP]{maxtimeoutdelay} if $delay > $_[HEAP]{maxtimeoutdelay};
    $_[KERNEL]->call(core => log => 'Reply timed out, delaying %.0fs.', $delay);
    return $_[KERNEL]->delay(nextcmd => $delay);
  }

  # message wasn't a timeout, reset timeout counter
  $_[HEAP]{tm} = 0;

  # our session isn't valid, discard it and call nextcmd to get a new one
  if($code == NOT_LOGGED_IN || $code == LOGIN_FIRST || $code == INVALID_SESSION) {
    $_[HEAP]{s} = '';
    $_[KERNEL]->call(core => log => 'Our session was invalid, logging in again...');
    return $_[KERNEL]->delay(nextcmd => $_[HEAP]{msgdelay});
  }

  # we received a session ID, call nextcmd again to fetch anime info
  if($code == LOGIN_ACCEPTED || $code == LOGIN_ACCEPTED_NEW_VER) {
    $_[HEAP]{s} = $1 if $msg =~ /^\s*([a-zA-Z0-9]{4,8}) /;
    $_[KERNEL]->call(core => log => 'Successfully logged in to AniDB in %.2fs.', $time);
    return $_[KERNEL]->delay(nextcmd => $_[HEAP]{msgdelay});
  }

  # we now know something about the anime we requested, update DB
  if($code == NO_SUCH_ANIME) {
    $_[KERNEL]->call(core => log => 'ERROR: No anime found with id = %d', $_[HEAP]{aid});
    $_[KERNEL]->post(pg => do => 'UPDATE anime SET lastfetch = NOW() WHERE id = ?', [ $_[HEAP]{aid} ]);
  } else {
    # aid, ANN id, NFO id, year, type, romaji, kanji
    my @col = split(/\|/, $r[1], 7);
    for (@col) {
      $_ =~ s/<br \/>/\n/g;
      $_ =~ s/`/'/g;
    }
    $col[1] = undef if !$col[1];
    $col[2] = undef if !$col[2] || $col[2] =~ /^0,/;
    $col[3] = $col[3] =~ /^([0-9]+)/ ? $1 : undef;
    $col[3] = undef if !$col[3];
    $col[4] = $_[HEAP]{anime_types}{ lc($col[4]) };
    $col[5] = undef if !$col[5];
    $col[6] = undef if !$col[6];
    $_[KERNEL]->post(pg => do => 'UPDATE anime
      SET id = ?, ann_id = ?, nfo_id = ?, year = ?, type = ?,
          title_romaji = ?,title_kanji = ?, lastfetch = NOW()
      WHERE id = ?',
      [ @col, $_[HEAP]{aid} ]
    );
    $_[KERNEL]->call(core => log => 'Fetched anime info for a%d in %.2fs', $_[HEAP]{aid}, $time);
    $_[KERNEL]->call(core => log => 'ERROR: a%d doesn\'t have a title or year!', $_[HEAP]{aid})
      if !$col[3] || !$col[5];
  }

  # this anime is handled, check for more
  $_[HEAP]{aid} = 0;
  $_[KERNEL]->delay(check_anime => $_[HEAP]{msgdelay});
}


1;

