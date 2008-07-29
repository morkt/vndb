
package VNDB::Util::DB;

use strict;
use warnings;
use DBI;
use Exporter 'import';
use Storable 'nfreeze', 'thaw';

use vars ('$VERSION', '@EXPORT');
$VERSION = $VNDB::VERSION;

@EXPORT = qw|
  DBInit DBCheck DBCommit DBRollBack DBExit
  DBLanguageCount DBCategoryCount DBTableCount DBGetHist DBLockItem DBIncId
  DBGetUser DBAddUser DBUpdateUser DBDelUser
  DBGetVotes DBVoteStats DBAddVote DBDelVote
  DBGetVNList DBDelVNList
  DBGetRList DBGetRLists DBEditRList DBDelRList
  DBGetVN DBAddVN DBEditVN DBHideVN DBUndefRG DBVNCache
  DBGetRelease DBAddRelease DBEditRelease DBHideRelease
  DBGetProducer DBGetProducerVN DBAddProducer DBEditProducer DBHideProducer
  DBGetThreads DBGetPosts DBAddPost DBEditPost DBEditThread DBAddThread
  DBExec DBRow DBAll DBLastId
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
      WHERE v.hidden = 0
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
      WHERE r.hidden = 0
        AND v.hidden = 0
        AND rr.type <> 2
        AND rr.released <= TO_CHAR('today'::timestamp, 'YYYYMMDD')::integer
      GROUP BY rr.language|)} };
}


sub DBTableCount { # table (users, producers, vn, releases, votes)
  return $_[0]->DBRow(q|
    SELECT COUNT(*) as cnt
      FROM %s
      %s|,
    $_[1],
    $_[1] =~ /producers|vn|releases/ ? 'WHERE hidden = 0' : '',
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
      'c.id IN(!l)' => $o{cid} ) : (),
    $o{type} eq 'u' ? (
      'c.requester = %d' => $o{id} ) : (),

    $o{type} eq 'v' && !$o{releases} ? ( 'c.type = 0' => 1,
      $o{id} ? ( 'vr.vid = %d' => $o{id} ) : () ) : (),
    $o{type} eq 'v' && $o{releases} ? (
      '((c.type = 0 AND vr.vid = %d) OR (c.type = 1 AND rv.vid = %1$d))' => $o{id} ) : (),
    
    $o{type} eq 'r' ? ( 'c.type = 1' => 1,
      $o{id} ? ( 'rr.rid = %d' => $o{id} ) : () ) : (),
    $o{type} eq 'p' ? ( 'c.type = 2' => 1,
      $o{id} ? ( 'pr.pid = %d' => $o{id} ) : () ) : (),

    $o{caused} ? (
      'c.causedby = %d' => $o{caused} ) : (),
    $o{ip} ? (
      'c.ip = !s' => $o{ip} ) : (),
    defined $o{edits} && !$o{edits} ? (
      'c.rev = 1' => 1 ) : (),
    $o{edits} ? (
      'c.rev > 1' => 1 ) : (),

   # get rid of 'hidden' items
    !$o{showhid} ? (
      '(v.hidden IS NOT NULL AND v.hidden = 0 OR r.hidden IS NOT NULL AND r.hidden = 0 OR p.hidden IS NOT NULL AND p.hidden = 0)' => 1,
    ) : $o{showhid} == 2 ? (
      '(v.hidden IS NOT NULL AND v.hidden = 1 OR r.hidden IS NOT NULL AND r.hidden = 1 OR p.hidden IS NOT NULL AND p.hidden = 1)' => 1,
    ) : (),
  );

  my $where = keys %where ? 'WHERE !W' : '';

  my $select = 'c.id, c.type, c.added, c.requester, c.comments, c.rev, c.causedby';
  $select .= ', u.username' if $o{what} =~ /user/;
  $select .= ', COALESCE(vr.vid, rr.rid, pr.pid) AS iid' if $o{what} =~ /iid/;
  $select .= ', COALESCE(vr2.title, rr2.title, pr2.name) AS ititle' if $o{what} =~ /ititle/;

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
      $where
      ORDER BY c.id %s
      LIMIT %d OFFSET %d|,
    $where ? \%where : (),
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
    UPDATE %s
      SET locked = %d
      WHERE id = %d|,
    $tbl, $l, $id);
}


