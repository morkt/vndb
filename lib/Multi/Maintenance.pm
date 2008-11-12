
#
#  Multi::Maintenance  -  General maintenance functions
#

package Multi::Maintenance;

use strict;
use warnings;
use POE;
use PerlIO::gzip;


sub spawn {
  # WARNING: these maintenance tasks can block the process for a few seconds

  my $p = shift;
  POE::Session->create(
    package_states => [
      $p => [qw| _start cmd_maintenance vncache revcache integrity unkanime logrotate |], 
    ],
  );
}


sub _start {
  $_[KERNEL]->alias_set('maintenance');
  $_[KERNEL]->call(core => register => qr/^maintenance((?: (?:vncache|revcache|integrity|unkanime|logrotate))+)$/, 'cmd_maintenance');
  
 # Perform some maintenance functions every day on 0:00
  $_[KERNEL]->post(core => addcron => '0 0 * * *', 'maintenance vncache integrity unkanime');
 # update caches and rotate logs every 1st day of the month at 0:05
  $_[KERNEL]->post(core => addcron => '5 0 1 * *' => 'maintenance revcache logrotate');
}


sub cmd_maintenance {
  $_[KERNEL]->yield($_)
    for (split /\s+/, $_[ARG1]);

  $_[KERNEL]->post(core => finish => $_[ARG0]);
}


sub vncache {
  $_[KERNEL]->call(core => log => 3 => 'Updating c_* columns in the vn table...');
 # takes ~5 seconds, better do this in the background...
  $Multi::SQL->do('SELECT update_vncache(0)');
}


sub revcache {
  $_[KERNEL]->call(core => log => 3 => 'Updating rev column in the changes table...');
  # this can take a while, maybe split these up in 3 queries?
  # ...or better yet, use asynchronous communication with PgSQL
  $Multi::SQL->do(q|SELECT update_rev('vn', ''), update_rev('releases', ''), update_rev('producers', '')|);
}


sub integrity {
 # checks for database inconsistencies not handled by the foreign key constraints:
 #   - releases without a VN relation
 #   - changes without an entry in the (vn|releases|producers)_rev table
 #   - threads without a tag or post

  my $q = $Multi::SQL->prepare(q|
   SELECT 'r', id FROM releases_rev rr
     WHERE NOT EXISTS(SELECT 1 FROM releases_vn rv WHERE rr.id = rv.rid)
   UNION
   SELECT c.type::varchar, id FROM changes c
     WHERE (c.type = 0 AND NOT EXISTS(SELECT 1 FROM vn_rev vr WHERE vr.id = c.id))
        OR (c.type = 1 AND NOT EXISTS(SELECT 1 FROM releases_rev rr WHERE rr.id = c.id))
        OR (c.type = 2 AND NOT EXISTS(SELECT 1 FROM producers_rev pr WHERE pr.id = c.id))
   UNION
   SELECT 't', id FROM threads t
     WHERE NOT EXISTS(SELECT 1 FROM threads_posts tp WHERE tp.tid = t.id)
        OR NOT EXISTS(SELECT 1 FROM threads_tags tt WHERE tt.tid = t.id)|);
  $q->execute();
  my $r = $q->fetchall_arrayref([]);
  if(@$r) {
    $_[KERNEL]->call(core => log => 1, '!DATABASE INCONSISTENCIES FOUND!: %s',
      join(', ', map { $_->[0].':'.$_->[1] } @$r));
  } else {
    $_[KERNEL]->call(core => log => 3, 'No database inconsistencies found');
  }
}


sub unkanime {
 # warn for VNs with a non-existing anidb id
 # (maybe do an automated edit or something in the future)

  my $q = $Multi::SQL->prepare(q|
    SELECT v.id, va.aid
    FROM vn_anime va
    JOIN vn v ON va.vid = v.latest
    JOIN anime a ON va.aid = a.id
    WHERE a.lastfetch < 0|);
  $q->execute();
  my $r = $q->fetchall_arrayref([]);
  my %aid = map { 
    my $a=$_;
    $a->[1] => join(',', map { $a->[1] == $_->[1] ? $_->[0] : () } @$r)
  } @$r;

  if(keys %aid) {
    $_[KERNEL]->call(core => log => 1, '!NON-EXISTING RELATED ANIME FOUND!: %s',
      join('; ', map { 'a'.$_.':v'.$aid{$_} } keys %aid)
    );
  } else {
    $_[KERNEL]->call(core => log => 3, 'No problems found with the related anime');
  }
}


sub logrotate {
  my $dir = sprintf '%s/old', $VNDB::M{log_dir};
  mkdir $dir if !-d $dir;

  for (glob sprintf '%s/*', $VNDB::M{log_dir}) {
    next if /^\./ || /~$/ || !-f;
    my $f = /([^\/]+)$/ ? $1 : $_;
    my $n = sprintf '%s/%s.%04d-%02d-%02d.gz', $dir, $f, (localtime)[5]+1900, (localtime)[4]+1, (localtime)[3];
    if(-f $n) {
      $_[KERNEL]->call(core => log => 1, 'Logs already rotated earlier today!');
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
}


1;


