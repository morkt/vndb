
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
|;
use POE::Component::IRC::Common ':ALL';
use URI::Escape 'uri_escape_utf8';
use Net::HTTP;

use constant {
  ARG  => ARG0,
  DEST => ARG1,
  NICK => ARG2
};


sub spawn {
  return if $Multi::DAEMONIZE != 0; # we don't provide any commands, after all

  my $p = shift;
  my $irc = POE::Component::IRC::State->spawn(
    alias => 'circ',
    NoDNS => 1,
  );
  POE::Session->create(
    package_states => [
      $p => [qw|
        _start irc_001 irc_public irc_ctcp_action irc_msg irccmd vndbid ircnotify shutdown
        cmd_info cmd_vndb cmd_list cmd_vn cmd_uptime cmd_notifications cmd_me cmd_say cmd_cmd cmd_eval
      |],
    ],
    heap => { irc => $irc,
      o => {
        user => 'Multi_test'.$$,
        server => 'irc.synirc.net',
        ircname => 'VNDB.org Multi',
        channel => [ '#vndb' ],
        @_
      },
      log => {},
      privpers => {},
      notify => [],
    }
  );
}


sub _start {
  $_[KERNEL]->alias_set('irc');
  $_[KERNEL]->call(core => register => qr/^ircnotify ([vrptg][0-9]+\.[0-9]+)$/, 'ircnotify');

  $_[HEAP]{irc}->plugin_add(
    Logger => POE::Component::IRC::Plugin::Logger->new(
      Path => $VNDB::M{log_dir},
      Private => 0,
      Public => 1,
  ));
  $_[HEAP]{irc}->plugin_add(
    Connector => POE::Component::IRC::Plugin::Connector->new()
  );
  $_[HEAP]{irc}->plugin_add(
    CTCP => POE::Component::IRC::Plugin::CTCP->new(
      version => $_[HEAP]{o}{ircname}.' v'.$VNDB::S{version},
      userinfo => $_[HEAP]{o}{ircname},
  ));
  if($_[HEAP]{o}{pass}) {
    require POE::Component::IRC::Plugin::NickServID;
    $_[HEAP]{irc}->plugin_add(
      NickServID => POE::Component::IRC::Plugin::NickServID->new(
        Password => $_[HEAP]{o}{pass}
    )) 
  }
  if($_[HEAP]{o}{console}) {
    require POE::Component::IRC::Plugin::Console;
    $_[HEAP]{irc}->plugin_add(
      Console => POE::Component::IRC::Plugin::Console->new(
        bindport => 3030,
        password => $_[HEAP]{o}{console}
    )) 
  }

  $_[KERNEL]->post(circ => register => 'all');
  $_[KERNEL]->post(circ => connect => {
    Nick  => $_[HEAP]{o}{user},
    Username => 'u1',
    Ircname => $_[HEAP]{o}{ircname},
    Server => $_[HEAP]{o}{server},
  });

 # notifications in the main channel enabled by default
  push @{$_[HEAP]{notify}}, $_[HEAP]{o}{channel}[0];

  $_[KERNEL]->sig('shutdown' => 'shutdown');
}


sub irc_001 { 
  $_[KERNEL]->post(circ => join => $_) for (@{$_[HEAP]{o}{channel}});
  $_[KERNEL]->call(core => log => 2, 'Connected to IRC!');
}


sub irc_public {
  if($_[ARG2] =~ /^!/) {
    (my $cmd = $_[ARG2]) =~ s/^!//;
    my $nick = (split /!/, $_[ARG0])[0];
    $_[KERNEL]->call(irc => irccmd => $_[ARG1][0], $cmd, $nick);
  } else {
    $_[KERNEL]->call(irc => vndbid => $_[ARG1][0], $_[ARG2]);
  }
}


sub irc_ctcp_action {
  $_[KERNEL]->call(irc => vndbid => $_[ARG1][0], $_[ARG2]);
}


sub irc_msg {
  my $nick = ( split /!/, $_[ARG0] )[0];
  $_[ARG2] =~ s/^!//;
  if(!$_[KERNEL]->call(irc => irccmd => $nick => $_[ARG2])) {
    $_[HEAP]{privpers}{$_} < time-3600 and delete $_[HEAP]{privpers}{$_}
      for (keys %{$_[HEAP]{privpers}});
    $_[KERNEL]->post(circ => privmsg => $nick => 'I am not human, join #vndb or PM Yorhel if you need something.')
      if !$_[HEAP]{privpers}{$nick};
    $_[HEAP]{privpers}{$nick} ||= time;
  }
}