sub DBIncId { # sequence (this is a rather low-level function... aww heck...)
  return $_[0]->DBRow(q|SELECT nextval(!s) AS ni|, $_[1])->{ni};
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
    $o{username} ? (
      'username = !s' => $o{username} ) : (),
    $o{mail} ? (
      'mail = !s' => $o{mail} ) : (),
    $o{passwd} ? (
      'passwd = decode(!s, \'hex\')' => $o{passwd} ) : (),
    $o{firstchar} ? (
      'SUBSTRING(username from 1 for 1) = !s' => $o{firstchar} ) : (),
    !$o{firstchar} && defined $o{firstchar} ? (
      'ASCII(username) < 97 OR ASCII(username) > 122' => 1 ) : (),
    $o{uid} ? (
      'id = %d' => $o{uid} ) : (),
    !$o{uid} && !$o{username} ? (
      'id > 0' => 1 ) : (),
  );

  my $where = keys %where ? 'AND !W' : '';
  my $r = $s->DBAll(qq|
    SELECT *
      FROM users u
      WHERE id > 0 $where
      ORDER BY %s
      LIMIT %d OFFSET %d|,
    $where ? \%where : (),
    $o{order},
    $o{results}+(wantarray?1:0), $o{results}*($o{page}-1)
  );

  if($o{what} =~ /list/ && $#$r >= 0) {
    my %r = map {
      $r->[$_]{votes} = 0;
      $r->[$_]{vnlist} = 0;
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
      VALUES (!s, decode(!s, 'hex'), !s, %d, %d)|,
    lc($_[1]), $_[2], $_[3], $_[4], time
  );
}


sub DBUpdateUser { # uid, %options->{ columns in users table }
  my $s = shift;
  my $user = shift;
  my %opt = @_;
  my %h;

  defined $opt{$_} && ($h{$_.' = !s'} = $opt{$_})
    for (qw| username mail |);
  defined $opt{$_} && ($h{$_.' = %d'} = $opt{$_})
    for (qw| rank flags |);
  $h{'passwd = decode(!s, \'hex\')'} = $opt{passwd}
    if defined $opt{passwd};

  return 0 if scalar keys %h <= 0;
  return $s->DBExec(q|
    UPDATE users
      SET !H
      WHERE id = %d|,
    \%h, $user);
}


sub DBDelUser { # uid
  my($s, $id) = @_;
  $s->DBExec($_, $id) for (
    q|DELETE FROM vnlists WHERE uid = %d|,
    q|DELETE FROM rlists WHERE uid = %d|,
    q|DELETE FROM votes WHERE uid = %d|,
    q|UPDATE changes SET requester = 0 WHERE requester = %d|,
    q|UPDATE threads_posts SET uid = 0 WHERE uid = %d|,
    q|DELETE FROM users WHERE id = %d|
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
    $o{uid} ? ( 'n.uid = %d' => $o{uid} ) : (),
    $o{vid} ? ( 'n.vid = %d' => $o{vid} ) : (),
    $o{hide} ? ( 'u.flags & %d = %1$d' => $VNDB::UFLAGS->{list} ) : (),
  );

  my $where = scalar keys %where ? 'WHERE !W' : '';
  my $r = $s->DBAll(qq|
    SELECT n.vid, vr.title, n.vote, n.date, n.uid, u.username
      FROM votes n
      JOIN vn v ON v.id = n.vid
      JOIN vn_rev vr ON vr.id = v.latest
      JOIN users u ON u.id = n.uid
      $where
      ORDER BY %s
      LIMIT %d OFFSET %d|,
    $where ? \%where : (),
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
  my $r = [ qw| 0 0 0 0 0 0 0 0 0 0 | ],
  my $where = $col ? 'WHERE '.$col.' = '.$id : '';
  $r->[$_->{vote}-1] = $_->{votes} for (@{$s->DBAll(qq|
    SELECT vote, COUNT(vote) as votes
      FROM votes
      $where
      GROUP BY vote|,
  )});
  return $r;
}


sub DBAddVote { # vid, uid, vote
  $_[0]->DBExec(q|
    UPDATE votes
      SET vote = %d
      WHERE vid = %d
        AND uid = %d|,
    $_[3], $_[1], $_[2]
  ) || $_[0]->DBExec(q|
    INSERT INTO votes
      (vid, uid, vote, date)
      VALUES (%d, %d, %d, %d)|,
    $_[1], $_[2], $_[3], time
  );
  # XXX: performance improvement: let a cron job handle this
}


sub DBDelVote { # uid, vid  # uid = 0 to delete all
  my $uid = $_[1] ? 'uid = '.$_[1].' AND' : '';
  $_[0]->DBExec(q|
    DELETE FROM votes
      WHERE %s vid = %d|,
    $uid, $_[2]);
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
      'l.uid = %d' => $o{uid} ) : (),
    $o{vid} ? (
      'l.vid = %d' => $o{vid} ) : (),
    defined $o{status} ? (
      'l.status = %d' => $o{status} ) : (),
    $o{hide} ? ( 'u.flags & %d = %1$d' => $VNDB::UFLAGS->{list} ) : (),
  );

  return wantarray ? ([], 0) : [] if !keys %where;

  my $r = $s->DBAll(q|
    SELECT l.vid, vr.title, l.status, l.comments, l.date, l.uid, u.username
      FROM vnlists l
      JOIN vn v ON l.vid = v.id
      JOIN vn_rev vr ON vr.id = v.latest
      JOIN users u ON l.uid = u.id
      WHERE !W
      ORDER BY %s
      LIMIT %d OFFSET %d|,
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
  $uid = $uid ? 'uid = '.$uid.' AND ' : '';
  $s->DBExec(q|
    DELETE FROM vnlists
      WHERE %s vid IN(!l)|,
    $uid, \@vid
  );
}





