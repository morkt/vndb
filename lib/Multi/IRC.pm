
#
#  Multi::IRC  -  HMX-12 Multi, the IRC bot
#

package Multi::IRC;

use strict;
use warnings;
use POE qw|
  Component::IRC::State
  Component::IRC::Plugin::Connector
  Component::IRC::Plugin::CTCP
  Component::IRC::Plugin::Logger
  Component::IRC::Plugin::NickServID
|;
use POE::Component::IRC::Common ':ALL';


sub spawn {
  return if $Multi::DAEMONIZE != 0; # we don't provide any commands, after all

  my $p = shift;
  my $irc = POE::Component::IRC::State->spawn(
    alias => 'circ',
    NoDNS => 1,
  );
  POE::Session->create(
    package_states => [
      $p => [qw| _start irc_001 irc_public irc_ctcp_action irc_msg vndbid shutdown |],
    ],
    heap => { irc => $irc,
      o => {
        user => 'Multi',
        server => 'irc.synirc.net',
        ircname => 'VNDB.org Multi',
        channel => '#vndb',
        @_
      }
    }
  );
}


sub _start {
  $_[KERNEL]->alias_set('irc');

  $_[HEAP]{irc}->plugin_add(
    Logger => POE::Component::IRC::Plugin::Logger->new(
      Path => $Multi::LOGDIR,
      Private => 0,
      Public => 1,
  ));
  $_[HEAP]{irc}->plugin_add(
    Connector => POE::Component::IRC::Plugin::Connector->new()
  );
  $_[HEAP]{irc}->plugin_add(
    CTCP => POE::Component::IRC::Plugin::CTCP->new(
      version => $_[HEAP]{o}{ircname}.' v'.$Multi::VERSION,
      userinfo => $_[HEAP]{o}{ircname},
  ));
  $_[HEAP]{irc}->plugin_add(
    NickServID => POE::Component::IRC::Plugin::NickServID->new(
      Password => $_[HEAP]{o}{pass}
  )) if $_[HEAP]{o}{pass};

  $_[KERNEL]->post(circ => register => 'all');
  $_[KERNEL]->post(circ => connect => {
    Nick  => $_[HEAP]{o}{user},
    Username => 'u1',
    Ircname => $_[HEAP]{o}{ircname},
    Server => $_[HEAP]{o}{server},
  });

  $_[KERNEL]->sig('shutdown' => 'shutdown');
}


sub irc_001 { 
  $_[KERNEL]->post(circ => join => $_[HEAP]{o}{channel});
  $_[KERNEL]->call(core => log => 2, 'Connected to IRC!');
}


sub irc_public {
  if($_[ARG2] =~ /^!info/) {
    $_[KERNEL]->post(circ => privmsg => $_[ARG1][0],
      'Hello, I am HMX-12 Multi v'.$Multi::VERSION.' made by the great Yorhel! (Please ask Ayo for more info)');
  } else {
    $_[KERNEL]->call(irc => vndbid => $_[ARG1][0], $_[ARG2]);
  }
}


sub irc_ctcp_action {
  $_[KERNEL]->call(irc => vndbid => $_[ARG1][0], $_[ARG2]);
}


sub irc_msg {
  my $nick = ( split /!/, $_[ARG0] )[0];

  if(!$_[HEAP]{irc}->is_channel_operator($_[HEAP]{o}{channel}, $nick)
   && !$_[HEAP]{irc}->is_channel_owner($_[HEAP]{o}{channel}, $nick)
   && !$_[HEAP]{irc}->is_channel_admin($_[HEAP]{o}{channel}, $nick)) {
    $_[KERNEL]->post(circ => privmsg => $nick, 'You are not my master');
    return;
  }

  my $m = $_[ARG2];
  if($m =~ /^say (.+)$/) {
    $_[KERNEL]->post(circ => privmsg => $_[HEAP]{o}{channel}, $1); }
  elsif($m =~ /^me (.+)$/) {
    $_[KERNEL]->post(circ => ctcp => $_[HEAP]{o}{channel}, "ACTION $1"); }
  elsif($m =~ /^cmd (.+)$/) {
    $_[KERNEL]->post(core => queue => $1); }
  elsif($m =~ /^eval (.+)$/) {
    $_[KERNEL]->post(circ => privmsg => $nick, 'eval: '.$_)
      for (split /\r?\n/, eval($1)||$@); }
  else {
    $_[KERNEL]->post(circ => privmsg => $nick, 'Unkown command'); }

  # TODO: add command to view the current queue, and a method to send log messages
}


sub vndbid { # dest, msg
  my $m = $_[ARG1];
  my @id;
  push @id, [$1,$2,$3,$4] while $m =~ s/^(.*)([uvpr])([0-9]+)(.*)$/ $1 $4 /i;
  for (reverse @id) {
    next if $$_[0] =~ /(\.org\/|[a-z])$/i || $$_[3] =~ /^[a-z]/i;
    my($t, $id) = (lc($$_[1]), $$_[2]);
    my $s = $Multi::SQL->prepare(
      $t eq 'v' ? 'SELECT vr.title FROM vn_rev vr JOIN vn v ON v.latest = vr.id WHERE v.id = ?' :
      $t eq 'u' ? 'SELECT u.username AS title FROM users u WHERE u.id = ?' :
      $t eq 'p' ? 'SELECT pr.name AS title FROM producers_rev pr JOIN producers p ON p.latest = pr.id WHERE p.id = ?' :
                  'SELECT rr.title FROM releases_rev rr JOIN releases r ON r.latest = rr.id WHERE r.id = ?'
    );
    $s->execute($id);
    my $r = $s->fetchrow_hashref;
    $s->finish;
    next if !$r || ref($r) ne 'HASH';
    $_[KERNEL]->post(circ => privmsg => $_[ARG0], sprintf
      BOLD.RED.'['.RED.'%s%d'.RED.']'.NORMAL.' %s '.RED.'@'.NORMAL.LIGHT_GREY.' http://vndb.org/%s%d'.NORMAL,
      $t, $id, $r->{title}, $t, $id
    );
  }
}


sub shutdown {
  $_[KERNEL]->post(circ => shutdown => 'Byebye!');
}


1;



__END__

# debug
sub _default {
  my($event,$args) = @_[ ARG0 .. $#_ ];
  my $arg_number = 0;
  for (@$args) {
    print "  ARG$arg_number = ";
    if ( ref($_) eq 'ARRAY' ) {
      print "$_ = [", join ( ", ", @$_ ), "]\n";
    }
    else {
      print "'".($_||'')."'\n";
    }
    $arg_number++;
  }
  return 0;
}

