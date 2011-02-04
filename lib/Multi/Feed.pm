
#
#  Multi::Feed  -  Generates and updates Atom feeds
#

package Multi::Feed;

use strict;
use warnings;
use POE;
use TUWF::XML;
use POSIX 'strftime';
use Time::HiRes 'time';
use VNDBUtil 'bb2html';


sub spawn {
  my $p = shift;
  POE::Session->create(
    package_states => [
      $p => [qw| _start shutdown generate write_atom log_stats |],
    ],
    heap => {
      regenerate_interval => 900, # 15 min.
      stats_interval => 86400, # daily
      debug => 0,
      @_,
      stats => {}, # key = feed, value = [ count, total, max ]
    },
  );
}


sub _start {
  $_[KERNEL]->alias_set('feed');
  $_[KERNEL]->yield('generate');
  $_[KERNEL]->alarm(log_stats => int((time+3)/$_[HEAP]{stats_interval}+1)*$_[HEAP]{stats_interval});
  $_[KERNEL]->sig(shutdown => 'shutdown');
}


sub shutdown {
  $_[KERNEL]->delay('generate');
  $_[KERNEL]->delay('log_stats');
  $_[KERNEL]->alias_remove('feed');
}


sub generate {
  $_[KERNEL]->alarm(generate => int((time+3)/$_[HEAP]{regenerate_interval}+1)*$_[HEAP]{regenerate_interval});

  # announcements
  $_[KERNEL]->post(pg => query => q{
    SELECT '/t'||t.id AS id, t.title, extract('epoch' from tp.date) AS published,
       extract('epoch' from tp.edited) AS updated, u.username, u.id AS uid, tp.msg AS summary
     FROM threads t
     JOIN threads_posts tp ON tp.tid = t.id AND tp.num = 1
     JOIN threads_boards tb ON tb.tid = t.id AND tb.type = 'an'
     JOIN users u ON u.id = tp.uid
    WHERE NOT t.hidden
    ORDER BY t.id DESC
    LIMIT ?}, [ $VNDB::S{atom_feeds}{announcements}[0] ], 'write_atom', 'announcements'
  );

  # changes
  $_[KERNEL]->post(pg => query => q{
    SELECT '/'||c.type||COALESCE(vr.vid, rr.rid, pr.pid)||'.'||c.rev AS id,
       COALESCE(vr.title, rr.title, pr.name) AS title, extract('epoch' from c.added) AS updated,
       u.username, u.id AS uid, c.comments AS summary
    FROM changes c
     LEFT JOIN vn_rev vr ON c.type = 'v' AND c.id = vr.id
     LEFT JOIN releases_rev rr ON c.type = 'r' AND c.id = rr.id
     LEFT JOIN producers_rev pr ON c.type = 'p' AND c.id = pr.id
     JOIN users u ON u.id = c.requester
    WHERE c.requester <> 1
    ORDER BY c.id DESC
    LIMIT ?}, [ $VNDB::S{atom_feeds}{changes}[0] ], 'write_atom', 'changes'
  );

  # posts (this query isn't all that fast)
  $_[KERNEL]->post(pg => query => q{
    SELECT '/t'||t.id||'.'||tp.num AS id, t.title||' (#'||tp.num||')' AS title, extract('epoch' from tp.date) AS published,
       extract('epoch' from tp.edited) AS updated, u.username, u.id AS uid, tp.msg AS summary
     FROM threads_posts tp
     JOIN threads t ON t.id = tp.tid
     JOIN users u ON u.id = tp.uid
    WHERE NOT tp.hidden AND NOT t.hidden
    ORDER BY tp.date DESC
    LIMIT ?}, [ $VNDB::S{atom_feeds}{posts}[0] ], 'write_atom', 'posts'
  );
}


sub write_atom { # num, res, feed, time
  my $r = $_[ARG1];
  my $feed = $_[ARG2];

  my $start = time;

  my $updated = 0;
  for(@$r) {
    $updated = $_->{published} if $_->{published} && $_->{published} > $updated;
    $updated = $_->{updated} if $_->{updated} && $_->{updated} > $updated;
  }

  my $data;
  my $x = TUWF::XML->new(write => sub { $data .= shift }, pretty => 2);
  $x->xml();
  $x->tag(feed => xmlns => 'http://www.w3.org/2005/Atom', 'xml:lang' => 'en', 'xml:base' => $VNDB::S{url}.'/');
  $x->tag(title => $VNDB::S{atom_feeds}{$feed}[1]);
  $x->tag(updated => datetime($updated));
  $x->tag(id => $VNDB::S{url}.$VNDB::S{atom_feeds}{$feed}[2]);
  $x->tag(link => rel => 'self', type => 'application/atom+xml', href => "$VNDB::S{url}/feeds/$feed.atom", undef);
  $x->tag(link => rel => 'alternate', type => 'text/html', href => $VNDB::S{atom_feeds}{$feed}[2], undef);

  for(@$r) {
    $x->tag('entry');
    $x->tag(id => $VNDB::S{url}.$_->{id});
    $x->tag(title => $_->{title});
    $x->tag(updated => $_->{updated}?datetime($_->{updated}):datetime($_->{published}));
    $x->tag(published => datetime($_->{published})) if $_->{published};
    if($_->{username}) {
      $x->tag('author');
      $x->tag(name => $_->{username});
      $x->tag(uri => '/u'.$_->{uid}) if $_->{uid};
      $x->end;
    }
    $x->tag(link => rel => 'alternate', type => 'text/html', href => $_->{id}, undef);
    $x->tag('summary', type => 'html', bb2html($_->{summary}, 200)) if $_->{summary};
    $x->end('entry');
  }

  $x->end('feed');

  open my $f, '>:utf8', "$VNDB::ROOT/www/feeds/$feed.atom" || die $!;
  print $f $data;
  close $f;

  $_[HEAP]{debug} && $_[KERNEL]->call(core => log => 'Wrote %s.atom (%d entries, sql:%4dms, perl:%4dms)',
    $feed, scalar(@$r), $_[ARG3]*1000, (time-$start)*1000);

  $_[HEAP]{stats}{$feed} = [ 0, 0, 0 ] if !$_[HEAP]{stats}{$feed};
  my $time = ((time-$start)+$_[ARG3])*1000;
  $_[HEAP]{stats}{$feed}[0]++;
  $_[HEAP]{stats}{$feed}[1] += $time;
  $_[HEAP]{stats}{$feed}[2] = $time if $_[HEAP]{stats}{$feed}[2] < $time;
}


sub log_stats {
  $_[KERNEL]->alarm(log_stats => int((time+3)/$_[HEAP]{stats_interval}+1)*$_[HEAP]{stats_interval});

  for (keys %{$_[HEAP]{stats}}) {
    my $v = $_[HEAP]{stats}{$_};
    next if !$v->[0];
    $_[KERNEL]->call(core => log => 'Stats summary for %s.atom: total:%5dms, avg:%4dms, max:%4dms, size: %.1fkB',
      $_, $v->[1], $v->[1]/$v->[0], $v->[2], (-s "$VNDB::ROOT/www/feeds/$_.atom")/1024);
  }
  $_[HEAP]{stats} = {};
}


# non-POE helper function
sub datetime {
  strftime('%Y-%m-%dT%H:%M:%SZ', gmtime shift);
}


1;