sub irccmd { # dest, cmd, [nick]
  my($dest, $cmd, $nick) = @_[ARG0..$#_];
  $nick ||= $_[ARG0];

  return 0 if $cmd !~ /^([a-z0-9A-Z_]+)(?: (.+))?$/;
  my($f, $a) = (lc $1, $2||'');

  # check for a cmd_* function and call it (some scary magic, see perlmod)
  my $sub;
  {
    no strict;
    $sub = ${__PACKAGE__.'::'}{'cmd_'.$f};
  }
  return 0 if !defined $sub;
  local *SUB = $sub;
  return 0 if !defined *SUB{CODE};
  $_[KERNEL]->yield('cmd_'.$f, $a, $dest, $nick);
  return 1;
}


sub vndbid { # dest, msg, force
  my $m = $_[ARG1];

  $_[HEAP]{log}{$_} < time-60 and delete $_[HEAP]{log}{$_}
    for (keys %{$_[HEAP]{log}});

  # Four possible options:
  #  1.  [tvprug]+ -> item/user/thread/tag (nf)
  #  2.  [vprt]+.+ -> revision/reply (ef)
  #  3.  d+        -> documentation page (nf)
  #  4.  d+.+      -> documentation page # section (sf)

  # nf (normal format):   x+     : x, id, title
  # sf (sub format):      x+.+   : x, id, subid, title, action2, title2
  # ef (extended format): x+.+   : x, id, subid, action, title, action2, title2
  my $nf = BOLD.RED.'['.NORMAL.BOLD.'%s%d'   .RED.']'                 .NORMAL.' %s '                       .RED.'@'.NORMAL.LIGHT_GREY.' '.$VNDB::S{url}.'/%1$s%2$d'.NORMAL;
  my $sf = BOLD.RED.'['.NORMAL.BOLD.'%s%d.%d'.RED.']'                 .NORMAL.' %s '.RED.'%s'.NORMAL.' %s '.RED.'@'.NORMAL.LIGHT_GREY.' '.$VNDB::S{url}.'/%1$s%2$d.%3$d'.NORMAL;
  my $ef = BOLD.RED.'['.NORMAL.BOLD.'%s%d.%d'.RED.']'.NORMAL.RED.' %s'.NORMAL.' %s '.RED.'%s'.NORMAL.' %s '.RED.'@'.NORMAL.LIGHT_GREY.' '.$VNDB::S{url}.'/%1$s%2$d.%3$d'.NORMAL;

  # get a list of possible IDs (a la sub summary in defs.pl)
  my @id; # [ type, id, ref ]
  for (split /[, ]/, $m) {
    next if length > 15 or m{[a-z]{3,6}://}i; # weed out URLs and too long things
    push @id, /^(?:.*[^\w]|)([dvprt])([1-9][0-9]*)\.([1-9][0-9]*)(?:[^\w].*|)$/ ? [ $1, $2, $3 ]   # matches 2 and 4
           :  /^(?:.*[^\w]|)([dvprtug])([1-9][0-9]*)(?:[^\w].*|)$/ ? [ $1, $2, 0 ] : ();       # matches 1 and 3
  }

  # loop through the matched IDs and search the database
  for (@id) {
    my($t, $id, $rev) = (@$_);

    next if $_[HEAP]{log}{$t.$id.'.'.$rev} && !$_[ARG2];
    $_[HEAP]{log}{$t.$id.'.'.$rev} = time;

   # option 1: item/user/thread/tag
    if($t =~ /[vprtug]/ && !$rev) {
      my $s = $Multi::SQL->prepare(
        $t eq 'v' ? 'SELECT vr.title FROM vn_rev vr JOIN vn v ON v.latest = vr.id WHERE v.id = ?' :
        $t eq 'u' ? 'SELECT u.username AS title FROM users u WHERE u.id = ?' :
        $t eq 'p' ? 'SELECT pr.name AS title FROM producers_rev pr JOIN producers p ON p.latest = pr.id WHERE p.id = ?' :
        $t eq 't' ? 'SELECT title FROM threads WHERE id = ?' :
        $t eq 'g' ? 'SELECT name AS title FROM tags WHERE id = ?' :
                    'SELECT rr.title FROM releases_rev rr JOIN releases r ON r.latest = rr.id WHERE r.id = ?'
      );
      $s->execute($id);
      my $r = $s->fetchrow_hashref;
      $s->finish;
      next if !$r || ref($r) ne 'HASH';
      $_[KERNEL]->post(circ => privmsg => $_[ARG0], sprintf $nf,
        $t, $id, $r->{title});

   # option 2: revision/reply
    } elsif($t =~ /[vprt]/) {
      my $s = $Multi::SQL->prepare(
        $t eq 'v' ? 'SELECT vr.title, u.username FROM changes c JOIN vn_rev vr ON c.id = vr.id JOIN users u ON u.id = c.requester WHERE vr.vid = ? AND c.rev = ?' :
        $t eq 'r' ? 'SELECT rr.title, u.username FROM changes c JOIN releases_rev rr ON c.id = rr.id JOIN users u ON u.id = c.requester WHERE rr.rid = ? AND c.rev = ?' :
        $t eq 'p' ? 'SELECT pr.name, u.username FROM changes c JOIN producers_rev pr ON c.id = pr.id JOIN users u ON u.id = c.requester WHERE pr.pid = ? AND c.rev = ?' :
                    'SELECT t.title, u.username FROM threads t JOIN threads_posts tp ON tp.tid = t.id JOIN users u ON u.id = tp.uid WHERE t.id = ? AND tp.num = ?'
      );
      $s->execute($id, $rev);
      my $r = $s->fetchrow_arrayref;
      next if !$r || ref($r) ne 'ARRAY';
      $_[KERNEL]->post(circ => privmsg => $_[ARG0], sprintf $ef, $t, $id, $rev,
        $rev == 1 ? 'New '.($t eq 'v' ? 'visual novel' : $t eq 'p' ? 'producer' : $t eq 'r' ? 'release': 'thread')
                  : ($t eq 't' ? 'Reply to' : 'Edit of'), $r->[0], 'By', $r->[1]
      );

   # option 3: documentation page
    } elsif($t eq 'd') {
      my $f = sprintf '/www/vndb/data/docs/%d', $id;
      open my $F, '<', $f or next;
      (my $title = <$F>) =~ s/^:TITLE://;
      chomp($title);

      if(!$rev) {
        $_[KERNEL]->post(circ => privmsg => $_[ARG0], sprintf $nf,
          'd', $id, $title);
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
      $_[KERNEL]->post(circ => privmsg => $_[ARG0], sprintf $sf,
        'd', $id, $rev, $title, '->', $sub);
    }
  }
}


sub ircnotify { # command, VNDBID
  $_[KERNEL]->yield(vndbid => $_ => $_[ARG1] => 1) for (@{$_[HEAP]{notify}});
  $_[KERNEL]->post(core => finish => $_[ARG0]);
}


sub shutdown {
  $_[KERNEL]->post(circ => shutdown => 'Byebye!');
}



# cmd_* commands: $arg, $dest, $nick

sub cmd_info {
  $_[KERNEL]->post(circ => privmsg => $_[DEST],
    'Hello, I am HMX-12 Multi v'.$VNDB::S{version}.' made by the great Yorhel!');
}


sub cmd_vndb {
  $_[KERNEL]->post(circ => privmsg => $_[DEST],
    'VNDB ~ The Visual Novel Database ~ http://vndb.org/');
}


sub cmd_list {
  return if $_[DEST] ne $_[HEAP]{o}{channel}[0];
  $_[KERNEL]->post(circ => privmsg => $_[DEST],
    $_[NICK].', this is not a warez channel!');
}


sub cmd_vn { # $arg = search string
  $_[ARG] =~ s/%//g;
  return $_[KERNEL]->post(circ => privmsg => $_[DEST], 'You forgot the search query, idiot~~!.') if !$_[ARG];
  
  my $q = $Multi::SQL->prepare(q|
    SELECT v.id
    FROM vn v
    JOIN vn_rev vr ON vr.id = v.latest
    WHERE vr.title ILIKE $1
       OR vr.alias ILIKE $1
       OR v.id IN(
         SELECT rv.vid
         FROM releases r
         JOIN releases_rev rr ON rr.id = r.latest
         JOIN releases_vn rv ON rv.rid = rr.id
         WHERE rr.title ILIKE $1
            OR rr.original ILIKE $1
       )
    ORDER BY vr.id
    LIMIT 6|);
  $q->execute('%'.$_[ARG].'%');

  my $res = $q->fetchall_arrayref([]);
  return $_[KERNEL]->post(circ => privmsg => $_[DEST],
    sprintf 'No results found for %s', $_[ARG]) if !@$res;
  return $_[KERNEL]->post(circ => privmsg => $_[DEST],
    sprintf 'Too many results found, see %s/v/search?q=%s',
      $VNDB::S{url}, uri_escape_utf8($_[ARG])) if @$res > 5;
  $_[KERNEL]->yield(vndbid => $_[DEST], join(' ', map 'v'.$_->[0], @$res), 1);
}


sub cmd_uptime {
  my $age = sub {
    return '...down!?' if !$_[0];
    my $d = int $_[0] / 86400;
    $_[0] %= 86400;
    my $h = int $_[0] / 3600;
    $_[0] %= 3600;
    my $m = int $_[0] / 60;
    $_[0] %= 60;
    return sprintf '%s%02d:%02d:%02d', $d ? $d.' day'.($d>1?'s':'').', ' : '', $h, $m, int $_[0];
  };

  open my $R, '<', '/proc/uptime';
  my $server = <$R> =~ /^\s*([0-9]+)/ ? $1 : 0;
  close $R;

  my $multi = time - $^T;

  my $http=0;
 # this should actually be done asynchronously... but I don't expect it to timeout
  if(my $req = Net::HTTP->new(Host => 'localhost', Timeout => 1)) {
    $req->write_request(GET => '/server-status?auto');
    my $d;
    $req->read_entity_body($d, 1024) if $req->read_response_headers;
    $http = $1 if $d =~ /Uptime:\s*([0-9]+)/i;
  }
  
  $_[KERNEL]->post(circ => privmsg => $_[DEST], $_) for (split /\n/, sprintf
    "Uptimes:\n  Server: %s\n  Multi:  %s\n  HTTP:   %s", map $age->($_), $server, $multi, $http);
}


sub cmd_notifications { # $arg = '' or 'on' or 'off'
  return unless &mymaster;
  if($_[ARG] =~ /^on$/i) {
    push @{$_[HEAP]{notify}}, $_[DEST] if !grep $_ eq $_[DEST], @{$_[HEAP]{notify}};
    $_[KERNEL]->post(circ => privmsg => $_[DEST], 'Notifications enabled.');
  } elsif($_[ARG] =~ /^off$/i) {
    $_[HEAP]{notify} = [ grep $_ ne $_[DEST], @{$_[HEAP]{notify}} ];
    $_[KERNEL]->post(circ => privmsg => $_[DEST], 'Notifications disabled.');
  } else {
    $_[KERNEL]->post(circ => privmsg => $_[DEST], sprintf 'Notifications %s, type !notifications %s to %s.',
      (grep $_ eq $_[DEST], @{$_[HEAP]{notify}}) ? ('enabled', 'off', 'disable') : ('disabled', 'on', 'enable'));
  }
}


sub cmd_say { # $arg = '[#chan ]text', no #chan = $dest
  return unless &mymaster;
  my $chan = $_[ARG] =~ s/^(#[a-zA-Z0-9-_.]+) // ? $1 : $_[DEST];
  $_[KERNEL]->post(circ => privmsg => $chan, $_[ARG]);
}


sub cmd_me { # same as cmd_say, but CTCP ACTION
  return unless &mymaster;
  my $chan = $_[ARG] =~ s/^(#[a-zA-Z0-9-_.]+) // ? $1 : $_[DEST];
  $_[KERNEL]->post(circ => ctcp => $chan, 'ACTION '.$_[ARG]);
}


sub cmd_cmd { # TODO: feedback?
  return unless &mymaster;
  $_[KERNEL]->post(core => queue => $_[ARG]);
  $_[KERNEL]->post(circ => privmsg => $_[DEST] => sprintf "Executing %s", $_[ARG]);
}


sub cmd_eval { # the evil cmd
  return unless &mymaster;
  $_[KERNEL]->post(circ => privmsg => $_[DEST], 'eval: '.$_)
    for (split /\r?\n/, eval($_[ARG])||$@);
}




# non-POE function, checks whether we should trust $nick
sub mymaster { # same @_ as the cmd_ functions
  if(!$_[HEAP]{irc}->is_channel_operator($_[HEAP]{o}{channel}[0], $_[ARG2])
    && !$_[HEAP]{irc}->is_channel_owner($_[HEAP]{o}{channel}[0], $_[ARG2])
    && !$_[HEAP]{irc}->is_channel_admin($_[HEAP]{o}{channel}[0], $_[ARG2])
  ) {
    $_[KERNEL]->post(circ => privmsg => $_[ARG1],
      ($_[ARG1]=~/^#/?$_[ARG2].', ':'').'You are not my master!');
    return 0;
  }
  return 1;
}

1;


