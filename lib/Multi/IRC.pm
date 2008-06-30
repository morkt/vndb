
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
        user => 'Multi_test'.$$,
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
    $_[KERNEL]->post(circ => privmsg => $dest => sprintf "Executing command '%s'", $1);
  } elsif($cmd =~ /^eval (.+)$/) {
    $_[KERNEL]->post(circ => privmsg => $dest, 'eval: '.$_)
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

  # Four possible options:
  #  1.  [vpru]+   -> item page
  #  2.  [vpr]+.+  -> item revision
  #  3.  d+        -> documentation page
  #  4.  d+.+      -> documentation page # section

  my @formats = (
    BOLD.RED.'['.NORMAL.BOLD.'%s%d'   .RED.']'.NORMAL.' %s '                       .RED.'@'.NORMAL.LIGHT_GREY.' %s/%1$s%2$d'.NORMAL,
    BOLD.RED.'['.NORMAL.BOLD.'%s%d.%d'.RED.']'.NORMAL.' %s '.RED.'by'.NORMAL.' %s '.RED.'@'.NORMAL.LIGHT_GREY.' %s/%1$s%2$d.%3$d'.NORMAL,
    BOLD.RED.'['.NORMAL.BOLD.'d%d'    .RED.']'.NORMAL.' %s '                       .RED.'@'.NORMAL.LIGHT_GREY.' %s/d%1$d'.NORMAL,
    BOLD.RED.'['.NORMAL.BOLD.'d%d.%d' .RED.']'.NORMAL.' %s '.RED.'->'.NORMAL.' %s '.RED.'@'.NORMAL.LIGHT_GREY.' %s/d%1$d#%2$d'.NORMAL,
  );

  # get a list of possible IDs (a la sub summary in defs.pl)
  my @id; # [ type, id, ref ]
  for (split /[, ]/, $m) {
    next if length > 15 or m{[a-z]{3,6}://}i; # weed out URLs and too long things
    push @id, /^(?:.*[^\w]|)([dvpr])([0-9]+)\.([0-9]+)(?:[^\w].*|)$/ ? [ $1, $2, $3 ]   # matches 2 and 4
           :  /^(?:.*[^\w]|)([duvpr])([0-9]+)(?:[^\w].*|)$/ ? [ $1, $2, 0 ] : ();       # matches 1 and 3
  }

  # loop through the matched IDs and search the database
  for (@id) {
    my($t, $id, $rev) = (@$_);

    next if $_[HEAP]{log}{$t.$id.'.'.$rev};
    $_[HEAP]{log}{$t.$id.'.'.$rev} = time;

   # option 1: item page
    if($t =~ /[vpru]/ && !$rev) {
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
      $_[KERNEL]->post(circ => privmsg => $_[ARG0], sprintf $formats[0],
        $t, $id, $r->{title}, $VNDB::VNDBopts{root_url});

   # option 2: item revision
    } elsif($t =~ /[vpr]/) {
      my $s = $Multi::SQL->prepare(sprintf q|
        SELECT %s AS title, u.username
        FROM changes c
        JOIN %s_rev i ON c.id = i.id
        JOIN users u ON u.id = c.requester
        WHERE i.%sid = %d 
          AND c.rev = %d|,
        $t ne 'p' ? 'i.title' : 'i.name',
        {qw|v vn r releases p producers|}->{$t},
        $t, $id, $rev);
      $s->execute;
      my $r = $s->fetchrow_hashref;
      next if !$r || ref($r) ne 'HASH';
      $_[KERNEL]->post(circ => privmsg => $_[ARG0], sprintf $formats[1],
        $t, $id, $rev, $r->{title}, $r->{username}, $VNDB::VNDBopts{root_url});

   # option 3: documentation page
    } elsif($t eq 'd') {
      my $f = sprintf '/www/vndb/data/docs/%d', $id;
      open my $F, '<', $f or next;
      (my $title = <$F>) =~ s/^:TITLE://;
      chomp($title);

      if(!$rev) {
        $_[KERNEL]->post(circ => privmsg => $_[ARG0], sprintf $formats[2],
          $id, $title, $VNDB::VNDBopts{root_url});
        next;
      }

   # option 4: documentation page # section
      my($sec, $sub);
      while(<$F>) {
        if(/^:SUB:/ && ++$sec == $rev) {
          chomp;
          ($sub = $_) =~ s/^:SUB://;
          last;
        }
      }
      next if !$sub;
      $_[KERNEL]->post(circ => privmsg => $_[ARG0], sprintf $formats[3],
        $id, $rev, $title, $sub, $VNDB::VNDBopts{root_url});
    }
  }
}


sub shutdown {
  $_[KERNEL]->post(circ => shutdown => 'Byebye!');
}


1;


