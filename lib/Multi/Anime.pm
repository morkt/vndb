
#
#  Multi::Anime  -  Fetches anime info from AniDB
#

package Multi::Anime;

use strict;
use warnings;
use POE 'Wheel::UDP', 'Filter::Stream';
use Tie::ShareLite ':lock';
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

my @expected_codes = ( TIMEOUT, LOGIN_ACCEPTED, LOGIN_ACCEPTED_NEW_VER, ANIME, NO_SUCH_ANIME, NOT_LOGGED_IN, LOGIN_FIRST, INVALID_SESSION );


sub spawn {
  # The 'anime' command doesn't actually do anything, it just
  #  adds IDs to process to the internal queue, which is seperate
  #  from the global processing queue.
  # This module -only- fetches anime information in daemon mode!
  # Calling the anime command with an ID as argument will force
  #  the information to be refreshed. This is not recommended, 
  #  just use 'anime' for normal usage.

  my $p = shift;
  POE::Session->create(
    package_states => [
      $p => [qw| _start shutdown cmd_anime nextcmd receivepacket updateanime |],
    ],
    heap => {
     # POE::Wheels::UDP options
      LocalAddr => '0.0.0.0',
      LocalPort => 9000,
      PeerAddr => do {
        if(!$Multi::DAEMONIZE) {
          my $a = gethostbyname('api.anidb.info');
          die "ERROR: Couldn't resolve domain" if !defined $a;
          inet_ntoa($a);
        } else {
          0;
        }
      },
      PeerPort => 9000,
     # AniDB UDP API options
      client => 'multi',
      clientver => 1,
     # Misc settings
      msgdelay => 10,
      timeout => 30,
      timeoutdelay => 0.4, # $delay = $msgdelay ^ (1 + $tm*$timeoutdelay)
      maxtimeoutdelay => 2*3600, # two hours
      cachetime => 30*24*3600,   # one month

      @_,
      w => undef,
      s => '',    # session key, '' = not logged in
      tm => 0,    # number of repeated timeouts
      lm => 0,    # timestamp of last outgoing message, 0=no running msg
      aid => 0,   # anime ID of the last sent ANIME command
      tag => int(rand()*50000),
    },
  );
}


sub _start {
  $_[KERNEL]->alias_set('anime');
  $_[KERNEL]->call(core => register => qr/^anime(?: ([0-9]+))?$/, 'cmd_anime');
  
 # check for anime twice a day
  $_[KERNEL]->post(core => addcron => '0 0,12 * * *', 'anime');
  $_[KERNEL]->sig('shutdown' => 'shutdown');
 
  if(!$Multi::DAEMONIZE) {
   # init the UDP 'connection'
    $_[HEAP]{w} = POE::Wheel::UDP->new(
      (map { $_ => $_[HEAP]{$_} } qw| LocalAddr LocalPort PeerAddr PeerPort |),
      InputEvent => 'receivepacket',
      Filter => POE::Filter::Stream->new(),
    );

   # start executing commands
    $_[KERNEL]->delay(nextcmd => 0); #$_[HEAP]{msgdelay});
  }
}


sub shutdown {
  undef $_[HEAP]{w};
  $_[KERNEL]->delay('nextcmd');
  $_[KERNEL]->delay('receivepacket');
}


sub cmd_anime { # cmd, arg
  my @push;
  if(!$_[ARG1]) {
    # only animes we have never fetched, or haven't been updated for a month
    my $q = $Multi::SQL->prepare(q|
      SELECT id
      FROM anime
      WHERE lastfetch < ?
        AND lastfetch <> -1|);
    $q->execute(int(time-$_[HEAP]{cachetime}));
    push @push, map $_->[0], @{$q->fetchall_arrayref([])};
    $_[KERNEL]->call(core => log => 2, 'All anime info is up-to-date!') if !@push;
  } else {
    push @push, $_[ARG1];
  }

  if(@push) {
    my $s = tie my %s, 'Tie::ShareLite', @VNDB::SHMOPTS;
    $s->lock(LOCK_EX);
    my @q = $s{anime} ? @{$s{anime}} : ();
    push @q, grep { 
      my $ia = $_;
      !(scalar grep $ia == $_, @q)
    } @push;
    $s{anime} = \@q;
    $s->unlock();
  }

  $_[KERNEL]->post(core => finish => $_[ARG0]);
}


sub nextcmd {
  return if $_[HEAP]{lm};

  my $s = tie my %s, 'Tie::ShareLite', @VNDB::SHMOPTS;
  my @q = $s{anime} ? @{$s{anime}} : ();
  undef $s;

  if(!@q) { # nothing to do...
    $_[KERNEL]->delay(nextcmd => $_[HEAP]{msgdelay});
    return;
  } 
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
    $_[KERNEL]->call(core => log => 3, 'Authenticating with AniDB...');
  }

 # logged in, get anime
  else {
    $_[HEAP]{aid} = $q[0];
    %cmd = (
      command => 'ANIME',
      aid => $q[0],
      acode => 3973121, # aid, ANN id, NFO id, year, type, romaji, kanji
    );
    $_[KERNEL]->call(core => log => 3, 'Fetching info for a%d', $q[0]);
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
  $VNDB::DEBUG && printf " > %s\n", $cmd;
 
  $_[KERNEL]->delay(receivepacket => $_[HEAP]{timeout}, { payload => [ $_[HEAP]{tag}.' 100 TIMEOUT' ] });
  $_[HEAP]{lm} = time;
}