#-----------------------------------------------------------------------------#
#                    U S E R   R E L E A S E   L I S T S                      #
#-----------------------------------------------------------------------------#


sub DBGetRList { # %options->{ uid rids }
  my($s, %o) = @_;

  my %where = (
    'uid = %d' => $o{uid},
    $o{rids} ? (
      'rid IN(!l)' => $o{rids} ) : (),
  );
  
  return $s->DBAll(q|
    SELECT uid, rid, rstat, vstat
      FROM rlists
      WHERE !W|,
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
      WHERE !W
    )| if !$o{voted};
  $where = '('.$where.') AND LOWER(SUBSTR(vr.title, 1, 1)) = \''.$o{char}.'\'' if $o{char};
  $where = '('.$where.') AND (ASCII(vr.title) < 97 OR ASCII(vr.title) > 122) AND (ASCII(vr.title) < 65 OR ASCII(vr.title) > 90)' if defined $o{char} && !$o{char};

 # WHERE clause for the rlists subquery
  my %where = (
    'uid = %d' => $o{uid},
    defined $o{rstat} ? ( 'rstat = %d' => $o{rstat} ) : (),
    defined $o{vstat} ? ( 'vstat = %d' => $o{vstat} ) : (),
  );

  my $r = $s->DBAll(qq|
    SELECT vr.vid, vr.title, v.c_released, v.c_languages, v.c_platforms, COALESCE(vo.vote, 0) AS vote
      FROM vn v
      JOIN vn_rev vr ON vr.id = v.latest
      %s JOIN votes vo ON vo.vid = v.id AND vo.uid = %d
      WHERE $where
      ORDER BY %s
      LIMIT %d OFFSET %d|,
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
        WHERE rl.uid = %d
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
    defined $o{rstat} ? ( 'rstat = %d', $o{rstat} ) : (),
    defined $o{vstat} ? ( 'vstat = %d', $o{vstat} ) : (),
  );
  $o{rstat}||=0;
  $o{vstat}||=0;

    $s->DBExec(q|UPDATE rlists SET !H WHERE uid = %d AND rid IN(!l)|,
      \%s, $o{uid}, ref($o{rid}) eq 'ARRAY' ? $o{rid} : [ $o{rid} ])
  ||
    $s->DBExec(q|INSERT INTO rlists (uid, rid, rstat, vstat)
      VALUES(%d, %d, %d, %d)|,
      @o{qw| uid rid rstat vstat |});
}


