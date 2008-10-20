
package VNDB::Util::DB;

use strict;
use warnings;
use DBI;
use Exporter 'import';

use vars ('$VERSION', '@EXPORT');
$VERSION = $VNDB::VERSION;

@EXPORT = qw|
  DBInit DBCheck DBCommit DBRollBack DBExit
  DBLanguageCount DBCategoryCount DBTableCount DBGetHist DBLockItem DBIncId DBAddScreenshot DBGetScreenshot
  DBGetUser DBAddUser DBUpdateUser DBDelUser
  DBGetVotes DBVoteStats DBAddVote DBDelVote
  DBGetVNList DBDelVNList
  DBGetWishList DBEditWishList DBDelWishList
  DBGetRList DBGetRLists DBEditRList DBDelRList
  DBGetVN DBAddVN DBEditVN DBHideVN DBVNCache
  DBGetRelease DBAddRelease DBEditRelease DBHideRelease
  DBGetProducer DBGetProducerVN DBAddProducer DBEditProducer DBHideProducer
  DBGetThreads DBGetPosts DBAddPost DBEditPost DBEditThread DBAddThread
  DBExec DBRow DBAll
|;





#-----------------------------------------------------------------------------#
#                     I M P O R T A N T   S T U F F                           #
#-----------------------------------------------------------------------------#


sub new {
  my $me = shift;

  my $type = ref($me) || $me;
  $me = bless { o => \@_ }, $type;
  
  $me->DBInit();

  return $me;
}


sub DBInit {
  my $self = shift;
  my $info = $self->{_DB} || $self;
  
  $info->{sql} = DBI->connect(@{$self->{o}}, {
      PrintError => 0, RaiseError => 1,
      AutoCommit => 0, pg_enable_utf8 => 1,  
    }
  );
}


sub DBCheck {
  my $self = shift;
  my $info = $self->{_DB} || $self;

  require Time::HiRes
    if $self->{debug} && !$Time::Hires::VERSION;
  $info->{Queries} = [] if $self->{debug};
  my $start = [Time::HiRes::gettimeofday()] if $self->{debug};

  if(!$info->{sql}->ping) {
    warn "Ping failed, reconnecting";
    $self->DBInit;
  }
  $info->{sql}->rollback();
  push(@{$info->{Queries}},
    [ 'ping/rollback', Time::HiRes::tv_interval($start) ])
   if $self->{debug};
}


sub DBCommit {
  my $self = shift;
  my $info = $self->{_DB} || $self;
  my $start = [Time::HiRes::gettimeofday()] if $self->{debug};
  $info->{sql}->commit();
  push(@{$info->{Queries}},
    [ 'commit', Time::HiRes::tv_interval($start) ])
   if $self->{debug};
}


sub DBRollBack {
  my $self = shift;
  my $info = $self->{_DB} || $self;
  $info->{sql}->rollback();
}


sub DBExit {
  my $self = shift;
  my $info = $self->{_DB} || $self; 
  $info->{sql}->disconnect();
}


# XXX: this function should be disabled when performance is going to be a problem
sub DBCategoryCount {
  return {
    (map { map { $_, 0 } keys %{$VNDB::CAT->{$_}[1]} } keys %{$VNDB::CAT}),
    map { $_->{cat}, $_->{cnt} } @{shift->DBAll(q|
    SELECT cat, COUNT(vid) AS cnt
      FROM vn_categories vc
      JOIN vn v ON v.latest = vc.vid
      WHERE v.hidden = FALSE
      GROUP BY cat
      ORDER BY cnt|
    )}
  };
}


# XXX: Above comment also applies to this function
sub DBLanguageCount {
  return { (map { $_ => 0 } keys %$VNDB::LANG ),
    map { $_->{language} => $_->{count} } @{shift->DBAll(q|
    SELECT rr.language, COUNT(DISTINCT v.id) AS count
      FROM releases_rev rr
      JOIN releases r ON r.latest = rr.id
      JOIN releases_vn rv ON rv.rid = rr.id
      JOIN vn v ON v.id = rv.vid
      WHERE r.hidden = FALSE
        AND v.hidden = FALSE
        AND rr.type <> 2
        AND rr.released <= TO_CHAR('today'::timestamp, 'YYYYMMDD')::integer
      GROUP BY rr.language|)} };
}


sub DBTableCount { # table (users, producers, vn, releases, votes)
  return $_[0]->DBRow(q|
    SELECT COUNT(*) as cnt
      FROM !s
      !W|,
    $_[1],
    $_[1] =~ /producers|vn|releases/ ? { 'hidden = ?' => 0 } : {},
  )->{cnt} - ($_[1] eq 'users' ? 1 : 0);
}



# XXX: iid, ititle and hidden columns should be cached if performance will be a problem
sub DBGetHist { # %options->{ type, id, cid, caused, next, page, results, ip, edits, showhid, what }  (Item hist)
  my($s, %o) = @_;

  $o{results} ||= $o{next} ? 1 : 50;
  $o{page} ||= 1;
  $o{type} ||= '';
  $o{what} ||= ''; #flags: user iid ititle
  $o{showhid} ||= $o{type} && $o{type} ne 'u' && $o{id} || $o{cid} ? 1 : 0;

  my %where = (
    $o{cid} ? (
      'c.id IN(!l)' => [$o{cid}] ) : (),
    $o{type} eq 'u' ? (
      'c.requester = ?' => $o{id} ) : (),

    $o{type} eq 'v' && !$o{releases} ? ( 'c.type = ?' => 0,
      $o{id} ? ( 'vr.vid = ?' => $o{id} ) : () ) : (),
    $o{type} eq 'v' && $o{releases} ? (
      '((c.type = ? AND vr.vid = ?) OR (c.type = ? AND rv.vid = ?))' => [0,$o{id},1,$o{id}] ) : (),
    
    $o{type} eq 'r' ? ( 'c.type = ?' => 1,
      $o{id} ? ( 'rr.rid = ?' => $o{id} ) : () ) : (),
    $o{type} eq 'p' ? ( 'c.type = ?' => 2,
      $o{id} ? ( 'pr.pid = ?' => $o{id} ) : () ) : (),

    $o{caused} ? (
      'c.causedby = ?' => $o{caused} ) : (),
    $o{ip} ? (
      'c.ip = ?' => $o{ip} ) : (),
    defined $o{edits} && !$o{edits} ? (
      'c.rev = ?' => 1 ) : (),
    $o{edits} ? (
      'c.rev > ?' => 1 ) : (),

   # get rid of 'hidden' items
    !$o{showhid} ? (
      '(v.hidden IS NOT NULL AND v.hidden = FALSE OR r.hidden IS NOT NULL AND r.hidden = FALSE OR p.hidden IS NOT NULL AND p.hidden = FALSE)' => 1,
    ) : $o{showhid} == 2 ? (
      '(v.hidden IS NOT NULL AND v.hidden = TRUE OR r.hidden IS NOT NULL AND r.hidden = TRUE OR p.hidden IS NOT NULL AND p.hidden = TRUE)' => 1,
    ) : (),
  );

  my $select = 'c.id, c.type, c.added, c.requester, c.comments, c.rev, c.causedby';
  $select .= ', u.username' if $o{what} =~ /user/;
  $select .= ', COALESCE(vr.vid, rr.rid, pr.pid) AS iid' if $o{what} =~ /iid/;
  $select .= ', COALESCE(vr2.title, rr2.title, pr2.name) AS ititle, COALESCE(vr2.original, rr2.original, pr2.original) AS ioriginal' if $o{what} =~ /ititle/;

  my $join = '';
  $join .= ' JOIN users u ON u.id = c.requester' if $o{what} =~ /user/;
  $join .= ' LEFT JOIN vn_rev vr ON c.type = 0 AND c.id = vr.id'.
           ' LEFT JOIN releases_rev rr ON c.type = 1 AND c.id = rr.id'.
           ' LEFT JOIN producers_rev pr ON c.type = 2 AND c.id = pr.id' if $o{what} =~ /(iid|ititle)/ || $o{releases} || $o{id} || !$o{showhid};
 # these joins should be optimised away at some point (cache the required columns in changes as mentioned above)
  $join .= ' LEFT JOIN vn v ON v.id = vr.vid'.
           ' LEFT JOIN vn_rev vr2 ON vr2.id = v.latest'.
           ' LEFT JOIN releases r ON r.id = rr.rid'.
           ' LEFT JOIN releases_rev rr2 ON rr2.id = r.latest'.
           ' LEFT JOIN producers p ON p.id = pr.pid'.
           ' LEFT JOIN producers_rev pr2 ON pr2.id = p.latest' if $o{what} =~ /ititle/ || $o{releases} || !$o{showhid};
  $join .= ' LEFT JOIN releases_vn rv ON c.id = rv.rid' if $o{type} eq 'v' && $o{releases};

  my $r = $s->DBAll(qq|
    SELECT $select
      FROM changes c
      $join
      !W
      ORDER BY c.id !s
      LIMIT ? OFFSET ?|,
    \%where,
    $o{next} ? 'ASC' : 'DESC',
    $o{results}+(wantarray?1:0), $o{results}*($o{page}-1)
  );
  return $r if !wantarray;
  return ($r, 0) if $#$r != $o{results};
  pop @$r;
  return ($r, 1);
}


