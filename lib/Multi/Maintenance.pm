
#
#  Multi::Maintenance  -  General maintenance functions
#

# TODO: more logging?

package Multi::Maintenance;

use strict;
use warnings;
use POE;
use PerlIO::gzip;


sub spawn {
  my $p = shift;
  POE::Session->create(
    package_states => [
      $p => [qw|
        _start shutdown set_daily daily set_monthly monthly
        vncache tagcache vnpopularity
        usercache statscache revcache logrotate
      |],
    ],
    heap => {
      daily => [qw|vncache tagcache vnpopularity|],
      monthly => [qw|usercache statscache revcache logrotate|],
      @_,
    },
  );
}


sub _start {
  $_[KERNEL]->alias_set('maintenance');
  $_[KERNEL]->sig(shutdown => 'shutdown');
  $_[KERNEL]->yield('set_daily');
  $_[KERNEL]->yield('set_monthly');
}


sub shutdown {
  $_[KERNEL]->delay('daily');
  $_[KERNEL]->delay('monthly');
  $_[KERNEL]->alias_remove('maintenance');
}


sub set_daily {
  # run daily each day at 0:00 GMT
  # (GMT because we're calculating on the UNIX timestamp, I can easily add an
  #  offset if necessary, but it doesn't really matter what time this cron
  #  runs, as long as it's run on a daily basis)
  $_[KERNEL]->alarm(daily => int(time/86400+1)*86400);
}


sub daily {
  $_[KERNEL]->call(core => log => 'Running daily cron: %s', join ', ', @{$_[HEAP]{daily}});

  # dispatch events that need to be run on a daily basis
  $_[KERNEL]->call($_[SESSION], $_) for (@{$_[HEAP]{daily}});

  # re-activate timer
  $_[KERNEL]->call($_[SESSION], 'set_daily');
}


sub set_monthly {
  # Calculate the UNIX timestamp of 0:00 GMT of the first day of the next month.
  # We do this by simply incrementing the timestamp with one day and checking gmtime()
  # for a month change. This might not be very reliable, but should be enough for
  # our purposes.
  my $nextday = int(time/86400+1)*86400;
  my $thismonth = (gmtime)[5]*100+(gmtime)[4]; # year*100 + month, for easy comparing
  $nextday += 86400 while (gmtime $nextday)[5]*100+(gmtime $nextday)[4] <= $thismonth;
  $_[KERNEL]->alarm(monthly => $nextday);
}


sub monthly {
  $_[KERNEL]->call(core => log => 'Running monthly cron: %s', join ', ', @{$_[HEAP]{monthly}});

  # dispatch events that need to be run on a monthly basis
  $_[KERNEL]->call($_[SESSION], $_) for (@{$_[HEAP]{monthly}});

  # re-activate timer
  $_[KERNEL]->call($_[SESSION], 'set_monthly');
}



#
#  D A I L Y   J O B S
#


sub vncache {
  # this takes about 30s to complete. We really need to search for an alternative
  # method of keeping the c_* columns in the vn table up-to-date.
  $_[KERNEL]->post(pg => do => 'SELECT update_vncache(0)');
}


sub tagcache {
  # this still takes "only" about 3 seconds max. Let's hope that doesn't increase too much.
  $_[KERNEL]->post(pg => do => 'SELECT tag_vn_calc()');
}


sub vnpopularity {
  # still takes at most 2 seconds. Againt, let's hope that doesn't increase...
  $_[KERNEL]->post(pg => do => 'SELECT update_vnpopularity()');
}



#
#  M O N T H L Y   J O B S
#


sub usercache {
  # Shouldn't really be necessary, except c_changes could be slightly off when hiding/unhiding DB items
  # Currently takes about 25 seconds to complete.
  $_[KERNEL]->post(pg => do => q|UPDATE users SET
    c_votes = COALESCE(
      (SELECT COUNT(vid)
      FROM votes
      WHERE uid = users.id
      GROUP BY uid
    ), 0),
    c_changes = COALESCE(
      (SELECT COUNT(id)
      FROM changes
      WHERE requester = users.id
      GROUP BY requester
    ), 0),
    c_tags = COALESCE(
      (SELECT COUNT(tag)
      FROM tags_vn
      WHERE uid = users.id
      GROUP BY uid
    ), 0)
  |);
}


sub statscache {
  # Shouldn't really be necessary, the triggers in PgSQL should keep these up-to-date nicely.
  # But it takes less than 100ms to complete, anyway
  $_[KERNEL]->post(pg => do => $_) for(
    q|UPDATE stats_cache SET count = (SELECT COUNT(*) FROM users)-1 WHERE section = 'users'|,
    q|UPDATE stats_cache SET count = (SELECT COUNT(*) FROM vn        WHERE hidden = FALSE) WHERE section = 'vn'|,
    q|UPDATE stats_cache SET count = (SELECT COUNT(*) FROM releases  WHERE hidden = FALSE) WHERE section = 'releases'|,
    q|UPDATE stats_cache SET count = (SELECT COUNT(*) FROM producers WHERE hidden = FALSE) WHERE section = 'producers'|,
    q|UPDATE stats_cache SET count = (SELECT COUNT(*) FROM threads   WHERE hidden = FALSE) WHERE section = 'threads'|,
    q|UPDATE stats_cache SET count = (SELECT COUNT(*) FROM threads_posts WHERE hidden = FALSE
        AND EXISTS(SELECT 1 FROM threads WHERE threads.id = tid AND threads.hidden = FALSE)) WHERE section = 'threads_posts'|
  );
}


sub revcache {
  # This -really- shouldn't be necessary...
  # Currently takes about 25 seconds to complete
  $_[KERNEL]->post(pg => do => q|SELECT update_rev('vn', ''), update_rev('releases', ''), update_rev('producers', '')|);
}


sub logrotate {
  my $dir = sprintf '%s/old', $VNDB::M{log_dir};
  mkdir $dir if !-d $dir;

  for (glob sprintf '%s/*', $VNDB::M{log_dir}) {
    next if /^\./ || /~$/ || !-f;
    my $f = /([^\/]+)$/ ? $1 : $_;
    my $n = sprintf '%s/%s.%04d-%02d-%02d.gz', $dir, $f, (localtime)[5]+1900, (localtime)[4]+1, (localtime)[3];
    if(-f $n) {
      $_[KERNEL]->call(core => log => 'Logs already rotated earlier today!');
      return;
    }
    open my $I, '<', sprintf '%s/%s', $VNDB::M{log_dir}, $f;
    open my $O, '>:gzip', $n;
    print $O $_ while <$I>;
    close $O;
    close $I;
    open $I, '>', sprintf '%s/%s', $VNDB::M{log_dir}, $f;
    close $I;
  }
  $_[KERNEL]->call(core => log => 'Logs rotated.');
}


1;

