
#
#  Multi::IRC  -  HMX-12 Multi, the IRC bot
#

package Multi::IRC;

use strict;
use warnings;
use Multi::Core;
use AnyEvent::IRC::Client;
use AnyEvent::IRC::Util 'prefix_nick';
use VNDBUtil 'normalize_query';
use TUWF::Misc 'uri_escape';
use POSIX 'strftime';
use Encode 'decode_utf8', 'encode_utf8';


# long subquery used in several places
my $GETBOARDS = q{array_to_string(array(
      SELECT tb.type||COALESCE(':'||COALESCE(u.username, vr.title, pr.name), '')
      FROM threads_boards tb
      LEFT JOIN vn v ON tb.type = 'v' AND v.id = tb.iid
      LEFT JOIN vn_rev vr ON vr.id = v.latest
      LEFT JOIN producers p ON tb.type = 'p' AND p.id = tb.iid
      LEFT JOIN producers_rev pr ON pr.id = p.latest
      LEFT JOIN users u ON tb.type = 'u' AND u.id = tb.iid
      WHERE tb.tid = t.id
      ORDER BY tb.type, tb.iid
    ), ', ') AS boards};

my $LIGHT_BLUE = "\x0312";
my $RED = "\x0304";
my $BOLD = "\x02";
my $NORMAL = "\x0f";
my $LIGHT_GREY = "\x0315";


my $irc;
my $connecttimer;
my @quotew;
my %lastnotify;


my %O = (
  nick => 'Multi_test'.$$,
  server => 'irc.synirc.net',
  port => 6667,
  ircname => 'VNDB.org Multi',
  channels => [ '#vndb' ],
  masters => [ 'Yorhel!~Ayo@your.hell' ],
  throt_sameid => [ 60, 0 ], # spamming the same vndbid
  throt_vndbid => [ 5,  5 ], # spamming vndbids in general
  throt_cmd    => [ 10, 2 ], # handling commands from a single user
);


