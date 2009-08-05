
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

use constant {
  USER => ARG0,
  DEST => ARG1,
  ARG  => ARG2,
  MASK => ARG3,

  # long subquery used in several places
  GETBOARDS => q{array_to_string(array(
      SELECT tb.type||COALESCE(':'||COALESCE(u.username, vr.title, pr.name), '')
      FROM threads_boards tb
      LEFT JOIN vn v ON tb.type = 'v' AND v.id = tb.iid
      LEFT JOIN vn_rev vr ON vr.id = v.latest
      LEFT JOIN producers p ON tb.type = 'p' AND p.id = tb.iid
      LEFT JOIN producers_rev pr ON pr.id = p.latest
      LEFT JOIN users u ON tb.type = 'u' AND u.id = tb.iid
      WHERE tb.tid = t.id
      ORDER BY tb.type, tb.iid
    ), ', ') AS boards},
};

my $irc;


sub spawn {
  my $p = shift;
  $irc = POE::Component::IRC::State->spawn(
    alias => 'circ',
    NoDNS => 1,
  );
  POE::Session->create(
    package_states => [
      $p => [qw|
        _start shutdown irc_001 irc_public irc_ctcp_action irc_msg command reply
        cmd_info cmd_list cmd_uptime cmd_vn cmd_vn_results cmd_quote cmd_quote_result cmd_say cmd_me
        cmd_eval cmd_die cmd_post vndbid formatid
      |],
    ],
    heap => {
      nick => 'Multi_test'.$$,
      server => 'irc.synirc.net',
      ircname => 'VNDB.org Multi',
      channels => [ '#vndb' ],
      masters => [ 'yorhel!*@*' ],
      @_,
      log => {},
      privpers => {},
      notify => [],
      commands => {
        info     => 0,   # argument = authentication level/flags,
        list     => 0,   #   0: everyone,
        uptime   => 0,   #   1: only OPs in the first channel listed in @channels
        vn       => 0,   #   2: only users matching the mask in @masters
        quote    => 0,   #  |8: has to be addressed to the bot (e.g. 'Multi: eval' instead of '!eval')
        say      => 1|8,
        me       => 1|8,
        eval     => 2|8,
        die      => 2|8,
        post     => 2|8,
      },
    }
  );
}


sub _start {
  $_[KERNEL]->alias_set('irc');

  $irc->plugin_add(
    Logger => POE::Component::IRC::Plugin::Logger->new(
      Path => $VNDB::M{log_dir},
      Private => 0,
      Public => 1,
  ));
  $irc->plugin_add(
    Connector => POE::Component::IRC::Plugin::Connector->new()
  );
  $irc->plugin_add(
    CTCP => POE::Component::IRC::Plugin::CTCP->new(
      version => $_[HEAP]{ircname}.' v'.$VNDB::S{version},
      userinfo => $_[HEAP]{ircname},
  ));
  if($_[HEAP]{pass}) {
    require POE::Component::IRC::Plugin::NickServID;
    $irc->plugin_add(
      NickServID => POE::Component::IRC::Plugin::NickServID->new(
        Password => $_[HEAP]{pass}
    ))
  }
  if($_[HEAP]{console}) {
    require POE::Component::IRC::Plugin::Console;
    $irc->plugin_add(
      Console => POE::Component::IRC::Plugin::Console->new(
        bindport => 3030,
        password => $_[HEAP]{console}
    ))
  }

  $irc->yield(register => 'all');
  $irc->yield(connect => {
    Nick  => $_[HEAP]{nick},
    Username => 'u1',
    Ircname => $_[HEAP]{ircname},
    Server => $_[HEAP]{server},
  });

  $_[KERNEL]->sig(shutdown => 'shutdown');
}


sub shutdown {
  $irc->yield(shutdown => $_[ARG1]);
  $_[KERNEL]->alias_remove('irc');
}


sub irc_001 {
  $irc->yield(join => $_) for (@{$_[HEAP]{channels}});
  $_[KERNEL]->call(core => log => 'Connected to IRC');
}