sub DBDelRList { # uid, \@rids
  my($s, $uid, $rid) = @_;
  $s->DBExec(q|DELETE FROM rlists WHERE uid = %d AND rid IN(!l)|, $uid, ref($rid) eq 'ARRAY' ? $rid : [ $rid ]);
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
      'v.hidden = 0' => 1 ) : (),
    $o{id} && !ref($o{id}) ? (
      'v.id = %d' => $o{id} ) : (),
    $o{id} && ref($o{id}) ? (
      'v.id IN(!l)' => $o{id} ) : (),
    $o{rev} ? (
      'c.rev = %d' => $o{rev} ) : (),
    $o{char} ? (
      'LOWER(SUBSTR(vr.title, 1, 1)) = !s' => $o{char} ) : (),
    defined $o{char} && !$o{char} ? (
      '(ASCII(vr.title) < 97 OR ASCII(vr.title) > 122) AND (ASCII(vr.title) < 65 OR ASCII(vr.title) > 90)' => 1 ) : (),
    $o{cati} && @{$o{cati}} ? ( q|
      v.id IN(SELECT iv.id
        FROM vn_categories ivc
        JOIN vn iv ON iv.latest = ivc.vid
        WHERE cat IN(!L)
        GROUP BY iv.id
        HAVING COUNT(cat) = |.($#{$o{cati}}+1).')' => $o{cati} ) : (),
    $o{cate} && @{$o{cate}} ? ( q|
      v.id NOT IN(SELECT iv.id
        FROM vn_categories ivc
        JOIN vn iv ON iv.latest = ivc.vid
        WHERE cat IN(!L)
        GROUP BY iv.id)| => $o{cate} ) : (),
    $o{lang} && @{$o{lang}} ? (
      '('.join(' OR ', map "v.c_languages ILIKE '%%$_%%'", @{$o{lang}}).')' => 1 ) : (),
    $o{platform} && @{$o{platform}} ? (
      '('.join(' OR ', map "v.c_platforms ILIKE '%%$_%%'", @{$o{platform}}).')' => 1 ) : (),
  );

  if($o{search}) {
    my %w;
    for (split /[ -,]/, $o{search}) {
      s/%//g;
      next if length($_) < 2;
      my $gt = VNDB::GTINType($_) ? ' OR irr.gtin = '.$_ : '';
      $w{ sprintf '(ivr.title ILIKE %s OR ivr.alias ILIKE %1$s OR irr.title ILIKE %1$s OR irr.original ILIKE %1$s'.$gt.')',
        qs('%%'.$_.'%%') } = 1;
    }
    $where{ q|
      v.id IN(SELECT iv.id
        FROM vn iv
        JOIN vn_rev ivr ON iv.latest = ivr.id
        LEFT JOIN releases_vn irv ON irv.vid = iv.id
        LEFT JOIN releases_rev irr ON irr.id = irv.rid
        LEFT JOIN releases ir ON ir.latest = irr.id
        WHERE !W
        GROUP BY iv.id)| } = \%w if keys %w;
  }

  my $where = scalar keys %where ? 'WHERE !W' : '';

  my @join = (
    $o{rev} ?
      'JOIN vn v ON v.id = vr.vid' :
      'JOIN vn v ON vr.id = v.latest',
    $o{what} =~ /changes/ || $o{rev} ? (
      'JOIN changes c ON c.id = vr.id',
      'JOIN users u ON u.id = c.requester' ) : (),
  );

  my $sel = 'v.id, v.locked, v.hidden, v.c_released, v.c_languages, v.c_platforms, vr.title, vr.id AS cid, v.rgraph';
  $sel .= ', vr.alias, vr.image AS image, vr.img_nsfw, vr.length, vr.desc, vr.l_wp, vr.l_encubed, vr.l_renai, vr.l_vnn' if $o{what} =~ /extended/;
  $sel .= ', c.added, c.requester, c.comments, v.latest, u.username, c.rev, c.causedby' if $o{what} =~ /changes/;

  my $r = $s->DBAll(qq|
    SELECT $sel
      FROM vn_rev vr
      @join
      $where
      ORDER BY %s
      LIMIT %d OFFSET %d|,
    $where ? \%where : (),
    $o{order},
    $o{results}+(wantarray?1:0), $o{results}*($o{page}-1)
  );
  $_->{c_released} = sprintf '%08d', $_->{c_released} for @$r;

  if($o{what} =~ /(?:relations|categories|anime)/ && $#$r >= 0) {
    my %r = map {
      $r->[$_]{relations} = [];
      $r->[$_]{categories} = [];
      $r->[$_]{anime} = [];
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

    if($o{what} =~ /relations/) {
      my $rel = $s->DBAll(q|
        SELECT rel.vid1, rel.vid2, rel.relation, vr.title
          FROM vn_relations rel
          JOIN vn v ON rel.vid2 = v.id
          JOIN vn_rev vr ON v.latest = vr.id
          WHERE rel.vid1 IN(!l)|,
        [ keys %r ]);
      push(@{$r->[$r{$_->{vid1}}]{relations}}, {
        relation => $_->{relation},
        id => $_->{vid2},
        title => $_->{title}
      }) for (@$rel);
    }
  }

  return $r if !wantarray;
  return ($r, 0) if $#$r != $o{results};
  pop @$r;
  return ($r, 1);
}  


sub DBAddVN { # %options->{ columns in vn_rev + comm + relations + categories + anime }
  my($s, %o) = @_;

  my $id = $s->DBRow(q|
    INSERT INTO changes (type, requester, ip, comments)
      VALUES (%d, %d, !s, !s)
      RETURNING id|,
    0, $s->AuthInfo->{id}, $s->ReqIP, $o{comm}
  )->{id};

  my $vid = $s->DBRow(q|
    INSERT INTO vn (latest)
      VALUES (%d)
      RETURNING id|, $id
  )->{id};

  _insert_vn_rev($s, $id, $vid, \%o);

  return ($vid, $id); # item id, global revision
}


sub DBEditVN { # id, %options->( columns in vn_rev + comm + relations + categories + anime + uid + causedby }
  my($s, $vid, %o) = @_;

  my $c = $s->DBRow(q|
    INSERT INTO changes (type, requester, ip, comments, rev, causedby)
      VALUES (%d, %d, !s, !s, (
        SELECT c.rev+1
        FROM changes c
        JOIN vn_rev vr ON vr.id = c.id
        WHERE vr.vid = %d
        ORDER BY c.id DESC
        LIMIT 1
      ), %d)
      RETURNING id, rev|,
    0, $o{uid}||$s->AuthInfo->{id}, $s->ReqIP, $o{comm}, $vid, $o{causedby}||0);

  _insert_vn_rev($s, $c->{id}, $vid, \%o);

  $s->DBExec(q|UPDATE vn SET latest = %d WHERE id = %d|, $c->{id}, $vid);
  return ($c->{rev}, $c->{id}); # local revision, global revision
}


sub _insert_vn_rev {
  my($s, $cid, $vid, $o) = @_;

  $s->DBExec(q|
    INSERT INTO vn_rev (id, vid, title, "desc", alias, image, img_nsfw, length, l_wp, l_encubed, l_renai, l_vnn)
      VALUES (%d, %d, !s, !s, !s, %d, %d, %d, !s, !s, !s, %d)|,
    $cid, $vid, @$o{qw|title desc alias image img_nsfw length l_wp l_encubed l_renai l_vnn|});

  $s->DBExec(q|
    INSERT INTO vn_categories (vid, cat, lvl)
      VALUES (%d, !s, %d)|,
    $cid, $_->[0], $_->[1]
  ) for (@{$o->{categories}});

  $s->DBExec(q|
    INSERT INTO vn_relations (vid1, vid2, relation)
      VALUES (%d, %d, %d)|,
    $cid, $_->[1], $_->[0]
  ) for (@{$o->{relations}});

  if(@{$o->{anime}}) {
    $s->DBExec(q|
      INSERT INTO vn_anime (vid, aid)
        VALUES (%d, %d)|,
      $cid, $_
    ) for (@{$o->{anime}});

    # insert unknown anime
    my $a = $s->DBAll(q|
      SELECT id FROM anime WHERE id IN(!l)|,
      $o->{anime});
    $s->DBExec(q|
      INSERT INTO anime (id) VALUES (%d)|, $_
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
      SET hidden = %d
      WHERE id = %d|,
    $h, $id);

#  $s->DBExec(q|
#    DELETE FROM vn_relations
#      WHERE vid2 = %d
#         OR vid1 IN(SELECT id FROM vn_rev WHERE vid = %d)|,
#     $id, $id);
#  $s->DBDelVNList(0, $id);
#  $s->DBDelVote(0, $id);
}


sub DBVNCache { # @vids
  my($s,@vn) = @_;
  $s->DBExec('SELECT update_vncache(%d)', $_) for (@vn);
}


sub DBUndefRG { # ids
  my($s, @id) = @_;
  $s->DBExec(q|
    UPDATE vn
      SET rgraph = 0
      WHERE id IN(!l)|,
    \@id);
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
      'r.hidden = 0' => 1 ) : (),
    $o{id} ? (
      'r.id = %d' => $o{id} ) : (),
    $o{rev} ? (
      'c.rev = %d' => $o{rev} ) : (),
    $o{vid} ? (
      'rv.vid = %d' => $o{vid} ) : (),
    defined $o{unreleased} ? (
      q|rr.released %s TO_CHAR('today'::timestamp, 'YYYYMMDD')::integer| => $o{unreleased} ? '>' : '<=' ) : (),
  );

  my $where = scalar keys %where ? 'WHERE !W' : '';
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
      $where
      ORDER BY %s
      LIMIT %d OFFSET %d|,
    $where ? \%where : (),
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
        SELECT rv.rid, vr.vid, vr.title
          FROM releases_vn rv
          JOIN vn v ON v.id = rv.vid
          JOIN vn_rev vr ON vr.id = v.latest
          WHERE rv.rid IN(!l)|,
        [ keys %r ]
      )});
    }

    if($o{what} =~ /producers/) {
      push(@{$r->[$r{$_->{rid}}]{producers}}, $_) for (@{$s->DBAll(q|
        SELECT rp.rid, p.id, pr.name, pr.type
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


sub DBAddRelease { # options -> { columns in releases_rev table + comm + vn + producers + media + platforms }
  my($s, %o) = @_;

  my $id = $s->DBRow(q|
    INSERT INTO changes (type, requester, ip, comments)
      VALUES (%d, %d, !s, !s)
      RETURNING id|,
    1, $s->AuthInfo->{id}, $s->ReqIP, $o{comm}
  )->{id};

  my $rid = $s->DBRow(q|
    INSERT INTO releases (latest)
      VALUES (%d)
      RETURNING id|, $id)->{id};

  _insert_release_rev($s, $id, $rid, \%o);
  return ($rid, $id); # item id, global revision
}


sub DBEditRelease { # id, %opts->{ columns in releases_rev table + comm + vn + producers + media + platforms }
  my($s, $rid, %o) = @_;

  my $c = $s->DBRow(q|
    INSERT INTO changes (type, requester, ip, comments, rev)
      VALUES (%d, %d, !s, !s, (
        SELECT c.rev+1
        FROM changes c
        JOIN releases_rev rr ON rr.id = c.id
        WHERE rr.rid = %d
        ORDER BY c.id DESC
        LIMIT 1
      ))
      RETURNING id, rev|,
    1, $s->AuthInfo->{id}, $s->ReqIP, $o{comm}, $rid);

  _insert_release_rev($s, $c->{id}, $rid, \%o);

  $s->DBExec(q|UPDATE releases SET latest = %d WHERE id = %d|, $c->{id}, $rid);
  return ($c->{rev}, $c->{id}); # local revision, global revision
}


sub _insert_release_rev {
  my($s, $cid, $rid, $o) = @_;

  # most GTIN numbers can't be represented in a 32bit integer, so make sure Perl doesn't interpret it as one (%s, not %d)
  $s->DBExec(q|
    INSERT INTO releases_rev (id, rid, title, original, gtin, language, website, released, notes, minage, type)
      VALUES (%d, %d, !s, !s, %s, !s, !s, %d, !s, %d, %d)|,
    $cid, $rid, @$o{qw| title original gtin language website released notes minage type|});

  $s->DBExec(q|
    INSERT INTO releases_producers (rid, pid)
      VALUES (%d, %d)|,
    $cid, $_
  ) for (@{$o->{producers}});

  $s->DBExec(q|
    INSERT INTO releases_platforms (rid, platform)
      VALUES (%d, !s)|,
    $cid, $_
  ) for (@{$o->{platforms}});

  $s->DBExec(q|
    INSERT INTO releases_vn (rid, vid)
      VALUES (%d, %d)|,
    $cid, $_
  ) for (@{$o->{vn}});

  $s->DBExec(q|
    INSERT INTO releases_media (rid, medium, qty)
      VALUES (%d, !s, %d)|,
    $cid, $_->[0], $_->[1]
  ) for (@{$o->{media}});
}


sub DBHideRelease { # id, hidden
  my($s, $id, $h) = @_;
  $s->DBExec(q|
    UPDATE releases 
      SET hidden = %d
      WHERE id = %d|,
    $h, $id);
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
      'p.hidden = 0' => 1 ) : (),
    $o{id} ? (
      'p.id = %d' => $o{id} ) : (),
    $o{search} ? (
      sprintf('(pr.name ILIKE %s OR pr.original ILIKE %1$s)', qs('%%'.$o{search}.'%%')), 1
    ) : (),
    $o{char} ? (
      'LOWER(SUBSTR(pr.name, 1, 1)) = !s' => $o{char} ) : (),
    defined $o{char} && !$o{char} ? (
      '(ASCII(pr.name) < 97 OR ASCII(pr.name) > 122) AND (ASCII(pr.name) < 65 OR ASCII(pr.name) > 90)' => 1 ) : (),
    $o{rev} ? (
      'c.rev = %d' => $o{rev} ) : (),
  );

  my $where = scalar keys %where ? 'WHERE !W' : '';
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
      $where
      ORDER BY pr.name ASC
      LIMIT %d OFFSET %d|,
    $where ? \%where : (),
    $o{results}+(wantarray?1:0), $o{results}*($o{page}-1)
  );
  
  return $r if !wantarray;
  return ($r, 0) if $#$r < $o{results};
  pop @$r;
  return ($r, 1);
}


# XXX: This query is killing me!
sub DBGetProducerVN { # pid
  return $_[0]->DBAll(q|
    SELECT v.id, MAX(vr.title) AS title, MIN(rr.released) AS date
      FROM releases_producers vp
      JOIN releases_rev rr ON rr.id = vp.rid
      JOIN releases r ON r.latest = rr.id
      JOIN releases_vn rv ON rv.rid = rr.id
      JOIN vn v ON v.id = rv.vid
      JOIN vn_rev vr ON vr.id = v.latest
      WHERE vp.pid = %d
        AND v.hidden = 0
      GROUP BY v.id
      ORDER BY date|,
    $_[1]);
}


sub DBAddProducer { # %opts->{ columns in producers_rev + comm } 
  my($s, %o) = @_;

  my $id = $s->DBRow(q|
    INSERT INTO changes (type, requester, ip, comments)
      VALUES (%d, %d, !s, !s)
      RETURNING id|,
    2, $s->AuthInfo->{id}, $s->ReqIP, $o{comm}
  )->{id};

  my $pid = $s->DBRow(q|
    INSERT INTO producers (latest)
      VALUES (%d)
      RETURNING id|, $id
  )->{id};

  _insert_producer_rev($s, $id, $pid, \%o);

  return ($pid, $id); # item id, global revision
}


sub DBEditProducer { # id, %opts->{ columns in producers_rev + comm }
  my($s, $pid, %o) = @_;

  my $c = $s->DBRow(q|
    INSERT INTO changes (type, requester, ip, comments, rev)
      VALUES (%d, %d, !s, !s, (
        SELECT c.rev+1
        FROM changes c
        JOIN producers_rev pr ON pr.id = c.id
        WHERE pr.pid = %d
        ORDER BY c.id DESC
        LIMIT 1
      ))
      RETURNING id, rev|,
    2, $s->AuthInfo->{id}, $s->ReqIP, $o{comm}, $pid);

  _insert_producer_rev($s, $c->{id}, $pid, \%o);

  $s->DBExec(q|UPDATE producers SET latest = %d WHERE id = %d|, $c->{id}, $pid);
  return ($c->{rev}, $c->{id}); # local revision, global revision
}


sub _insert_producer_rev {
  my($s, $cid, $pid, $o) = @_;
  $s->DBExec(q|
    INSERT INTO producers_rev (id, pid, name, original, website, type, lang, "desc")
      VALUES (%d, %d, !s, !s, !s, !s, !s, !s)|,
    $cid, $pid, @$o{qw| name original website type lang desc|});
}


sub DBHideProducer { # id, hidden
  my($s, $id, $h) = @_;
  $s->DBExec(q|
    UPDATE producers 
      SET hidden = %d
      WHERE id = %d|,
    $h, $id);
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
      't.id = %d' => $o{id} ) : (),
    !$o{id} ? (
      't.hidden = 0' => 1 ) : (),
    $o{type} && !$o{iid} ? (
      't.id IN(SELECT tid FROM threads_tags WHERE type = !s)' => $o{type} ) : (),
    $o{type} && $o{iid} ? (
      'tt.type = !s' => $o{type}, 'tt.iid = %d' => $o{iid} ) : (),
  );
  my $where = scalar keys %where ? 'WHERE !W' : '';

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
      $where
      ORDER BY %s
      LIMIT %d OFFSET %d|,
    $where ? \%where : (),
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
      ($_->{type}=~s/ +//||1) && push(@{$r->[$r{$_->{tid}}]{tags}}, [ $_->{type}, $_->{iid}, $_->{title} ]) for (@{$s->DBAll(q|
        SELECT tt.tid, tt.type, tt.iid, COALESCE(u.username, vr.title, pr.name) AS title
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
    'tp.tid = %d' => $o{tid},
    $o{num} ? (
      'tp.num = %d' => $o{num} ) : (),
  );

  my $r = $s->DBAll(q|
    SELECT tp.num, tp.date, tp.edited, tp.msg, tp.hidden, tp.uid, u.username
      FROM threads_posts tp
      JOIN users u ON u.id = tp.uid
      WHERE !W
      ORDER BY tp.num ASC
      LIMIT %d OFFSET %d|,
    \%where,
    $o{results}, $o{results}*($o{page}-1)
  );

  return $r if !wantarray;
}