sub run {
  shift;
  %O = (%O, @_);
  $irc = AnyEvent::IRC::Client->new;

  set_cbs();
  set_logger();
  set_quotew($_) for (0..$#{$O{channels}});
  set_notify();
  ircconnect();
}


sub unload {
  @quotew = ();
  # TODO: Wait until we've nicely disconnected?
  $irc->disconnect('Closing...');
  undef $connecttimer;
  undef $irc;
}


sub ircconnect {
  $irc->connect($O{server}, $O{port}, { nick => $O{nick}, user => 'u1', real => $O{ircname} });
}


sub reconnect {
  $connecttimer = AE::timer 60, 0, sub {
    ircconnect();
    undef $connecttimer;
  };
}


sub send_quote {
  my $chan = shift;
  pg_cmd 'SELECT quote FROM quotes ORDER BY random() LIMIT 1', undef, sub {
    return if pg_expect $_[0], 1 or !$_[0]->nRows;
    $irc->send_msg(PRIVMSG => $chan, encode_utf8 $_[0]->value(0,0));
  };
}


sub set_quotew {
  my $idx = shift;
  $quotew[$idx] = AE::timer +(4*3600)+rand()*(30*3600), 0, sub {
    send_quote($O{channels}[$idx]) if $irc->registered;
    set_quotew($idx);
  };
}


sub set_cbs {
  $irc->reg_cb(connect => sub {
    return if !$_[1];
    AE::log warn => "IRC connection error: $_[1]";
    reconnect();
  });
  $irc->reg_cb(registered => sub {
    AE::log info => 'Connected to IRC';
    $irc->enable_ping(60);
    $irc->send_msg(PRIVMSG => NickServ => "IDENTIFY $O{pass}") if $O{pass} && $irc->is_my_nick($O{nick});
    $irc->send_msg(JOIN => join ',', @{$O{channels}});
  });

  $irc->reg_cb(disconnect => sub {
    AE::log info => 'Disconnected from IRC';
    reconnect();
  });

  #$irc->reg_cb(read => sub {
  #  require Data::Dumper;
  #  AE::log trace => "Received: ".Data::Dumper::Dumper($_[1]);
  #});

  $irc->ctcp_auto_reply(VERSION => ['VERSION', "$O{ircname}:$VNDB::S{version}:AnyEvent"]);
  $irc->ctcp_auto_reply(USERINFO => ['USERINFO', ":$O{ircname}"]);

  $irc->reg_cb(publicmsg => sub { my @a = (prefix_nick($_[2]->{prefix}), $_[1], $_[2]->{params}[1]); command(@a) || vndbid(@a); });
  $irc->reg_cb(privatemsg => sub { my $n = prefix_nick($_[2]->{prefix}); command($n, $n, $_[2]->{params}[1]) });
  $irc->reg_cb(ctcp_action => sub { vndbid($_[1], $_[2], $_[3]) });
}


sub set_logger {
  # Uses the same logging format as Component::IRC::Plugin::Logger
  # Only logs channel chat, joins, quits, kicks and topic/nick changes
  my $l = sub {
    my($chan, $msg, @arg) = @_;
    return if !grep $chan eq $_, @{$O{channels}};
    open my $F, '>>', "$VNDB::M{log_dir}/$chan" or die $!;
    print $F strftime('%Y-%m-%d %H:%M:%S', localtime).' '.sprintf($msg, @arg)."\n";
  };

  $irc->reg_cb(join => sub {
    my(undef, $nick, $chan) = @_;
    $l->($chan, '--> %s (%s) joins %s', $nick, $irc->nick_ident($nick)||'', $chan);
  });
  $irc->reg_cb(part => sub {
    my(undef, $nick, $chan, undef $msg) = @_;
    $l->($chan, '<-- %s (%s) quits (%s)', $nick, $irc->nick_ident($nick)||'', $msg);
  });
  $irc->reg_cb(kick => sub {
    my(undef, $nick, $chan, undef, $msg, $kicker) = @_;
    $l->($chan, '<-- %s kicks %s from %s (%s)', $kicker, $nick, $chan, $msg);
  });
  $irc->reg_cb(channel_change => sub {
    my(undef, undef, $chan, $old, $new) = @_;
    $l->($chan, '--- %s is now known as %s', $old, $new);
  });
  $irc->reg_cb(channel_topic => sub {
    my(undef, $chan, $topic, $nick) = @_;
    $l->($chan, '--- %s changes the topic to: %s', $nick||'server', $topic);
  });
  $irc->reg_cb(publicmsg => sub {
    my(undef, $chan, $msg) = @_;
    $l->($chan, '<%s> %s', prefix_nick($msg->{prefix}), $msg->{params}[1]);
  });
  $irc->reg_cb(ctcp_action => sub {
    my(undef, $nick, $chan, $msg) = @_;
    $l->($chan, '* %s %s', $nick, $msg);
  });
  $irc->reg_cb(sent => sub {
    my(undef, $prefix, $cmd, @args) = @_;
    # XXX: Doesn't handle CTCP ACTION
    $l->($args[0], '<%s> %s', $irc->nick(), $args[1]) if lc $cmd eq 'privmsg';
  });
}


sub set_notify {
  pg_cmd q{SELECT
    (SELECT id FROM changes ORDER BY id DESC LIMIT 1) AS rev,
    (SELECT id FROM tags ORDER BY id DESC LIMIT 1) AS tag,
    (SELECT id FROM traits ORDER BY id DESC LIMIT 1) AS trait,
    (SELECT date FROM threads_posts ORDER BY date DESC LIMIT 1) AS post
  }, undef, sub {
    return if pg_expect $_[0], 1;
    %lastnotify = %{($_[0]->rowsAsHashes())[0]};
    push_watcher pg->listen($_, on_notify => \&notify) for qw{newrevision newpost newtag newtrait};
  };
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
  my($res, $dest, $notify) = @_;

  my $c = $notify ? $LIGHT_BLUE : $RED;

  # only the types for which creation/edit announcements matter
  my %types = (
    v => 'visual novel',
    p => 'producer',
    r => 'release',
    c => 'character',
    s => 'staff',
    g => 'tag',
    i => 'trait',
    t => 'thread',
  );

  for (@$res) {
    my $id = $_->{type}.$_->{id} . ($_->{rev} ? '.'.$_->{rev} : '');

    # (always) [x+.+]
    my @msg = ("$BOLD$c"."[$NORMAL$BOLD$id$c]$NORMAL");

    # (only if username key is present) Edit of / New item / reply to / whatever
    push @msg, $c.(
      ($_->{rev}||1) == 1 ? "New $types{$_->{type}}" :
      $_->{type} eq 't' ? 'Reply to' : 'Edit of'
    ).$NORMAL if $_->{username};

    # (always) main title
    push @msg, $_->{title};

    # (only if boards key is present) Posted in [boards]
    push @msg, $c."Posted in$NORMAL $_->{boards}" if $_->{boards};

    # (only if username key is present) By [username]
    push @msg, $c."By$NORMAL $_->{username}" if $_->{username};

    # (only if comments key is present) Summary:
    $_->{comments} =~ s/\n/ /g if $_->{comments};
    push @msg, $c."Summary:$NORMAL ".(
      length $_->{comments} > 40 ? substr($_->{comments}, 0, 37).'...' : $_->{comments}
    ) if defined $_->{comments};

    # (for d+.+) -> section title
    push @msg, $c."->$NORMAL $_->{section}" if $_->{section};

    # (always) @ URL
    push @msg, $c."@ $NORMAL$LIGHT_GREY$VNDB::S{url}/$id$NORMAL";

    # now post it
    $irc->send_msg(PRIVMSG => $dest, encode_utf8 join ' ', @msg);
  }
}


sub handleid {
  my($chan, $t, $id, $rev) = @_;

  # Some common exceptions
  return if grep "$t$id$rev" eq $_, qw|v1 v2 v3 v4 u2 i3 i5 i7|;

  return if throttle $O{throt_vndbid}, 'irc_vndbid';
  return if throttle $O{throt_sameid}, "irc_sameid_$t$id$rev";

  my $c = sub {
    return if pg_expect $_[0], 1;
    formatid([$_[0]->rowsAsHashes], $chan, 0) if $_[0]->nRows;
  };

  # plain vn/user/producer/thread/tag/trait/release
  pg_cmd 'SELECT $1::text AS type, $2::integer AS id, '.(
    $t eq 'v' ? 'vr.title FROM vn_rev vr JOIN vn v ON v.latest = vr.id WHERE v.id = $2' :
    $t eq 'u' ? 'u.username AS title FROM users u WHERE u.id = $2' :
    $t eq 'p' ? 'pr.name AS title FROM producers_rev pr JOIN producers p ON p.latest = pr.id WHERE p.id = $2' :
    $t eq 'c' ? 'cr.name AS title FROM chars_rev cr JOIN chars c ON c.latest = cr.id WHERE c.id = $2' :
    $t eq 's' ? 'sa.name AS title FROM staff_rev sr JOIN staff s ON s.latest = sr.id JOIN staff_alias sa ON sa.id = sr.aid AND sa.rid = s.latest WHERE s.id = $2' :
    $t eq 't' ? 'title, '.$GETBOARDS.' FROM threads t WHERE id = $2' :
    $t eq 'g' ? 'name AS title FROM tags WHERE id = $2' :
    $t eq 'i' ? 'name AS title FROM traits WHERE id = $2' :
                'rr.title FROM releases_rev rr JOIN releases r ON r.latest = rr.id WHERE r.id = $2'),
    [ $t, $id ], $c if !$rev && $t =~ /[vprtugics]/;

  # edit/insert of vn/release/producer or discussion board post
  pg_cmd 'SELECT $1::text AS type, $2::integer AS id, $3::integer AS rev, '.(
    $t eq 'v' ? 'vr.title, u.username, c.comments FROM changes c JOIN vn_rev vr ON c.id = vr.id JOIN users u ON u.id = c.requester WHERE vr.vid = $2 AND c.rev = $3' :
    $t eq 'r' ? 'rr.title, u.username, c.comments FROM changes c JOIN releases_rev rr ON c.id = rr.id JOIN users u ON u.id = c.requester WHERE rr.rid = $2 AND c.rev = $3' :
    $t eq 'p' ? 'pr.name AS title, u.username, c.comments FROM changes c JOIN producers_rev pr ON c.id = pr.id JOIN users u ON u.id = c.requester WHERE pr.pid = $2 AND c.rev = $3' :
    $t eq 'c' ? 'cr.name AS title, u.username, h.comments FROM changes h JOIN chars_rev cr ON h.id = cr.id JOIN users u ON u.id = h.requester WHERE cr.cid = $2 AND h.rev = $3' :
    $t eq 's' ? 'sa.name AS title, u.username, c.comments FROM changes c JOIN staff_rev sr ON c.id = sr.id JOIN users u ON u.id = c.requester JOIN staff_alias sa ON sa.id = sr.aid AND sa.rid = sr.id WHERE sr.sid = $2 AND c.rev = $3' :
                't.title, u.username, '.$GETBOARDS.' FROM threads t JOIN threads_posts tp ON tp.tid = t.id JOIN users u ON u.id = tp.uid WHERE t.id = $2 AND tp.num = $3'),
    [ $t, $id, $rev], $c if $rev && $t =~ /[vprtcs]/;

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
    formatid([{type => 'd', id => $id, title => $title, rev => $rev, section => $sub}], $chan, 0);
  }
}