sub irc_public { # mask, dest, msg
  return if $_[KERNEL]->call($_[SESSION] => command => @_[ARG0..$#_]);
  $_[KERNEL]->call($_[SESSION] => vndbid => $_[ARG1], $_[ARG2]);
}


sub irc_ctcp_action { # mask, dest, msg
  $_[KERNEL]->call($_[SESSION] => vndbid => $_[ARG1], $_[ARG2]);
}


sub irc_msg { # mask, dest, msg
  return if $_[KERNEL]->call($_[SESSION] => command => $_[ARG0], [scalar parse_user($_[ARG0])], $_[ARG2]);

  my $usr = parse_user($_[ARG0]);
  return if ($_[HEAP]{privpers}{$usr}||0) > time-300;
  $irc->yield(notice => $usr, 'I am not human, join #vndb or PM Yorhel if you need something.');
  $_[HEAP]{privpers}{$usr} = time;
}


sub command { # mask, dest, msg
  my($mask, $dest, $msg) = @_[ARG0..$#_];

  my $me = $irc->nick_name();
  my $addressed = $dest->[0] !~ /^#/ || $msg =~ s/^\s*\Q$me\E[:,;.!?~]?\s*//;
  return 0 if !$addressed && !($msg =~ s/^\s*!//);

  return 0 if $msg !~ /^([a-z]+)(?:\s+(.+))?$/;
  my($cmd, $arg) = ($1, $2);
  return 0 if !exists $_[HEAP]{commands}{$cmd} || ($_[HEAP]{commands}{$cmd} & 8) && !$addressed;

  my $usr = parse_user($mask);
  return $_[KERNEL]->yield(reply => $dest,
      $dest eq $_[HEAP]{channels}[0] ? 'Only OPs can do that!' : "Only $_[HEAP]{channel}[0] OPs can do that!", $usr) || 1
    if $_[HEAP]{commands}{$cmd} == 1 && !$irc->is_channel_operator($_[HEAP]{channels}[0], $usr);
  return $_[KERNEL]->yield(reply => $dest, 'You are not my master!', $usr) || 1
    if $_[HEAP]{commands}{$cmd} == 2 && !grep matches_mask($_, $mask), @{$_[HEAP]{masters}};

  return $_[KERNEL]->yield('cmd_'.$cmd, $usr, $dest, $arg, $mask) || 1;
}


# convenience function
sub reply { # target, msg [, mask/user]
  my $usr = $_[ARG0][0] =~ /^#/ && parse_user($_[ARG2]);
  $irc->yield($_[ARG0][0] =~ /^#/ ? 'privmsg' : 'notice', $_[ARG0], ($usr ? "$usr, " : '').$_[ARG1]);
}




#
#  I R C   C O M M A N D S
#


sub cmd_info {
  $_[KERNEL]->yield(reply => $_[DEST],
    'Hi! I am HMX-12 Multi '.$VNDB::S{version}.', the IRC bot of '.$VNDB::S{url}.'/, written by the great Yorhel!');
}


sub cmd_list {
  $_[KERNEL]->yield(reply => $_[DEST],
    $_[DEST][0] =~ /^#/ ? 'This is not a warez channel!' : 'I am not a warez bot!', $_[USER]);
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

  $_[KERNEL]->yield(reply => $_[DEST], sprintf 'Server uptime: %s -- mine: %s', $age->($server), $age->($multi));
}


sub cmd_vn {
  (my $q = $_[ARG]||'') =~ s/%//g;
  return $_[KERNEL]->yield(reply => $_[DEST], 'You forgot the search query, dummy~~!', $_[USER]) if !$q;

  $_[KERNEL]->post(pg => query => q|
    SELECT 'v'::text AS type, v.id, vr.title
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
    ORDER BY vr.title
    LIMIT 6|, [ "%$q%" ], 'cmd_vn_results', \@_);
}


sub cmd_vn_results { # num, res, \@_
  return $_[KERNEL]->yield(reply => $_[ARG2][DEST], 'No results found', $_[ARG2][USER]) if $_[ARG0] < 1;
  return $_[KERNEL]->yield(reply => $_[ARG2][DEST], sprintf(
      'Too many results found, see %s/v/all?q=%s', $VNDB::S{url}, uri_escape_utf8($_[ARG2][ARG])
    ), $_[ARG2][USER]) if $_[ARG0] > 5;
  $_[KERNEL]->yield(formatid => $_[ARG0], $_[ARG1], $_[ARG2][DEST]);
}


sub cmd_quote {
  $_[KERNEL]->post(pg => query => q|SELECT quote FROM quotes ORDER BY random() LIMIT 1|, undef, 'cmd_quote_result', $_[DEST]);
}


sub cmd_quote_result { # 1, res, dest
  $_[KERNEL]->yield(reply => $_[ARG2] => $_[ARG1][0]{quote}) if $_[ARG0] > 0;
}


sub cmd_say {
  my $chan = $_[ARG] =~ s/^(#[a-zA-Z0-9-_.]+) // ? $1 : $_[DEST];
  $irc->yield(privmsg => $chan, $_[ARG]);
}


sub cmd_me {
  my $chan = $_[ARG] =~ s/^(#[a-zA-Z0-9-_.]+) // ? $1 : $_[DEST];
  $irc->yield(ctcp => $chan, 'ACTION '.$_[ARG]);
}


sub cmd_eval {
  $_[KERNEL]->yield(reply => $_[DEST], 'eval: '.$_)
    for (split /\r?\n/, eval($_[ARG])||$@);
}


sub cmd_die {
  $irc->yield(ctcp => $_[DEST] => 'ACTION dies');
  $_[KERNEL]->signal(core => shutdown => "Killed on IRC by $_[USER]");
}


sub cmd_post {
  $_[KERNEL]->yield(reply => $_[DEST], $_[KERNEL]->post(split /\s+/, $_[ARG])
    ? 'Sent your message to the post office, it will be processed shortly!'
    : "Oh no! The post office wouldn't accept your message! Wrong destination address?", $_[USER]);
}




#
#  D B   I T E M   L I N K S
#


sub vndbid { # dest, msg
  my($dest, $msg) = @_[ARG0, ARG1];

  $_[HEAP]{log}{$_} < time-60 and delete $_[HEAP]{log}{$_}
    for (keys %{$_[HEAP]{log}});

  my @id; # [ type, id, ref ]
  for (split /[, ]/, $msg) {
    next if length > 15 or m{[a-z]{3,6}://}i; # weed out URLs and too long things
    push @id, /^(?:.*[^\w]|)([dvprt])([1-9][0-9]*)\.([1-9][0-9]*)(?:[^\w].*|)$/ ? [ $1, $2, $3 ] # x+.+
           :  /^(?:.*[^\w]|)([dvprtug])([1-9][0-9]*)(?:[^\w].*|)$/ ? [ $1, $2, 0 ] : ();         # x+
  }

  for (@id) {
    my($t, $id, $rev) = @$_;

    next if $_[HEAP]{log}{$t.$id.'.'.$rev};
    $_[HEAP]{log}{$t.$id.'.'.$rev} = time;

    # plain vn/user/producer/thread/tag/release
    $_[KERNEL]->post(pg => query => 'SELECT ?::text AS type, ?::integer AS id, '.(
      $t eq 'v' ? 'vr.title FROM vn_rev vr JOIN vn v ON v.latest = vr.id WHERE v.id = ?' :
      $t eq 'u' ? 'u.username AS title FROM users u WHERE u.id = ?' :
      $t eq 'p' ? 'pr.name AS title FROM producers_rev pr JOIN producers p ON p.latest = pr.id WHERE p.id = ?' :
      $t eq 't' ? 'title, '.GETBOARDS.' FROM threads t WHERE id = ?' :
      $t eq 'g' ? 'name AS title FROM tags WHERE id = ?' :
                  'rr.title FROM releases_rev rr JOIN releases r ON r.latest = rr.id WHERE r.id = ?'),
      [ $t, $id, $id ], 'formatid', $dest
    ) if !$rev && $t =~ /[vprtug]/;

    # edit/insert of vn/release/producer or discussion board post
    $_[KERNEL]->post(pg => query => 'SELECT ?::text AS type, ?::integer AS id, ?::integer AS rev, '.(
      $t eq 'v' ? 'vr.title, u.username, c.comments FROM changes c JOIN vn_rev vr ON c.id = vr.id JOIN users u ON u.id = c.requester WHERE vr.vid = ? AND c.rev = ?' :
      $t eq 'r' ? 'rr.title, u.username, c.comments FROM changes c JOIN releases_rev rr ON c.id = rr.id JOIN users u ON u.id = c.requester WHERE rr.rid = ? AND c.rev = ?' :
      $t eq 'p' ? 'pr.name AS title, u.username, c.comments FROM changes c JOIN producers_rev pr ON c.id = pr.id JOIN users u ON u.id = c.requester WHERE pr.pid = ? AND c.rev = ?' :
                  't.title, u.username, '.GETBOARDS.' FROM threads t JOIN threads_posts tp ON tp.tid = t.id JOIN users u ON u.id = tp.uid WHERE t.id = ? AND tp.num = ?'),
      [ $t, $id, $rev, $id, $rev], 'formatid', $dest
    ) if $rev && $t =~ /[vprt]/;

    # documentation page (need to parse the doc pages manually here)
    if($t eq 'd') {
      my $f = sprintf $VNDB::ROOT.'/data/docs/%d', $id;
      my($title, $sec, $sub) = (undef, 0);
      open my $F, '<', $f or next;
      while(<$F>) {
        chomp;
        $title = $1 if /^:TITLE:(.+)$/;
        $sub = $1 if $rev && /^:SUB:(.+)$/ && ++$sec == $rev;
      }
      close $F;
      next if $rev && !$sub;
      $_[KERNEL]->yield(formatid => 1, [{type => 'd', id => $id, title => $title, rev => $rev, section => $sub}], $dest);
    }
  }
}


# formats and posts database items listed in @res, where each item is a hashref with:
#   type      database item in [dvprtug]
#   id        database id
#   title     main name or title of the DB entry
#   rev       (optional) revision, post number or section number
#   username  (optional) relevant username
#   section   (optional, for d+.+) section title
#   boards    (optional) board titles the thread has been posted in
#   comments  (optional) edit summary
sub formatid {
  my($num, $res, $dest) = @_[ARG0..$#_];

  # only the types for which creation/edit announcements matter
  my %types = (
    v => 'visual novel',
    p => 'producer',
    r => 'release',
    g => 'tag',
    t => 'thread',
  );

  for (@$res) {
    my $id = $_->{type}.$_->{id} . ($_->{rev} ? '.'.$_->{rev} : '');

    # (always) [x+.+]
    my @msg = (
      BOLD.RED.'['.NORMAL.BOLD.$id.RED.']'.NORMAL
    );

    # (only if username key is present) Edit of / New item / reply to / whatever
    push @msg, RED.(
      ($_->{rev}||1) == 1 ? 'New '.$types{$_->{type}} :
      $_->{type} eq 't' ? 'Reply to' : 'Edit of'
    ).NORMAL if $_->{username};

    # (always) main title
    push @msg, $_->{title};

    # (only if boards key is present) Posted in [boards]
    push @msg, RED.'Posted in'.NORMAL.' '.$_->{boards} if $_->{boards};

    # (only if username key is present) By [username]
    push @msg, RED.'By'.NORMAL.' '.$_->{username} if $_->{username};

    # (only if comments key is present) Summary:
    push @msg, RED.'Summary:'.NORMAL.' '.(
      length $_->{comments} > 40 ? substr($_->{comments}, 0, 37).'...' : $_->{comments}
    ) if defined $_->{comments};

    # (for d+.+) -> section title
    push @msg, RED.'->'.NORMAL.' '.$_->{section} if $_->{section};

    # (always) @ URL
    push @msg, RED.'@ '.NORMAL.LIGHT_GREY.$VNDB::S{url}.'/'.$id.NORMAL;

    # now post it
    $_[KERNEL]->yield(reply => $dest, join ' ',  @msg);
  }
}


1;


__END__

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