sub receivepacket { # input, wheelid
  $_[KERNEL]->delay('receivepacket'); # disable the timeout
  my @r = split /\n/, $_[ARG0]{payload}[0];
  my $delay = $_[HEAP]{msgdelay};

  my($tag, $code, $msg) = ($1, $2, $3) if $r[0] =~ /^([0-9]+) ([0-9]+) (.+)$/;

  if(!grep $_ == $code, @expected_codes) {
    $_[KERNEL]->call(core => log => 1, "Received an unexpected reply after %.2fs!\n < %s",
      time-$_[HEAP]{lm}, join("\n < ", @r));
  } else {
    $_[KERNEL]->call(core => log => 3, 'Received from AniDB after %.2fs: %d %s',
      time-$_[HEAP]{lm}, $code, $msg);
    $VNDB::DEBUG && print ' < '.join("\n < ", @r)."\n";
  }

 # just handle anime data, even if the tag is not correct
  if($code == ANIME) {
    $_[KERNEL]->yield(updateanime => $_[HEAP]{aid}, $r[1]);
  }

 # tag incorrect, ignore message
  if($tag != $_[HEAP]{tag}) {
    $_[KERNEL]->call(core => log => 3, 'Ignoring incorrect tag') if $code != ANIME;
    return;
  }

 # try again later
  if($code == TIMEOUT || $code == CLIENT_BANNED || $code == BANNED || $code == ANIDB_OUT_OF_SERVICE || $code == SERVER_BUSY) {
    $_[HEAP]{tm}++;
    $delay = $_[HEAP]{msgdelay}**(1 + $_[HEAP]{tm}*$_[HEAP]{timeoutdelay});
    $delay = $_[HEAP]{maxtimeoutdelay} if $delay > $_[HEAP]{maxtimeoutdelay};
    $_[KERNEL]->call(core => log => 1, 'Delaying %.0fs.', $delay);
  }

 # oops, wrong id
  if($code == NO_SUCH_ANIME) {
    $_[KERNEL]->yield(updateanime => $_[HEAP]{aid}, 'notfound');
  }

 # ok, we have a session now
  if($code == LOGIN_ACCEPTED || $code == LOGIN_ACCEPTED_NEW_VER) {
    $_[HEAP]{s} = $1 if $msg =~ /^\s*([a-zA-Z0-9]{4,8}) /;
  }

 # oops, we should've logged in, get a new session
  if($code == NOT_LOGGED_IN || $code == LOGIN_FIRST || $code == INVALID_SESSION) {
    $_[HEAP]{s} = '';
  }

  $_[HEAP]{lm} = $_[HEAP]{aid} = 0;
  $_[HEAP]{tm} = 0 if $delay == $_[HEAP]{msgdelay};
  $_[KERNEL]->delay(nextcmd => $delay);
}


sub updateanime { # aid, data|'notfound'
  # aid, ANN id, NFO id, year, type, romaji, kanji, lastfetch
  my @col = $_[ARG1] eq 'notfound'
    ? ($_[ARG0], 0, 0, 0, 0, '', '', -1)
    : (split(/\|/, $_[ARG1], 7), int time);

  if($col[7] > 0) {
    for (@col) {
      $_ =~ s/<br \/>/\n/g;
      $_ =~ s/`/'/g;
    }
    $col[3] = $1 if $col[3] =~ /^([0-9]+)/; # remove multi-year stuff
    for(0..$#$VNDB::ANITYPE) {
      $col[4] = $_ if lc($VNDB::ANITYPE->[$_][1]) eq lc($col[4]);
    }
    $col[4] = 0 if $col[4] !~ /^[0-9]+$/;
    $col[2] = '' if $col[2] =~ /^0,/;
  }

 # try to UPDATE first
  my $r = $Multi::SQL->do(q|
    UPDATE anime
      SET id = ?, ann_id = ?, nfo_id = ?, year = ?, type = ?,
          title_romaji = ?, title_kanji = ?, lastfetch = ?
      WHERE id = ?|,
    undef, @col, $col[0]);

 # fall back to INSERT when nothing was updated
  $Multi::SQL->do(q|
    INSERT INTO anime
      (id, ann_id, nfo_id, year, type, title_romaji, title_kanji, lastfetch)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)|,
    undef, @col) if $r < 1;

 # remove from queue
  my $s = tie my %s, 'Tie::ShareLite', @VNDB::SHMOPTS;
  $s->lock(LOCK_EX);
  my @q = grep $_ != $_[ARG0], ($s{anime} ? @{$s{anime}} : ());
  $s{anime} = \@q;
  $s->unlock();

  $col[7] > 0
    ? $_[KERNEL]->post(core => log => 2, 'Updated anime info for a%d', $col[0])
    : $_[KERNEL]->post(core => log => 1, 'Anime a%d not found!', $col[0]);
}


1;