sub DBAddPost { # %options->{ tid uid msg num }
  my($s, %o) = @_;

  $o{num} ||= $s->DBRow('SELECT num FROM threads_posts WHERE tid = %d ORDER BY num DESC LIMIT 1', $o{tid})->{num}+1;
  $o{uid} ||= $s->AuthInfo->{id};

  $s->DBExec(q|
    INSERT INTO threads_posts (tid, num, uid, msg)
      VALUES(%d, %d, %d, !s)|,
    @o{qw| tid num uid msg |}
  );
  $s->DBExec(q|
    UPDATE threads
      SET count = count+1
      WHERE id = %d|,
    $o{tid});

  return $o{num};
}


sub DBEditPost { # %options->{ tid num msg hidden }
  my($s, %o) = @_;

  my %set = (
    'msg = !s' => $o{msg},
    'edited = %d' => time,
    'hidden = %d' => $o{hidden}?1:0,
  );

  $s->DBExec(q|
    UPDATE threads_posts
      SET !H
      WHERE tid = %d
        AND num = %d|,
     \%set, $o{tid}, $o{num}
  );
}


sub DBEditThread { # %options->{ id title locked hidden tags }
  my($s, %o) = @_;

  my %set = (
    'title = !s' => $o{title},
    'locked = %d' => $o{locked}?1:0,
    'hidden = %d' => $o{hidden}?1:0,
  );

  $s->DBExec(q|
    UPDATE threads
      SET !H
      WHERE id = %d|,
     \%set, $o{id});

  if($o{tags}) {
    $s->DBExec('DELETE FROM threads_tags WHERE tid = %d', $o{id});
    $s->DBExec(q|
      INSERT INTO threads_tags (tid, type, iid)
        VALUES (%d, !s, %d)|,
      $o{id}, $_->[0], $_->[1]||0
    ) for (@{$o{tags}});
  }
}