sub DBLockItem { # table, id, locked
  my($s, $tbl, $id, $l) = @_;
  $s->DBExec(q|
    UPDATE !s
      SET locked = ?
      WHERE id = ?|,
    $tbl, $l?1:0, $id);
}


sub DBIncId { # sequence (this is a rather low-level function... aww heck...)
  return $_[0]->DBRow(q|SELECT nextval(?) AS ni|, $_[1])->{ni};
}


sub DBAddScreenshot { # just returns an ID
  return $_[0]->DBRow(q|INSERT INTO screenshots (status) VALUES(0) RETURNING id|)->{id};
}


sub DBGetScreenshot { # ids
  return $_[0]->DBAll(q|SELECT * FROM screenshots WHERE id IN(!l)|, $_[1]);
}



#-----------------------------------------------------------------------------#
#                      A U T H / U S E R   S T U F F                          #
#-----------------------------------------------------------------------------#


sub DBGetUser { # %options->{ username mail passwd order firstchar uid results page what }
  my $s = shift;
  my %o = (
    order => 'username ASC',
    page => 1,
    results => 10,
    what => '',
    @_
  );

  my %where = (
    'id > 0' => 1,
    $o{username} ? (
      'username = ?' => $o{username} ) : (),
    $o{mail} ? (
      'mail = ?' => $o{mail} ) : (),
    $o{passwd} ? (
      'passwd = decode(?, \'hex\')' => $o{passwd} ) : (),
    $o{firstchar} ? (
      'SUBSTRING(username from 1 for 1) = ?' => $o{firstchar} ) : (),
    !$o{firstchar} && defined $o{firstchar} ? (
      'ASCII(username) < 97 OR ASCII(username) > 122' => 1 ) : (),
    $o{uid} ? (
      'id = ?' => $o{uid} ) : (),
    !$o{uid} && !$o{username} ? (
      'id > 0' => 1 ) : (),
  );

  my $r = $s->DBAll(q|
    SELECT *
      FROM users u
      !W
      ORDER BY !s
      LIMIT ? OFFSET ?|,
    \%where,
    $o{order},
    $o{results}+(wantarray?1:0), $o{results}*($o{page}-1)
  );

 # XXX: easy to cache, good performance win
  if($o{what} =~ /list/ && $#$r >= 0) {
    my %r = map {
      $r->[$_]{votes} = 0;
      $r->[$_]{changes} = 0;
      ($r->[$_]{id}, $_)
    } 0..$#$r;
    
    $r->[$r{$_->{uid}}]{votes} = $_->{cnt} for (@{$s->DBAll(q|
      SELECT uid, COUNT(vid) AS cnt
        FROM votes
        WHERE uid IN(!l)
        GROUP BY uid|,
      [ keys %r ]
    )});

    $r->[$r{$_->{requester}}]{changes} = $_->{cnt} for (@{$s->DBAll(q|
      SELECT requester, COUNT(id) AS cnt
        FROM changes
        WHERE requester IN(!l)
        GROUP BY requester|,
      [ keys %r ]
    )});
  }

  return $r if !wantarray;
  return ($r, 0) if $#$r != $o{results};
  pop @$r;
  return ($r, 1);
}


sub DBAddUser { # username, passwd, mail, rank
  return $_[0]->DBExec(q|
    INSERT INTO users
      (username, passwd, mail, rank, registered)
      VALUES (?, decode(?, 'hex'), ?, ?, ?)|,
    lc($_[1]), $_[2], $_[3], $_[4], time
  );
}


sub DBUpdateUser { # uid, %options->{ columns in users table }
  my $s = shift;
  my $user = shift;
  my %opt = @_;
  my %h;

  defined $opt{$_} && ($h{$_.' = ?'} = $opt{$_})
    for (qw| username mail rank flags |);
  $h{'passwd = decode(?, \'hex\')'} = $opt{passwd}
    if defined $opt{passwd};

  return 0 if scalar keys %h <= 0;
  return $s->DBExec(q|
    UPDATE users
      !H
      WHERE id = ?|,
    \%h, $user);
}


sub DBDelUser { # uid
  my($s, $id) = @_;
  $s->DBExec($_, $id) for (
    q|DELETE FROM vnlists WHERE uid = ?|,
    q|DELETE FROM rlists WHERE uid = ?|,
    q|DELETE FROM wlists WHERE uid = ?|,
    q|DELETE FROM votes WHERE uid = ?|,
    q|UPDATE changes SET requester = 0 WHERE requester = ?|,
    q|UPDATE threads_posts SET uid = 0 WHERE uid = ?|,
    q|DELETE FROM users WHERE id = ?|
  );
}






#-----------------------------------------------------------------------------#
#                                 V O T E S                                   #
#-----------------------------------------------------------------------------#


