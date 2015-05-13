
#
#  Multi::Maintenance  -  General maintenance functions
#

package Multi::Maintenance;

use strict;
use warnings;
use Multi::Core;
use PerlIO::gzip;
use VNDBUtil 'normalize_titles';


my $monthly;


sub run {
  push_watcher schedule 12*3600, 24*3600, \&daily;
  push_watcher schedule 0, 3600, \&vnsearch_check;
  push_watcher pg->listen(vnsearch => on_notify => \&vnsearch_check);
  set_monthly();
}


sub unload {
  undef $monthly;
}


sub set_monthly {
  # Calculate the UNIX timestamp of 12:00 GMT of the first day of the next month.
  # We do this by simply incrementing the timestamp with one day and checking gmtime()
  # for a month change. This might not be very reliable, but should be enough for
  # our purposes.
  my $nextday = int((time+3)/86400+1)*86400 + 12*3600;
  my $thismonth = (gmtime)[5]*100+(gmtime)[4]; # year*100 + month, for easy comparing
  $nextday += 86400 while (gmtime $nextday)[5]*100+(gmtime $nextday)[4] <= $thismonth;
  $monthly = AE::timer $nextday, 0, \&monthly;
}


sub log_res {
  my($id, $res, $time) = @_;
  return if pg_expect $res, undef, $id;
  AE::log info => sprintf 'Finished %s in %.3fs (%d rows)', $id, $time, $res->cmdRows;
}


#
#  D A I L Y   J O B S
#


my %dailies = (
  # takes about 500ms to 5s to complete, depending on how many releases have
  # been released within the past 5 days
  vncache_inc => q|
    SELECT update_vncache(id)
      FROM (
        SELECT DISTINCT rv.vid
          FROM releases r
          JOIN releases_rev rr ON rr.id = r.latest
          JOIN releases_vn rv ON rv.rid = r.latest
         WHERE rr.released  > TO_CHAR(NOW() - '5 days'::interval, 'YYYYMMDD')::integer
           AND rr.released <= TO_CHAR(NOW(), 'YYYYMMDD')::integer
      ) AS r(id)|,

  # takes about 9 seconds max, still OK
  tagcache => 'SELECT tag_vn_calc()',

  # takes about 90 seconds, might want to optimize or split up
  traitcache => 'SELECT traits_chars_calc()',

  # takes about 30 seconds
  vnpopularity => 'SELECT update_vnpopularity()',

  # takes about 25 seconds, can be performed in ranges as well when necessary
  vnrating => q|
    UPDATE vn SET
      c_rating = (SELECT (
          ((SELECT COUNT(vote)::real/COUNT(DISTINCT vid)::real FROM votes)*(SELECT AVG(a)::real FROM (SELECT AVG(vote) FROM votes GROUP BY vid) AS v(a)) + SUM(vote)::real) /
          ((SELECT COUNT(vote)::real/COUNT(DISTINCT vid)::real FROM votes) + COUNT(uid)::real)
        ) FROM votes WHERE vid = id AND uid NOT IN(SELECT id FROM users WHERE ign_votes)
      ),
      c_votecount = COALESCE((SELECT count(*) FROM votes WHERE vid = id AND uid NOT IN(SELECT id FROM users WHERE ign_votes)), 0)|,

  # should be pretty fast
  cleangraphs => q|
    DELETE FROM relgraphs vg
     WHERE NOT EXISTS(SELECT 1 FROM vn WHERE rgraph = vg.id)
       AND NOT EXISTS(SELECT 1 FROM producers WHERE rgraph = vg.id)|,

  cleansessions      => q|DELETE FROM sessions       WHERE lastused   < NOW()-'1 month'::interval|,
  cleannotifications => q|DELETE FROM notifications  WHERE read       < NOW()-'1 month'::interval|,
  rmunconfirmusers   => q|DELETE FROM users          WHERE registered < NOW()-'1 week'::interval AND NOT email_confirmed|,
  cleanthrottle      => q|DELETE FROM login_throttle WHERE timeout    < NOW()|,
);


sub run_daily {
  my($d, $sub) = @_;
  pg_cmd $dailies{$d}, undef, sub {
    log_res $d, @_;
    $sub->() if $sub;
  };
}


sub daily {
  my @l = sort keys %dailies;
  my $s; $s = sub {
    run_daily shift(@l), $s if @l;
  };
  $s->();
}




#
#  M O N T H L Y   J O B S
#