sub DBAddThread { # %options->{ title hidden locked tags }
  my($s, %o) = @_;

  my $id = $s->DBRow(q|
    INSERT INTO threads (title, hidden, locked)
      VALUES (!s, %d, %d)
      RETURNING id|,
      $o{title}, $o{hidden}?1:0, $o{locked}?1:0
    )->{id};

  $s->DBExec(q|
    INSERT INTO threads_tags (tid, type, iid)
      VALUES (%d, !s, %d)|,
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


sub DBLastId { # table
  return $_[0]->{_DB}->{sql}->last_insert_id(undef, undef, $_[1], undef);
}


sub sqlhelper { # type, query, @list
  my $self = shift;
  my $type = shift;
  my $sqlq = shift;
  my $s = $self->{_DB}->{sql};

  my $start = [Time::HiRes::gettimeofday()] if $self->{debug};

  $sqlq =~ s/\r?\n/ /g;
  $sqlq =~ s/  +/ /g;
  $sqlq = sqlprint($sqlq, @_) if exists $_[0];
  #warn "$sqlq\n";

  my $q = $s->prepare($sqlq);
  $q->execute();
  my $r = $type == 1 ? $q->fetchrow_hashref :
          $type == 2 ? $q->fetchall_arrayref({}) :
                       $q->rows;
  $q->finish();

  push(@{$self->{_DB}->{Queries}}, [ $sqlq, Time::HiRes::tv_interval($start) ]) if $self->{debug};

  $r = 0  if $type == 0 && !$r;
  $r = {} if $type == 1 && (!$r || ref($r) ne 'HASH');
  $r = [] if $type == 2 && (!$r || ref($r) ne 'ARRAY');

  return $r;
}


# Added features:
#  !s    SQL-quote
#  !l    listify
#  !L    SQL-quote-and-listify
#  !H    list of SET-items: key = format, value = replacement
#  !W    same as !H, but for WHERE clauses
sub sqlprint {
  my $i = -1;
  my @arg;
  my $sq = my $s = shift;
  while($sq =~ s/([%!])(.)//) {
    $i++;
    my $t = $1; my $d = $2;
    if($t eq '%') {
      if($d eq '%') {
        $i--; next 
      }
      $arg[$i] = $_[$i];
      next;
    }
    if($d !~ /[slLHW]/) {
      $i--; next
    }
    $arg[$i] = qs($_[$i]) if $d eq 's';
    $arg[$i] = join(',', @{$_[$i]}) if $d eq 'l';
    $arg[$i] = join(',', (qs(@{$_[$i]}))) if $d eq 'L';
    if($d eq 'H' || $d eq 'W') {
      my @i;
      defined $_[$i]{$_} && push(@i, sqlprint($_, $_[$i]{$_})) for keys %{$_[$i]};
      $arg[$i] = join($d eq 'H' ? ', ' : ' AND ', @i);
    }
  }
  $s =~ s/![sSlLHW]/%s/g;
  $s =~ s/!!/!/g;
  return sprintf($s, @arg);
}


sub qs { # ISO SQL2-quoting, with some PgSQL-specific stuff
  my @r = @_;
  # NOTE: we use E''-style strings because backslash escaping in the normal ''-style
  #       depends on the standard_conforming_strings configuration option of PgSQL,
  #       while E'' will always behave the same regardless of the server configuration.
  for (@r) {
    (!defined $_ or $_ eq '_NULL_') && next;
    s/'/''/g;
    s/\\/\\\\/g;
    $_ = "E'$_'";
  }
  return wantarray ? @r : $r[0];
}


1;