sub DBGetVotes { # %options->{ uid vid hide order results page }
  my($s, %o) = @_;
  $o{order} ||= 'n.date DESC';
  $o{results} ||= 50;
  $o{page} ||= 1;

  my %where = (
    $o{uid} ? ( 'n.uid = ?' => $o{uid} ) : (),
    $o{vid} ? ( 'n.vid = ?' => $o{vid} ) : (),
    $o{hide} ? ( 'u.flags & ? = ?' => [ $VNDB::UFLAGS->{list}, $VNDB::UFLAGS->{list} ] ) : (),
  );

  my $r = $s->DBAll(q|
    SELECT n.vid, vr.title, vr.original, n.vote, n.date, n.uid, u.username
      FROM votes n
      JOIN vn v ON v.id = n.vid
      JOIN vn_rev vr ON vr.id = v.latest
      JOIN users u ON u.id = n.uid
      !W
      ORDER BY !s
      LIMIT ? OFFSET ?|,
    \%where,
    $o{order},
    $o{results}+(wantarray?1:0), $o{results}*($o{page}-1)
  );
  return $r if !wantarray;
  return ($r, 0) if $#$r < $o{results};
  pop @$r;
  return ($r, 1);
}


sub DBVoteStats { # uid|vid => id
  my($s, $col, $id) = @_;
  my $r = [ qw| 0 0 0 0 0 0 0 0 0 0 | ];
  $r->[$_->{vote}-1] = $_->{votes} for (@{$s->DBAll(q|
    SELECT vote, COUNT(vote) as votes
      FROM votes
      !W
      GROUP BY vote|,
    $col ? { '!s = ?' => [ $col, $id ] } : {},
  )});
  return $r;
}


sub DBAddVote { # vid, uid, vote
  $_[0]->DBExec(q|
    UPDATE votes
      SET vote = ?
      WHERE vid = ? 
        AND uid = ?|,
    $_[3], $_[1], $_[2]
  ) || $_[0]->DBExec(q|
    INSERT INTO votes
      (vid, uid, vote, date)
      VALUES (!l)|,
    [ @_[1..3], time ]
  );
}


sub DBDelVote { # uid, vid  # uid = 0 to delete all
  $_[0]->DBExec(q|
    DELETE FROM votes
      !W|,
    { 'vid = ?' => $_[2],
      $_[1] ? ('uid = ?' => $_[1]) : ()
    }
  );
}





#-----------------------------------------------------------------------------#
#              U S E R   V I S U A L   N O V E L   L I S T S                  #
#-----------------------------------------------------------------------------#


sub DBGetVNList { # %options->{ uid vid hide order results page status }
  my($s, %o) = @_;
  $o{results} ||= 10;
  $o{page} ||= 1;
  $o{order} ||= 'l.date DESC';

  my %where = (
    $o{uid} ? (
      'l.uid = ?' => $o{uid} ) : (),
    $o{vid} ? (
      'l.vid = ?' => $o{vid} ) : (),
    defined $o{status} ? (
      'l.status = ?' => $o{status} ) : (),
    $o{hide} ? ( 'u.flags & ? = ?' => [ $VNDB::UFLAGS->{list}, $VNDB::UFLAGS->{list} ] ) : (),
  );

  return wantarray ? ([], 0) : [] if !keys %where;

  my $r = $s->DBAll(q|
    SELECT l.vid, vr.title, l.status, l.comments, l.date, l.uid, u.username
      FROM vnlists l
      JOIN vn v ON l.vid = v.id
      JOIN vn_rev vr ON vr.id = v.latest
      JOIN users u ON l.uid = u.id
      !W
      ORDER BY !s 
      LIMIT ? OFFSET ?|,
    \%where,
    $o{order},
    $o{results}+(wantarray?1:0), $o{results}*($o{page}-1)
  );
  return $r if !wantarray;
  return ($r, 0) if $#$r < $o{results};
  pop @$r;
  return ($r, 1);
}


sub DBDelVNList { # uid, @vid  # uid = 0 to delete all
  my($s, $uid, @vid) = @_;
  $s->DBExec(q|
    DELETE FROM vnlists
      !W|,
    { 'vid IN (!l)' => [\@vid],
      $uid ? ('uid = ?' => $uid) : ()
    }
  );
}





#-----------------------------------------------------------------------------#
#                       U S E R   W I S H   L I S T S                         #
#-----------------------------------------------------------------------------#


sub DBGetWishList { # %options->{ uid vid what order page results }
  my($s, %o) = @_;

  $o{order} ||= 'wl.wstat ASC';
  $o{page} ||= 1;
  $o{results} ||= 50;
  $o{what} ||= '';

  my %where = (
    'wl.uid = ?' => $o{uid},
    $o{vid} ? ( 'wl.vid = ?' => $o{vid} ) : (),
  );
  
  my $select = 'wl.vid, wl.wstat, wl.added';
  my @join;
  if($o{what} =~ /vn/) {
    $select .= ', vr.title, vr.original';
    push @join, 'JOIN vn v ON v.id = wl.vid',
                'JOIN vn_rev vr ON vr.id = v.latest';
  }
  
  my $r = $s->DBAll(qq|
    SELECT $select
      FROM wlists wl
      @join
      !W
      ORDER BY !s
      LIMIT ? OFFSET ?|,
    \%where,
    $o{order},
    $o{results}+(wantarray?1:0), $o{results}*($o{page}-1)
  );
  return $r if !wantarray;
  return ($r, 0) if $#$r < $o{results};
  pop @$r;
  return ($r, 1);
}


sub DBEditWishList { # %options->{ uid vid wstat }
  my($s, %o) = @_;
    $s->DBExec(q|UPDATE wlists SET wstat = ? WHERE uid = ? AND vid IN(!l)|,
      $o{wstat}, $o{uid}, ref($o{vid}) eq 'ARRAY' ? $o{vid} : [ $o{vid} ])
  ||
    $s->DBExec(q|INSERT INTO wlists (uid, vid, wstat)
      VALUES(!l)|,
      [@o{qw| uid vid wstat |}]);
}


sub DBDelWishList { # uid, vids
  my($s, $uid, $vid) = @_;
  $s->DBExec(q|DELETE FROM wlists WHERE uid = ? AND vid IN(!l)|, $uid, $vid);
}






#-----------------------------------------------------------------------------#
#                    U S E R   R E L E A S E   L I S T S                      #
#-----------------------------------------------------------------------------#


sub DBGetRList { # %options->{ uid rids }
  my($s, %o) = @_;

  my %where = (
    'uid = ?' => $o{uid},
    $o{rids} ? (
      'rid IN(!l)' => [$o{rids}] ) : (),
  );
  
  return $s->DBAll(q|
    SELECT uid, rid, rstat, vstat
      FROM rlists
      !W|,
    \%where);
}


