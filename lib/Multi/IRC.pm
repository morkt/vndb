
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
      $p => [qw| _start irc_001 irc_public irc_ctcp_action irc_msg irccmd vndbid shutdown |],
    ],
    heap => { irc => $irc,
      o => {
        user => 'Multi',
        server => 'irc.synirc.net',
        ircname => 'VNDB.org Multi',
        channel => '#vndb',
        @_
      },
      log => {},
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
      version => $_[HEAP]{o}{ircname}.' v'.$VNDB::VERSION,
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
  if($_[ARG2] =~ /^!/) {
    (my $cmd = $_[ARG2]) =~ s/^!//;
    my $nick = (split /!/, $_[ARG0])[0];
    $_[KERNEL]->call(irc => irccmd => $_[ARG1][0], $cmd, $nick, $nick.', ');
  } else {
    $_[KERNEL]->call(irc => vndbid => $_[ARG1][0], $_[ARG2]);
  }
}


sub irc_ctcp_action {
  $_[KERNEL]->call(irc => vndbid => $_[ARG1][0], $_[ARG2]);
}


sub irc_msg {
  my $nick = ( split /!/, $_[ARG0] )[0];
  $_[KERNEL]->call(irc => irccmd => $nick => $_[ARG2]);
}


sub irccmd { # dest, cmd, [nick], [prep]
  my($dest, $cmd, $nick, $prep) = @_[ARG0..$#_];
  $nick ||= $_[ARG0];
  $prep ||= '';

  if($cmd =~ /^info/) {
    return $_[KERNEL]->post(circ => privmsg => $dest,
      'Hello, I am HMX-12 Multi v'.$VNDB::VERSION.' made by the great Yorhel!');
  }
  
  return $_[KERNEL]->post(circ => privmsg => $dest,
      $prep.'You are not my master!')
    if !$_[HEAP]{irc}->is_channel_operator($_[HEAP]{o}{channel}, $nick)
    && !$_[HEAP]{irc}->is_channel_owner($_[HEAP]{o}{channel}, $nick)
    && !$_[HEAP]{irc}->is_channel_admin($_[HEAP]{o}{channel}, $nick);

  if($cmd =~ /^say (.+)$/) {
    $_[KERNEL]->post(circ => privmsg => $_[HEAP]{o}{channel}, $1);
  } elsif($cmd =~ /^me (.+)$/) {
    $_[KERNEL]->post(circ => ctcp => $_[HEAP]{o}{channel}, "ACTION $1");
  } elsif($cmd =~ /^cmd (.+)$/) {
    $_[KERNEL]->post(core => queue => $1);
    $_[KERNEL]->post(circ => privmsg => $dest => sprintf "%sExecuting command '%s'", $prep, $1);
  } elsif($cmd =~ /^eval (.+)$/) {
    $_[KERNEL]->post(circ => privmsg => $dest, $prep.'eval: '.$_)
      for (split /\r?\n/, eval($1)||$@);
  } else {
    $_[KERNEL]->post(circ => privmsg => $dest, $prep.'Unkown command');
  }

  # TODO: add command to view the current queue, and a method to send log messages
}


sub vndbid { # dest, msg
  my $m = $_[ARG1];

  $_[HEAP]{log}{$_} < time-60 and delete $_[HEAP]{log}{$_}
    for (keys %{$_[HEAP]{log}});

  my @id;
  push @id, [$1,$2,$3,$4] while $m =~ s/^(.*)([duvpr])([0-9]+)(.*)$/ $1 $4 /i;
  for (reverse @id) {
    next if $$_[0] =~ /[a-z0-9%\/]$/i || $$_[3] =~ /^[a-z]/i || ($$_[1] eq 'v' && $$_[3] =~ /^\.[0-9]/);
    my($t, $id, $ext) = (lc($$_[1]), $$_[2], $$_[3]);

    next if $_[HEAP]{log}{$t.$id};
    $_[HEAP]{log}{$t.$id} = time;

    if($t ne 'd') {
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

    } else {
      my $f = sprintf '/www/vndb/data/docs/%d', $id;
      open my $F, '<', $f or next;
      (my $title = <$F>) =~ s/^:TITLE://;
      chomp($title);

      my($sub, $sec) = ('', 0);
      if($ext && $ext =~ /^\.([0-9]+)/) {
        my $fs = $1;
        while(<$F>) {
          next if !/^:SUB:/;
          $sec++;
          if($sec == $fs) {
            chomp;
            ($sub = $_) =~ s/^:SUB://;
            last;
          }
        }
      }
      close $F;

      if(!$sub) {
        $_[KERNEL]->post(circ => privmsg => $_[ARG0], sprintf
          BOLD.RED.'['.RED.'d%d'.RED.']'.NORMAL.' %s '.RED.'@'.NORMAL.LIGHT_GREY.' http://vndb.org/d%d'.NORMAL,
          $id, $title, $id
        );
      } else {
        $_[KERNEL]->post(circ => privmsg => $_[ARG0], sprintf
          BOLD.RED.'['.RED.'d%d.%d'.RED.']'.NORMAL.' %s -> %s '.RED.'@'.NORMAL.LIGHT_GREY.' http://vndb.org/d%d#%d'.NORMAL,
          $id, $sec, $title, $sub, $id, $sec
        );
      }
    }
  }
}


sub shutdown {
  $_[KERNEL]->post(circ => shutdown => 'Byebye!');
}


1;