sub vndbid {
  my($nick, $chan, $msg) = @_;

  return if $msg =~ /^\Q$BOLD/; # Never reply to another multi's spam. And ignore idiots who use bold. :D

  my @id; # [ type, id, ref ]
  for (split /[, ]/, $msg) {
    next if length > 15 or m{[a-z]{3,6}://}i; # weed out URLs and too long things
    push @id, /^(?:.*[^\w]|)([dvprtcs])([1-9][0-9]*)\.([1-9][0-9]*)(?:[^\w].*|)$/ ? [ $1, $2, $3 ] # x+.+
            : /^(?:.*[^\w]|)([dvprtugics])([1-9][0-9]*)(?:[^\w].*|)$/ ? [ $1, $2, '' ] : ();       # x+
  }
  handleid($chan, @$_) for @id;
}




sub notify {
  my(undef, $sel) = @_;
  my $k = {qw|newrevision rev  newpost post  newtrait trait  newtag tag|}->{$sel};
  return if !$k || !$lastnotify{$k};

  my $q = {
  rev => q{
    SELECT c.type, c.rev, c.comments, c.id AS lastid,
      COALESCE(vr.vid, rr.rid, pr.pid, cr.cid, sr.sid) AS id, COALESCE(vr.title, rr.title, pr.name, cr.name, sa.name) AS title, u.username
    FROM changes c
    LEFT JOIN vn_rev vr ON c.type = 'v' AND c.id = vr.id
    LEFT JOIN releases_rev rr ON c.type = 'r' AND c.id = rr.id
    LEFT JOIN producers_rev pr ON c.type = 'p' AND c.id = pr.id
    LEFT JOIN chars_rev cr ON c.type = 'c' AND c.id = cr.id
    LEFT JOIN staff_rev sr ON c.type = 's' AND c.id = sr.id
    LEFT JOIN staff_alias sa ON c.type = 's' AND sa.id = sr.aid AND sa.rid = c.id
    JOIN users u ON u.id = c.requester
    WHERE c.id > $1 AND c.requester <> 1
    ORDER BY c.id},
  post => q{
    SELECT 't' AS type, tp.tid AS id, tp.num AS rev, t.title, u.username, tp.date AS lastid, }.$GETBOARDS.q{
    FROM threads_posts tp
    JOIN threads t ON t.id = tp.tid
    JOIN users u ON u.id = tp.uid
    WHERE tp.date > $1 AND tp.num = 1
    ORDER BY tp.date},
  trait => q{
    SELECT 'i' AS type, t.id, t.name AS title, u.username, t.id AS lastid
    FROM traits t
    JOIN users u ON u.id = t.addedby
    WHERE t.id > $1
    ORDER BY t.id},
  tag => q{
    SELECT 'g' AS type, t.id, t.name AS title, u.username, t.id AS lastid
    FROM tags t
    JOIN users u ON u.id = t.addedby
    WHERE t.id > $1
    ORDER BY t.id}
  }->{$k};

  pg_cmd $q, [ $lastnotify{$k} ], sub {
    my $res = shift;
    return if pg_expect $res, 1;
    my @res = $res->rowsAsHashes;
    $lastnotify{$k} = $_->{lastid} for (@res);
    formatid \@res, $O{channels}[0], 1;
  };
}




# command => [ admin_only, need_bot_prefix, sub->(nick, chan, cmd_args) ]
my %cmds = (

info => [ 0, 0, sub {
  $irc->send_msg(PRIVMSG => $_[1], 
    'Hi! I am HMX-12 Multi '.$VNDB::S{version}.', the IRC bot of '.$VNDB::S{url}.'/, written by the great master Yorhel!');
}],

list => [ 0, 0, sub {
  $irc->send_msg(PRIVMSG => $_[1],
    $irc->is_channel_name($_[1]) ? 'This is not a warez channel!' : 'I am not a warez bot!');
}],

quote => [ 0, 0, sub { send_quote($_[1]) } ],

vn => [ 0, 0, sub {
  my($nick, $chan, $q) = @_;
  return $irc->send_msg(PRIVMSG => $chan, 'You forgot the search query, dummy~~!') if !$q;

  my @q = normalize_query($q);
  return $irc->send_msg(PRIVMSG => $chan,
    "Couldn't do anything with that search query, you might want to add quotes or use longer words.") if !@q;

  my $w = join ' AND ', map "v.c_search LIKE \$$_", 1..@q;
  pg_cmd qq{
    SELECT 'v'::text AS type, v.id, vr.title
      FROM vn v
      JOIN vn_rev vr ON vr.id = v.latest
     WHERE NOT v.hidden AND $w
     ORDER BY vr.title
     LIMIT 6
  }, [ map "%$_%", @q ], sub {
    my $res = shift;
    return if pg_expect $res, 1;
    return $irc->send_msg(PRIVMSG => $chan, 'No visual novels found.') if !$res->nRows;
    return $irc->send_msg(PRIVMSG => $chan,
      sprintf 'Too many results found, see %s/v/all?q=%s', $VNDB::S{url}, uri_escape($q)) if $res->nRows > 5;
    formatid([$res->rowsAsHashes()], $chan, 0);
  };
}],

p => [ 0, 0, sub {
  my($nick, $chan, $q) = @_;
  return $irc->send_msg(PRIVMSG => $chan, 'You forgot the search query, dummy~~!') if !$q;
  pg_cmd q{
    SELECT 'p'::text AS type, p.id, pr.name AS title
    FROM producers p
    JOIN producers_rev pr ON pr.id = p.latest
    WHERE p.hidden = FALSE AND (pr.name ILIKE $1 OR pr.original ILIKE $1 OR pr.alias ILIKE $1)
    ORDER BY pr.name
    LIMIT 6
  }, [ "%$q%" ], sub {
    my $res = shift;
    return if pg_expect $res, 1;
    return $irc->send_msg(PRIVMSG => $chan, 'No producers novels found.') if !$res->nRows;
    return $irc->send_msg(PRIVMSG => $chan,
      sprintf 'Too many results found, see %s/p/all?q=%s', $VNDB::S{url}, uri_escape($q)) if $res->nRows > 5;
    formatid([$res->rowsAsHashes()], $chan, 0);
  };
}],

scr => [ 0, 0, sub {
  my($nick, $chan, $q) = @_;
  return $irc->send_msg(PRIVMSG => $chan.
     q|Sorry, I failed to comprehend which screenshot you'd like me to lookup for you,|
    .q| please understand that Yorhel was not willing to supply me with mind reading capabilities.|)
    if $q !~ /([0-9]+)\.jpg/;
  $q = $1;
  pg_cmd q{
    SELECT 'v'::text AS type, v.id, vr.title
      FROM vn v
      JOIN vn_rev vr ON vr.id = v.latest
      JOIN vn_rev vr2 ON vr2.vid = v.id
      JOIN vn_screenshots vs ON vs.vid = vr2.id
     WHERE vs.scr = $1 LIMIT 1
  }, [ $q ], sub {
    my $res = shift;
    return if pg_expect $res, 1;
    return $irc->send_msg(PRIVMSG => $chan, "Couldn't find a VN with that screenshot ID.") if !$res->nRows;
    formatid([$res->rowsAsHashes()], $chan, 0);
  };
}],

eval => [ 1, 1, sub {
  my @l = split /\r?\n/, eval($_[2])||$@;
  if(@l > 5 || length(join ' ', @l) > 400) {
    $irc->send_msg(PRIVMSG => $_[1], 'Output too large, refusing to spam chat (and too lazy to use a pastebin).');
  } else {
    $irc->send_msg(PRIVMSG => $_[1], encode_utf8("eval: ".$_)) for @l;
  }
}],

die => [ 1, 1, sub {
  kill 'TERM', 0;
}],
);


# Returns 1 if there was a valid command (or something that looked like it)
sub command {
  my($nick, $chan, $msg) = @_;
  $msg = decode_utf8($msg);

  my $me = $irc->nick();
  my $addressed = !$irc->is_channel_name($chan) || $msg =~ s/^\s*\Q$me\E[:,;.!?~]?\s*//;
  return 0 if !$addressed && !($msg =~ s/^\s*!//);

  return 0 if $msg !~ /^([a-z]+)(?:\s+(.+))?$/;
  my($cmd, $arg) = ($cmds{$1}, $2);

  return 0 if !$cmd && !$addressed;
  return 0 if $cmd && $cmd->[1] && !$addressed;

  return 1 if throttle $O{throt_cmd}, "irc_cmd_$nick";

  if(!$cmd && $addressed) {
    $irc->send_msg(PRIVMSG => $chan, 'Please make sense.');
    return 1;
  }

  my $id = lc $irc->nick_ident($nick);
  if($cmd->[1] && !grep $id eq lc $_, @{$O{masters}}) {
    $irc->send_msg(PRIVMSG => $chan, 'I am not your master!');
    return 1;
  }
  $cmd->[2]->($nick, $chan, $arg);
  return 1;
}

1;