# separate function, which also fetches VN info and votes
sub DBGetRLists { # %options->{ uid order char rstat vstat voted page results }
  my($s, %o) = @_;

  $o{results} ||= 50;
  $o{page} ||= 1;

 # bit ugly...
  my $where = !$o{rstat} && !$o{vstat} ? 'vo.vote IS NOT NULL' : '';
  $where .= ($where?' OR ':'').q|v.id IN(
      SELECT irv.vid
      FROM rlists irl
      JOIN releases ir ON ir.id = irl.rid
      JOIN releases_vn irv ON irv.rid = ir.latest 
      !W
    )| if !$o{voted};
  $where = '('.$where.') AND LOWER(SUBSTR(vr.title, 1, 1)) = \''.$o{char}.'\'' if $o{char};
  $where = '('.$where.') AND (ASCII(vr.title) < 97 OR ASCII(vr.title) > 122) AND (ASCII(vr.title) < 65 OR ASCII(vr.title) > 90)' if defined $o{char} && !$o{char};

 # WHERE clause for the rlists subquery
  my %where = (
    'uid = ?' => $o{uid},
    defined $o{rstat} ? ( 'rstat = ?' => $o{rstat} ) : (),
    defined $o{vstat} ? ( 'vstat = ?' => $o{vstat} ) : (),
  );

  my $r = $s->DBAll(qq|
    SELECT vr.vid, vr.title, vr.original, v.c_released, v.c_languages, v.c_platforms, COALESCE(vo.vote, 0) AS vote
      FROM vn v
      JOIN vn_rev vr ON vr.id = v.latest
      !s JOIN votes vo ON vo.vid = v.id AND vo.uid = ?
      WHERE $where
      ORDER BY !s
      LIMIT ? OFFSET ?|,
    $o{voted} ? '' : 'LEFT', $o{uid},   # JOIN if we only want votes, LEFT JOIN if we also want rlist items
    $o{voted} ? () : \%where,
    $o{order},
    $o{results}+(wantarray?1:0), $o{results}*($o{page}-1)
  );

 # now fetch the releases and link them to VNs
  if(@$r) {
    my %vns = map { $_->{rels}=[]; $_->{vid}, $_->{rels} } @$r;
    push @{$vns{$_->{vid}}}, $_ for (@{$s->DBAll(q|
      SELECT rv.vid, rr.rid, rr.title, rr.original, rr.released, rr.type, rr.language, rr.minage, rl.rstat, rl.vstat
        FROM rlists rl
        JOIN releases r ON rl.rid = r.id
        JOIN releases_rev rr ON rr.id = r.latest
        JOIN releases_vn rv ON rv.rid = r.latest
        WHERE rl.uid = ? 
          AND rv.vid IN(!l)
        ORDER BY rr.released ASC|,
      $o{uid}, [ keys %vns ]
    )});
  }

  return $r if !wantarray;
  return ($r, 0) if $#$r < $o{results};
  pop @$r;
  return ($r, 1);
}


sub DBEditRList { # %options->{ uid rid rstat vstat }
 # rid can only be a arrayref with UPDATE
  my($s, %o) = @_;
  my %s = (
    defined $o{rstat} ? ( 'rstat = ?', $o{rstat} ) : (),
    defined $o{vstat} ? ( 'vstat = ?', $o{vstat} ) : (),
  );
  $o{rstat}||=0;
  $o{vstat}||=0;

    $s->DBExec(q|UPDATE rlists !H WHERE uid = ? AND rid IN(!l)|,
      \%s, $o{uid}, ref($o{rid}) eq 'ARRAY' ? $o{rid} : [ $o{rid} ])
  ||
    $s->DBExec(q|INSERT INTO rlists (uid, rid, rstat, vstat)
      VALUES(!l)|,
      [@o{qw| uid rid rstat vstat |}]);
}


sub DBDelRList { # uid, \@rids
  my($s, $uid, $rid) = @_;
  $s->DBExec(q|DELETE FROM rlists WHERE uid = ? AND rid IN(!l)|, $uid, ref($rid) eq 'ARRAY' ? $rid : [ $rid ]);
}





#-----------------------------------------------------------------------------#
#                        V I S U A L   N O V E L S                            #
#-----------------------------------------------------------------------------#