my %monthlies = (
  # This takes about 4 to 5 minutes to complete, and should only be necessary
  # in the event that the daily vncache_inc cron hasn't been running for 5
  # subsequent days.
  vncache_full => 'SELECT update_vncache(id) FROM vn',

  # These shouldn't really be necessary, the triggers in PgSQL should keep
  # these up-to-date nicely.  But these all take less a second to complete,
  # anyway.
  stats_users => q|UPDATE stats_cache SET count = (SELECT COUNT(*) FROM users)-1 WHERE section = 'users'|,
  stats_vn    => q|UPDATE stats_cache SET count = (SELECT COUNT(*) FROM vn        WHERE hidden = FALSE) WHERE section = 'vn'|,
  stats_rel   => q|UPDATE stats_cache SET count = (SELECT COUNT(*) FROM releases  WHERE hidden = FALSE) WHERE section = 'releases'|,
  stats_prod  => q|UPDATE stats_cache SET count = (SELECT COUNT(*) FROM producers WHERE hidden = FALSE) WHERE section = 'producers'|,
  stats_chars => q|UPDATE stats_cache SET count = (SELECT COUNT(*) FROM chars     WHERE hidden = FALSE) WHERE section = 'chars'|,
  stats_chars => q|UPDATE stats_cache SET count = (SELECT COUNT(*) FROM staff     WHERE hidden = FALSE) WHERE section = 'staff'|,
  stats_tags  => q|UPDATE stats_cache SET count = (SELECT COUNT(*) FROM tags      WHERE state = 2)      WHERE section = 'tags'|,
  stats_trait => q|UPDATE stats_cache SET count = (SELECT COUNT(*) FROM traits    WHERE state = 2)      WHERE section = 'traits'|,
  stats_thread=> q|UPDATE stats_cache SET count = (SELECT COUNT(*) FROM threads   WHERE hidden = FALSE) WHERE section = 'threads'|,
  stats_posts => q|UPDATE stats_cache SET count = (SELECT COUNT(*) FROM threads_posts WHERE hidden = FALSE
    AND EXISTS(SELECT 1 FROM threads WHERE threads.id = tid AND threads.hidden = FALSE)) WHERE section = 'threads_posts'|,
);


sub logrotate {
  my $dir = sprintf '%s/old', $VNDB::M{log_dir};
  mkdir $dir if !-d $dir;

  for (glob sprintf '%s/*', $VNDB::M{log_dir}) {
    next if /^\./ || /~$/ || !-f;
    my $f = /([^\/]+)$/ ? $1 : $_;
    my $n = sprintf '%s/%s.%04d-%02d-%02d.gz', $dir, $f, (localtime)[5]+1900, (localtime)[4]+1, (localtime)[3];
    return if -f $n;
    open my $I, '<', sprintf '%s/%s', $VNDB::M{log_dir}, $f;
    open my $O, '>:gzip', $n;
    print $O $_ while <$I>;
    close $O;
    close $I;
    open $I, '>', sprintf '%s/%s', $VNDB::M{log_dir}, $f;
    close $I;
  }
  AE::log info => 'Logs rotated.';
}


sub run_monthly {
  my($d, $sub) = @_;
  pg_cmd $monthlies{$d}, undef, sub {
    log_res $d, @_;
    $sub->() if $sub;
  };
}


sub monthly {
  my @l = sort keys %monthlies;
  my $s; $s = sub {
    run_monthly shift(@l), $s if @l;
  };
  $s->();

  logrotate;
  set_monthly;
}



#
#  V N   S E A R C H   C A C H E
#


sub vnsearch_check {
  pg_cmd 'SELECT id FROM vn WHERE c_search IS NULL LIMIT 1', undef, sub {
    my $res = shift;
    return if pg_expect $res, 1 or !$res->rows;

    my $id = $res->value(0,0);
    pg_cmd q|SELECT vr.title, vr.original, vr.alias
        FROM vn v
        JOIN vn_rev vr ON vr.id = v.latest
       WHERE v.id = $1
      UNION
      SELECT rr.title, rr.original, NULL
        FROM releases r
        JOIN releases_rev rr ON rr.id = r.latest
        JOIN releases_vn rv ON rv.rid = r.latest
       WHERE rv.vid = $1
         AND NOT r.hidden
    |, [ $id ], sub { vnsearch_update($id, @_) };
  };
}


sub vnsearch_update { # id, res, time
  my($id, $res, $time) = @_;
  return if pg_expect $res, 1;

  my $t = normalize_titles(grep length, map
    +($_->{title}, $_->{original}, split /[\n,]/, $_->{alias}||''),
    $res->rowsAsHashes
  );

  pg_cmd 'UPDATE vn SET c_search = $1 WHERE id = $2', [ $t, $id ], sub {
    my($res, $t2) = @_;
    return if pg_expect $res, 0;
    AE::log info => sprintf 'Updated search cache for v%d (%3dms SQL)', $id, ($time+$t2)*1000;
    vnsearch_check;
  };
}


1;

__END__

# Shouldn't really be necessary, except c_changes could be slightly off when
# hiding/unhiding DB items.
# This query takes almost two hours to complete and tends to bring the entire
# site down with it, so it's been disabled for now. Can be performed in
# ranges though.
UPDATE users SET
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