sub DBGetVN { # %options->{ id rev char search order results page what cati cate lang platform }
  my $s = shift;
  my %o = (
    page => 1,
    results => 50,
    order => 'vr.title ASC',
    what => '',
    @_ );

  my %where = (
    !$o{id} && !$o{rev} ? ( # don't fetch hidden items unless we ask for an ID
      'v.hidden = ?' => 0 ) : (),
    $o{id} && !ref($o{id}) ? (
      'v.id = ?' => $o{id} ) : (),
    $o{id} && ref($o{id}) ? (
      'v.id IN(!l)' => [$o{id}] ) : (),
    $o{rev} ? (
      'c.rev = ?' => $o{rev} ) : (),
    $o{char} ? (
      'LOWER(SUBSTR(vr.title, 1, 1)) = ?' => $o{char} ) : (),
    defined $o{char} && !$o{char} ? (
      '(ASCII(vr.title) < 97 OR ASCII(vr.title) > 122) AND (ASCII(vr.title) < 65 OR ASCII(vr.title) > 90)' => 1 ) : (),
    $o{cati} && @{$o{cati}} ? ( q|
      v.id IN(SELECT iv.id
        FROM vn_categories ivc
        JOIN vn iv ON iv.latest = ivc.vid
        WHERE cat IN(!l)
        GROUP BY iv.id
        HAVING COUNT(cat) = ?)| => [ $o{cati}, $#{$o{cati}}+1 ] ) : (),
    $o{cate} && @{$o{cate}} ? ( q|
      v.id NOT IN(SELECT iv.id
        FROM vn_categories ivc
        JOIN vn iv ON iv.latest = ivc.vid
        WHERE cat IN(!l)
        GROUP BY iv.id)| => [ $o{cate} ] ) : (),
   # this needs some proper handling...
    $o{lang} && @{$o{lang}} ? (
      '('.join(' OR ', map "v.c_languages ILIKE '%%$_%%'", @{$o{lang}}).')' => 1 ) : (),
    $o{platform} && @{$o{platform}} ? (
      '('.join(' OR ', map "v.c_platforms ILIKE '%%$_%%'", @{$o{platform}}).')' => 1 ) : (),
  );

  if($o{search}) {
    my @w;
    for (split /[ -,]/, $o{search}) {
      s/%//g;
      next if length($_) < 2;
      if(VNDB::GTINType($_)) {
        push @w, 'irr.gtin = ?', $_;
      } else {
        $_ = "%$_%";
        push @w, '(ivr.title ILIKE ? OR ivr.alias ILIKE ? OR irr.title ILIKE ? OR irr.original ILIKE ?)',
          [ $_, $_, $_, $_ ];
      } 
    }
    $where{ q|
      v.id IN(SELECT iv.id
        FROM vn iv
        JOIN vn_rev ivr ON iv.latest = ivr.id
        LEFT JOIN releases_vn irv ON irv.vid = iv.id
        LEFT JOIN releases_rev irr ON irr.id = irv.rid
        LEFT JOIN releases ir ON ir.latest = irr.id
        !W
        GROUP BY iv.id)| } = [ \@w ] if @w;
  }

  my @join = (
    $o{rev} ?
      'JOIN vn v ON v.id = vr.vid' :
      'JOIN vn v ON vr.id = v.latest',
    $o{what} =~ /changes/ || $o{rev} ? (
      'JOIN changes c ON c.id = vr.id',
      'JOIN users u ON u.id = c.requester' ) : (),
    $o{what} =~ /relgraph/ ? (
      'LEFT JOIN relgraph rg ON rg.id = v.rgraph' ) : (),
  );

  my $sel = 'v.id, v.locked, v.hidden, v.c_released, v.c_languages, v.c_platforms, vr.title, vr.original, vr.id AS cid';
  $sel .= ', vr.alias, vr.image AS image, vr.img_nsfw, vr.length, vr.desc, vr.l_wp, vr.l_encubed, vr.l_renai, vr.l_vnn' if $o{what} =~ /extended/;
  $sel .= ', c.added, c.requester, c.comments, v.latest, u.username, c.rev, c.causedby' if $o{what} =~ /changes/;
  $sel .= ', v.rgraph, rg.cmap' if $o{what} =~ /relgraph/;

  my $r = $s->DBAll(qq|
    SELECT $sel
      FROM vn_rev vr
      @join
      !W
      ORDER BY !s
      LIMIT ? OFFSET ?|,
    \%where,
    $o{order},
    $o{results}+(wantarray?1:0), $o{results}*($o{page}-1)
  );
  $_->{c_released} = sprintf '%08d', $_->{c_released} for @$r;

  if($o{what} =~ /(?:relations|categories|anime|screenshots)/ && $#$r >= 0) {
    my %r = map {
      $r->[$_]{relations} = [];
      $r->[$_]{categories} = [];
      $r->[$_]{anime} = [];
      $r->[$_]{screenshots} = [];
      ($r->[$_]{cid}, $_)
    } 0..$#$r;
    
    if($o{what} =~ /categories/) {
      push(@{$r->[$r{$_->{vid}}]{categories}}, [ $_->{cat}, $_->{lvl} ]) for (@{$s->DBAll(q|
        SELECT vid, cat, lvl
          FROM vn_categories
          WHERE vid IN(!l)|,
        [ keys %r ]
      )});
    }

    if($o{what} =~ /anime/) {
      push(@{$r->[$r{$_->{vid}}]{anime}}, $_) && delete $_->{vid} for (@{$s->DBAll(q|
        SELECT va.vid, a.*
          FROM vn_anime va
          JOIN anime a ON va.aid = a.id
          WHERE va.vid IN(!l)|,
        [ keys %r ]
      )});
    }

    if($o{what} =~ /screenshots/) {
      push(@{$r->[$r{$_->{vid}}]{screenshots}}, $_) && delete $_->{vid} for (@{$s->DBAll(q|
        SELECT vs.vid, s.id, vs.nsfw, vs.rid, s.width, s.height
          FROM vn_screenshots vs
          JOIN screenshots s ON vs.scr = s.id
          WHERE vs.vid IN(!l)
          ORDER BY vs.scr|,
        [ keys %r ]
      )});
    }

    if($o{what} =~ /relations/) {
      my $rel = $s->DBAll(q|
        SELECT rel.vid1, rel.vid2, rel.relation, vr.title, vr.original
          FROM vn_relations rel
          JOIN vn v ON rel.vid2 = v.id
          JOIN vn_rev vr ON v.latest = vr.id
          WHERE rel.vid1 IN(!l)|,
        [ keys %r ]);
      push(@{$r->[$r{$_->{vid1}}]{relations}}, {
        relation => $_->{relation},
        id => $_->{vid2},
        title => $_->{title},
        original => $_->{original}
      }) for (@$rel);
    }
  }

  return $r if !wantarray;
  return ($r, 0) if $#$r != $o{results};
  pop @$r;
  return ($r, 1);
}  


sub DBAddVN { # %options->{ comm + _insert_vn_rev }
  my($s, %o) = @_;

  my $id = $s->DBRow(q|
    INSERT INTO changes (type, requester, ip, comments)
      VALUES (!l)
      RETURNING id|,
    [ 0, $s->AuthInfo->{id}, $s->ReqIP, $o{comm} ]
  )->{id};

  my $vid = $s->DBRow(q|
    INSERT INTO vn (latest)
      VALUES (?)
      RETURNING id|, $id
  )->{id};

  _insert_vn_rev($s, $id, $vid, \%o);

  return ($vid, $id); # item id, global revision
}


sub DBEditVN { # id, %options->( comm + _insert_vn_rev + uid + causedby }
  my($s, $vid, %o) = @_;

  my $c = $s->DBRow(q|
    INSERT INTO changes (type, requester, ip, comments, rev, causedby)
      VALUES (?, ?, ?, ?, (
        SELECT c.rev+1
        FROM changes c
        JOIN vn_rev vr ON vr.id = c.id
        WHERE vr.vid = ?
        ORDER BY c.id DESC
        LIMIT 1
      ), ?)
      RETURNING id, rev|,
    0, $o{uid}||$s->AuthInfo->{id}, $s->ReqIP, $o{comm}, $vid, $o{causedby}||undef);

  _insert_vn_rev($s, $c->{id}, $vid, \%o);

  $s->DBExec(q|UPDATE vn SET latest = ? WHERE id = ?|, $c->{id}, $vid);
  return ($c->{rev}, $c->{id}); # local revision, global revision
}


sub _insert_vn_rev { # columns in vn_rev + categories + screenshots + relations
  my($s, $cid, $vid, $o) = @_;

  $$o{img_nsfw} = $$o{img_nsfw}?1:0;
  $s->DBExec(q|
    INSERT INTO vn_rev (id, vid, title, original, "desc", alias, image, img_nsfw, length, l_wp, l_encubed, l_renai, l_vnn)
      VALUES (!l)|,
    [ $cid, $vid, @$o{qw|title original desc alias image img_nsfw length l_wp l_encubed l_renai l_vnn|} ]);

  $s->DBExec(q|
    INSERT INTO vn_categories (vid, cat, lvl)
      VALUES (?, ?, ?)|,
    $cid, $_->[0], $_->[1]
  ) for (@{$o->{categories}});

  $s->DBExec(q|
    INSERT INTO vn_screenshots (vid, scr, nsfw, rid)
      VALUES (?, ?, ?, ?)|,
    $cid, $_->[0], $_->[1]?1:0, $_->[2]
  ) for (@{$o->{screenshots}});

  $s->DBExec(q|
    INSERT INTO vn_relations (vid1, vid2, relation)
      VALUES (?, ?, ?)|,
    $cid, $_->[1], $_->[0]
  ) for (@{$o->{relations}});

  if(@{$o->{anime}}) {
    $s->DBExec(q|
      INSERT INTO vn_anime (vid, aid)
        VALUES (?, ?)|,
      $cid, $_
    ) for (@{$o->{anime}});

    # insert unknown anime
    my $a = $s->DBAll(q|
      SELECT id FROM anime WHERE id IN(!l)|,
      $o->{anime});
    $s->DBExec(q|
      INSERT INTO anime (id) VALUES (?)|, $_
    ) for (grep {
      my $ia = $_;
      !(scalar grep $ia == $_->{id}, @$a)
    } @{$o->{anime}});
  }
}


sub DBHideVN { # id, hidden
  my($s, $id, $h) = @_;
  $s->DBExec(q|
    UPDATE vn 
      SET hidden = ?
      WHERE id = ?|,
    $h?1:0, $id);
}


sub DBVNCache { # @vids
  my($s,@vn) = @_;
  $s->DBExec('SELECT update_vncache(?)', $_) for (@vn);
}





#-----------------------------------------------------------------------------#
#                              R E L E A S E S                                #
#-----------------------------------------------------------------------------#


sub DBGetRelease { # %options->{ id vid results page rev }
  my($s, %o) = @_;

  $o{results} ||= 50;
  $o{page} ||= 1;
  $o{what} ||= '';
  $o{order} ||= 'rr.released ASC';
  my %where = (
    !$o{id} && !$o{rev} ? (
      'r.hidden = ?' => 0 ) : (),
    $o{id} ? (
      'r.id = ?' => $o{id} ) : (),
    $o{rev} ? (
      'c.rev = ?' => $o{rev} ) : (),
    $o{vid} ? (
      'rv.vid = ?' => $o{vid} ) : (),
    defined $o{unreleased} ? (
      q|rr.released !s TO_CHAR('today'::timestamp, 'YYYYMMDD')::integer| => $o{unreleased} ? '>' : '<=' ) : (),
  );

  my @join;
  push @join, $o{rev} ? 'JOIN releases r ON r.id = rr.rid' : 'JOIN releases r ON rr.id = r.latest';
  push @join, 'JOIN changes c ON c.id = rr.id' if $o{what} =~ /changes/ || $o{rev};
  push @join, 'JOIN users u ON u.id = c.requester' if $o{what} =~ /changes/;
  push @join, 'JOIN releases_vn rv ON rv.rid = rr.id' if $o{vid};

  my $select = 'r.id, r.locked, r.hidden, rr.id AS cid, rr.title, rr.original, rr.gtin, rr.language, rr.website, rr.released, rr.notes, rr.minage, rr.type';
  $select .= ', c.added, c.requester, c.comments, r.latest, u.username, c.rev' if $o{what} =~ /changes/;

  my $r = $s->DBAll(qq|
    SELECT $select
      FROM releases_rev rr
      @join
      !W
      ORDER BY !s
      LIMIT ? OFFSET ?|,
    \%where,
    $o{order},
    $o{results}+(wantarray?1:0), $o{results}*($o{page}-1)
  );
  $_->{released} = sprintf '%08d', $_->{released} for @$r;

  if($#$r >= 0 && $o{what} =~ /(vn|producers|platforms|media)/) {
    my %r = map {
      $r->[$_]{producers} = [];
      $r->[$_]{platforms} = [];
      $r->[$_]{media} = [];
      $r->[$_]{vn} = [];
      ($r->[$_]{cid}, $_)
    } 0..$#$r;

    if($o{what} =~ /vn/) {
      push(@{$r->[$r{$_->{rid}}]{vn}}, $_) for (@{$s->DBAll(q|
        SELECT rv.rid, vr.vid, vr.title, vr.original
          FROM releases_vn rv
          JOIN vn v ON v.id = rv.vid
          JOIN vn_rev vr ON vr.id = v.latest
          WHERE rv.rid IN(!l)|,
        [ keys %r ]
      )});
    }

    if($o{what} =~ /producers/) {
      push(@{$r->[$r{$_->{rid}}]{producers}}, $_) for (@{$s->DBAll(q|
        SELECT rp.rid, p.id, pr.name, pr.original, pr.type
          FROM releases_producers rp
          JOIN producers p ON rp.pid = p.id
          JOIN producers_rev pr ON pr.id = p.latest
          WHERE rp.rid IN(!l)|,
        [ keys %r ]
      )});
    }
    if($o{what} =~ /platforms/) {
      push(@{$r->[$r{$_->{rid}}]{platforms}}, $_->{platform}) for (@{$s->DBAll(q|
        SELECT rid, platform
          FROM releases_platforms
          WHERE rid IN(!l)|,
        [ keys %r ]
      )});
    }
    if($o{what} =~ /media/) {
      ($_->{medium}=~s/\s+//||1)&&push(@{$r->[$r{$_->{rid}}]{media}}, $_) for (@{$s->DBAll(q|
        SELECT rid, medium, qty
          FROM releases_media
          WHERE rid IN(!l)|,
        [ keys %r ]
      )});
    }
  }
  
  return $r if !wantarray;
  return ($r, 0) if $#$r < $o{results};
  pop @$r;
  return ($r, 1);
}


sub DBAddRelease { # options -> { comm + _insert_release_rev }
  my($s, %o) = @_;

  my $id = $s->DBRow(q|
    INSERT INTO changes (type, requester, ip, comments)
      VALUES (!l)
      RETURNING id|,
    [ 1, $s->AuthInfo->{id}, $s->ReqIP, $o{comm} ]
  )->{id};

  my $rid = $s->DBRow(q|
    INSERT INTO releases (latest)
      VALUES (?)
      RETURNING id|, $id)->{id};

  _insert_release_rev($s, $id, $rid, \%o);
  return ($rid, $id); # item id, global revision
}


sub DBEditRelease { # id, %opts->{ comm + _insert_release_rev }
  my($s, $rid, %o) = @_;

  my $c = $s->DBRow(q|
    INSERT INTO changes (type, requester, ip, comments, rev)
      VALUES (?, ?, ?, ?, (
        SELECT c.rev+1
        FROM changes c
        JOIN releases_rev rr ON rr.id = c.id
        WHERE rr.rid = ?
        ORDER BY c.id DESC
        LIMIT 1
      ))
      RETURNING id, rev|,
    1, $s->AuthInfo->{id}, $s->ReqIP, $o{comm}, $rid);

  _insert_release_rev($s, $c->{id}, $rid, \%o);

  $s->DBExec(q|UPDATE releases SET latest = ? WHERE id = ?|, $c->{id}, $rid);
  return ($c->{rev}, $c->{id}); # local revision, global revision
}


sub _insert_release_rev { # %option->{ columns in releases_rev + producers + platforms + vn + media }
  my($s, $cid, $rid, $o) = @_;

  $s->DBExec(q|
    INSERT INTO releases_rev (id, rid, title, original, gtin, language, website, released, notes, minage, type)
      VALUES (!l)|,
    [ $cid, $rid, @$o{qw| title original gtin language website released notes minage type|} ]);

  $s->DBExec(q|
    INSERT INTO releases_producers (rid, pid)
      VALUES (?, ?)|,
    $cid, $_
  ) for (@{$o->{producers}});

  $s->DBExec(q|
    INSERT INTO releases_platforms (rid, platform)
      VALUES (?, ?)|,
    $cid, $_
  ) for (@{$o->{platforms}});

  $s->DBExec(q|
    INSERT INTO releases_vn (rid, vid)
      VALUES (?, ?)|,
    $cid, $_
  ) for (@{$o->{vn}});

  $s->DBExec(q|
    INSERT INTO releases_media (rid, medium, qty)
      VALUES (?, ?, ?)|,
    $cid, $_->[0], $_->[1]
  ) for (@{$o->{media}});
}


sub DBHideRelease { # id, hidden
  my($s, $id, $h) = @_;
  $s->DBExec(q|
    UPDATE releases 
      SET hidden = ?
      WHERE id = ?|,
    $h?1:0, $id);
}



#-----------------------------------------------------------------------------#
#                             P R O D U C E R S                               #
#-----------------------------------------------------------------------------#


sub DBGetProducer { # %options->{ id search char results page rev }
  my($s, %o) = @_;

  $o{results} ||= 50;
  $o{page} ||= 1;
  $o{search} =~ s/%//g if $o{search};
  $o{what} ||= '';
  my %where = (
    !$o{id} && !$o{rev} ? (
      'p.hidden = ?' => 0 ) : (),
    $o{id} ? (
      'p.id = ?' => $o{id} ) : (),
    $o{search} ? (
      '(pr.name ILIKE ? OR pr.original ILIKE ?)', [ '%%'.$o{search}.'%%', '%%'.$o{search}.'%%' ] ) : (),
    $o{char} ? (
      'LOWER(SUBSTR(pr.name, 1, 1)) = ?' => $o{char} ) : (),
    defined $o{char} && !$o{char} ? (
      '(ASCII(pr.name) < 97 OR ASCII(pr.name) > 122) AND (ASCII(pr.name) < 65 OR ASCII(pr.name) > 90)' => 1 ) : (),
    $o{rev} ? (
      'c.rev = ?' => $o{rev} ) : (),
  );

  my @join;
  push @join, $o{rev} ? 'JOIN producers p ON p.id = pr.pid' : 'JOIN producers p ON pr.id = p.latest';
  push @join, 'JOIN changes c ON c.id = pr.id' if $o{what} =~ /changes/ || $o{rev};
  push @join, 'JOIN users u ON u.id = c.requester' if $o{what} =~ /changes/;

  my $select = 'p.id, p.locked, p.hidden, pr.type, pr.name, pr.original, pr.website, pr.lang, pr.desc';
  $select .= ', c.added, c.requester, c.comments, p.latest, pr.id AS cid, u.username, c.rev' if $o{what} =~ /changes/;

  my $r = $s->DBAll(qq|
    SELECT $select
      FROM producers_rev pr
      @join
      !W
      ORDER BY pr.name ASC
      LIMIT ? OFFSET ?|,
    \%where,
    $o{results}+(wantarray?1:0), $o{results}*($o{page}-1)
  );
  
  return $r if !wantarray;
  return ($r, 0) if $#$r < $o{results};
  pop @$r;
  return ($r, 1);
}


sub DBGetProducerVN { # pid
  return $_[0]->DBAll(q|
    SELECT v.id, MAX(vr.title) AS title, MAX(vr.original) AS original, MIN(rr.released) AS date
      FROM releases_producers vp
      JOIN releases_rev rr ON rr.id = vp.rid
      JOIN releases r ON r.latest = rr.id
      JOIN releases_vn rv ON rv.rid = rr.id
      JOIN vn v ON v.id = rv.vid
      JOIN vn_rev vr ON vr.id = v.latest
      WHERE vp.pid = ?
        AND v.hidden = ?
      GROUP BY v.id
      ORDER BY date|,
    $_[1], 0);
}


sub DBAddProducer { # %opts->{ comm + _insert_producer_rev } 
  my($s, %o) = @_;

  my $id = $s->DBRow(q|
    INSERT INTO changes (type, requester, ip, comments)
      VALUES (!l)
      RETURNING id|,
    [ 2, $s->AuthInfo->{id}, $s->ReqIP, $o{comm} ]
  )->{id};

  my $pid = $s->DBRow(q|
    INSERT INTO producers (latest)
      VALUES (?)
      RETURNING id|, $id
  )->{id};

  _insert_producer_rev($s, $id, $pid, \%o);

  return ($pid, $id); # item id, global revision
}


sub DBEditProducer { # id, %opts->{ comm + _insert_producer_rev }
  my($s, $pid, %o) = @_;

  my $c = $s->DBRow(q|
    INSERT INTO changes (type, requester, ip, comments, rev)
      VALUES (?, ?, ?, ?, (
        SELECT c.rev+1
        FROM changes c
        JOIN producers_rev pr ON pr.id = c.id
        WHERE pr.pid = ?
        ORDER BY c.id DESC
        LIMIT 1
      ))
      RETURNING id, rev|,
    2, $s->AuthInfo->{id}, $s->ReqIP, $o{comm}, $pid);

  _insert_producer_rev($s, $c->{id}, $pid, \%o);

  $s->DBExec(q|UPDATE producers SET latest = ? WHERE id = ?|, $c->{id}, $pid);
  return ($c->{rev}, $c->{id}); # local revision, global revision
}


sub _insert_producer_rev { # %opts->{ columns in produces_rev }
  my($s, $cid, $pid, $o) = @_;
  $s->DBExec(q|
    INSERT INTO producers_rev (id, pid, name, original, website, type, lang, "desc")
      VALUES (!l)|,
    [ $cid, $pid, @$o{qw| name original website type lang desc|} ]);
}


sub DBHideProducer { # id, hidden
  my($s, $id, $h) = @_;
  $s->DBExec(q|
    UPDATE producers 
      SET hidden = ?
      WHERE id = ?|,
    $h?1:0, $id);
}





#-----------------------------------------------------------------------------#
#                            D I S C U S S I O N S                            #
#-----------------------------------------------------------------------------#


sub DBGetThreads { # %options->{ id type iid results page what }
  my($s, %o) = @_;

  $o{results} ||= 50;
  $o{page} ||= 1;
  $o{what} ||= '';
  $o{order} ||= 't.id DESC';

  my %where = (
    $o{id} ? (
      't.id = ?' => $o{id} ) : (),
    !$o{id} ? (
      't.hidden = ?' => 0 ) : (),
    $o{type} && !$o{iid} ? (
      't.id IN(SELECT tid FROM threads_tags WHERE type = ?)' => $o{type} ) : (),
    $o{type} && $o{iid} ? (
      'tt.type = ?' => $o{type}, 'tt.iid = ?' => $o{iid} ) : (),
  );

  my $select = 't.id, t.title, t.count, t.locked, t.hidden';
  $select .= ', tp.uid, tp.date, u.username' if $o{what} =~ /firstpost/;
  $select .= ', tp2.uid AS luid, tp2.date AS ldate, u2.username AS lusername' if $o{what} =~ /lastpost/;

  my @join;
  push @join, 'JOIN threads_posts tp ON tp.tid = t.id AND tp.num = 1' if $o{what} =~ /firstpost/;
  push @join, 'JOIN users u ON u.id = tp.uid' if $o{what} =~ /firstpost/;
  push @join, 'JOIN threads_posts tp2 ON tp2.tid = t.id AND tp2.num = t.count' if $o{what} =~ /lastpost/;
  push @join, 'JOIN users u2 ON u2.id = tp2.uid' if $o{what} =~ /lastpost/;
  push @join, 'JOIN threads_tags tt ON tt.tid = t.id' if $o{type} && $o{iid};

  my $r = $s->DBAll(qq|
    SELECT $select
      FROM threads t
      @join
      !W
      ORDER BY !s
      LIMIT ? OFFSET ?|,
    \%where,
    $o{order},
    $o{results}+(wantarray?1:0), $o{results}*($o{page}-1)
  );

  if($o{what} =~ /(tags|tagtitles)/ && $#$r >= 0) {
    my %r = map {
      $r->[$_]{tags} = [];
      ($r->[$_]{id}, $_)
    } 0..$#$r;
    
    if($o{what} =~ /tags/) {
      ($_->{type}=~s/ +//||1) && push(@{$r->[$r{$_->{tid}}]{tags}}, [ $_->{type}, $_->{iid} ]) for (@{$s->DBAll(q|
        SELECT tid, type, iid
          FROM threads_tags
          WHERE tid IN(!l)|,
        [ keys %r ]
      )});
    }
    if($o{what} =~ /tagtitles/) {
      ($_->{type}=~s/ +//||1) && push(@{$r->[$r{$_->{tid}}]{tags}}, [ $_->{type}, $_->{iid}, $_->{title}, $_->{original} ]) for (@{$s->DBAll(q|
        SELECT tt.tid, tt.type, tt.iid, COALESCE(u.username, vr.title, pr.name) AS title, COALESCE(u.username, vr.original, pr.original) AS original
          FROM threads_tags tt
          LEFT JOIN vn v ON tt.type = 'v' AND v.id = tt.iid
          LEFT JOIN vn_rev vr ON vr.id = v.latest
          LEFT JOIN producers p ON tt.type = 'p' AND p.id = tt.iid
          LEFT JOIN producers_rev pr ON pr.id = p.latest
          LEFT JOIN users u ON tt.type = 'u' AND u.id = tt.iid
          WHERE tt.tid IN(!l)|,
        [ keys %r ]
      )});
    }
  }

  return $r if !wantarray;
  return ($r, 0) if $#$r < $o{results};
  pop @$r;
  return ($r, 1);
}


sub DBGetPosts { # %options->{ tid num page results }
  my($s, %o) = @_;
  
  $o{results} ||= 50;
  $o{page} ||= 1;

  my %where = (
    'tp.tid = ?' => $o{tid},
    $o{num} ? (
      'tp.num = ?' => $o{num} ) : (),
  );

  my $r = $s->DBAll(q|
    SELECT tp.num, tp.date, tp.edited, tp.msg, tp.hidden, tp.uid, u.username
      FROM threads_posts tp
      JOIN users u ON u.id = tp.uid
      !W
      ORDER BY tp.num ASC
      LIMIT ? OFFSET ?|,
    \%where,
    $o{results}, $o{results}*($o{page}-1)
  );

  return $r if !wantarray;
}


sub DBAddPost { # %options->{ tid uid msg num }
  my($s, %o) = @_;

  $o{num} ||= $s->DBRow('SELECT num FROM threads_posts WHERE tid = ? ORDER BY num DESC LIMIT 1', $o{tid})->{num}+1;
  $o{uid} ||= $s->AuthInfo->{id};

  $s->DBExec(q|
    INSERT INTO threads_posts (tid, num, uid, msg)
      VALUES(?, ?, ?, ?)|,
    @o{qw| tid num uid msg |}
  );
  $s->DBExec(q|
    UPDATE threads
      SET count = count+1
      WHERE id = ?|,
    $o{tid});

  return $o{num};
}


sub DBEditPost { # %options->{ tid num msg hidden }
  my($s, %o) = @_;

  my %set = (
    'msg = ?' => $o{msg},
    'edited = ?' => time,
    'hidden = ?' => $o{hidden}?1:0,
  );

  $s->DBExec(q|
    UPDATE threads_posts
      !H
      WHERE tid = ?
        AND num = ?|,
     \%set, $o{tid}, $o{num}
  );
}


sub DBEditThread { # %options->{ id title locked hidden tags }
  my($s, %o) = @_;

  my %set = (
    'title = ?' => $o{title},
    'locked = ?' => $o{locked}?1:0,
    'hidden = ?' => $o{hidden}?1:0,
  );

  $s->DBExec(q|
    UPDATE threads
      !H
      WHERE id = ?|,
     \%set, $o{id});

  if($o{tags}) {
    $s->DBExec('DELETE FROM threads_tags WHERE tid = ?', $o{id});
    $s->DBExec(q|
      INSERT INTO threads_tags (tid, type, iid)
        VALUES (?, ?, ?)|,
      $o{id}, $_->[0], $_->[1]||0
    ) for (@{$o{tags}});
  }
}


sub DBAddThread { # %options->{ title hidden locked tags }
  my($s, %o) = @_;

  my $id = $s->DBRow(q|
    INSERT INTO threads (title, hidden, locked)
      VALUES (?, ?, ?)
      RETURNING id|,
      $o{title}, $o{hidden}?1:0, $o{locked}?1:0
    )->{id};

  $s->DBExec(q|
    INSERT INTO threads_tags (tid, type, iid)
      VALUES (?, ?, ?)|,
    $id, $_->[0], $_->[1]
  ) for (@{$o{tags}});

  return $id;
}





#-----------------------------------------------------------------------------#
#                              U T I L I T I E S                              #
#-----------------------------------------------------------------------------#


sub DBExec { return sqlhelper(shift, 0, @_); }
sub DBRow  { return sqlhelper(shift, 1, @_); }
sub DBAll  { return sqlhelper(shift, 2, @_); }

sub sqlhelper { # type, query, @list
  my $self = shift;
  my $type = shift;
  my $sqlq = shift;
  my $s = $self->{_DB}->{sql};

  my $start = [Time::HiRes::gettimeofday()] if $self->{debug};

  $sqlq =~ s/\r?\n/ /g;
  $sqlq =~ s/  +/ /g;
  my(@q) = @_ ? sqlprint(0, $sqlq, @_) : ($sqlq);
  #warn join(', ', map "'$_'", @q)."\n";

  my $q = $s->prepare($q[0]);
  $q->execute($#q ? @q[1..$#q] : ());
  my $r = $type == 1 ? $q->fetchrow_hashref :
          $type == 2 ? $q->fetchall_arrayref({}) :
                       $q->rows;
  $q->finish();

  push(@{$self->{_DB}->{Queries}}, [ $q[0], Time::HiRes::tv_interval($start), @q[1..$#q] ]) if $self->{debug};

  $r = 0  if $type == 0 && !$r;
  $r = {} if $type == 1 && (!$r || ref($r) ne 'HASH');
  $r = [] if $type == 2 && (!$r || ref($r) ne 'ARRAY');

  return $r;
}


# sqlprint:
#   ?    normal placeholder
#   !l   list of placeholders, expects arrayref
#   !H   list of SET-items, expects hashref or arrayref: format => (bind_value || \@bind_values)
#   !W   same as !H, but for WHERE clauses (AND'ed together)
#   !s   the classic sprintf %s, use with care
# This isn't sprintf, so all other things won't work,
# Only the ? placeholder is supported, so no dollar sign numbers or named placeholders
# Indeed, this also means you can't use PgSQL operators containing a question mark

sub sqlprint { # start, query, bind values. Returns new query + bind values
  my @a;
  my $q='';
  my $s = shift;
  for my $p (split /(\?|![lHWs])/, shift) {
    next if !defined $p;
    if($p eq '?') {
      push @a, shift;
      $q .= '$'.(@a+$s);
    } elsif($p eq '!s') {
      $q .= shift;
    } elsif($p eq '!l') {
      my $l = shift;
      $q .= join ', ', map '$'.(@a+$s+$_+1), 0..$#$l;
      push @a, @$l;
    } elsif($p eq '!H' || $p eq '!W') {
      my $h=shift;
      my @h=ref $h eq 'HASH' ? %$h : @$h;
      my @r;
      while(my($k,$v) = (shift(@h), shift(@h))) {
        last if !defined $k;
        my($n,@l) = sqlprint($#a+1, $k, ref $v eq 'ARRAY' ? @$v : $v);
        push @r, $n;
        push @a, @l;
      }
      $q .= ($p eq '!W' ? 'WHERE ' : 'SET ').join $p eq '!W' ? ' AND ' : ', ', @r
        if @r;
    } else {
      $q .= $p;
    }
  }
  return($q, @a);
}

1;

