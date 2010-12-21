
package VNDB::DB::ULists;

use strict;
use warnings;
use Exporter 'import';


our @EXPORT = qw|
  dbRListGet dbVNListGet dbVNListList dbVNListAdd dbVNListDel dbRListAdd dbRListDel
  dbVoteGet dbVoteStats dbVoteAdd dbVoteDel
  dbWishListGet dbWishListAdd dbWishListDel
|;


# Options: uid rid
sub dbRListGet {
  my($self, %o) = @_;

  my %where = (
    'uid = ?' => $o{uid},
    $o{rid} ? ('rid IN(!l)' => [ ref $o{rid} ? $o{rid} : [$o{rid}] ]) : (),
  );

  return $self->dbAll(q|
    SELECT uid, rid, status
      FROM rlists
      !W|,
    \%where
  );
}

# Options: uid vid
sub dbVNListGet {
  my($self, %o) = @_;

  my %where = (
    'uid = ?' => $o{uid},
    $o{vid} ? ('vid IN(!l)' => [ ref $o{vid} ? $o{vid} : [$o{vid}] ]) : (),
  );

  return $self->dbAll(q|
    SELECT uid, vid, status
      FROM vnlists
      !W|,
    \%where
  );
}


# Options: uid char voted page results sort reverse
# sort: title vote
sub dbVNListList {
  my($self, %o) = @_;
  $o{results} ||= 50;
  $o{page}    ||= 1;

  my %where = (
    'vl.uid = ?' => $o{uid},
    defined($o{voted}) ? ('vo.vote !s NULL' => $o{voted} ? 'IS NOT' : 'IS') : (),
    defined($o{status})? ('vl.status = ?' => $o{status}) : (),
    $o{char}           ? ('LOWER(SUBSTR(vr.title, 1, 1)) = ?' => $o{char} ) : (),
    defined $o{char} && !$o{char} ? (
      '(ASCII(vr.title) < 97 OR ASCII(vr.title) > 122) AND (ASCII(vr.title) < 65 OR ASCII(vr.title) > 90)' => 1 ) : (),
  );

  my $order = sprintf {
    title => 'vr.title %s',
    vote  => 'vo.vote %s NULLS LAST, vr.title ASC',
  }->{ $o{sort}||'title' }, $o{reverse} ? 'DESC' : 'ASC';

  # execute query
  my($r, $np) = $self->dbPage(\%o, qq|
    SELECT vr.vid, vr.title, vr.original, vl.status, vl.notes, COALESCE(vo.vote, 0) AS vote
      FROM vnlists vl
      JOIN vn v ON v.id = vl.vid
      JOIN vn_rev vr ON vr.id = v.latest
      LEFT JOIN votes vo ON vo.vid = vl.vid AND vo.uid = vl.uid
      !W
      ORDER BY !s|,
    \%where, $order
  );

  # fetch releases and link to VNs
  if(@$r) {
    my %vns = map {
      $_->{rels}=[];
      $_->{vid}, $_->{rels}
    } @$r;

    my $rel = $self->dbAll(q|
      SELECT rv.vid, rr.rid, r.latest, rr.title, rr.original, rr.released, rr.type, rl.status
        FROM rlists rl
        JOIN releases r ON rl.rid = r.id
        JOIN releases_rev rr ON rr.id = r.latest
        JOIN releases_vn rv ON rv.rid = r.latest
        WHERE rl.uid = ?
          AND rv.vid IN(!l)
        ORDER BY rr.released ASC|,
      $o{uid}, [ keys %vns ]
    );

    if(@$rel) {
      my %rel = map {
        $_->{languages}=[];
        $_->{latest}, $_->{languages}
      } @$rel;

      push(@{$rel{$_->{rid}}}, $_->{lang}) for (@{$self->dbAll(q|
        SELECT rid, lang
          FROM releases_lang
          WHERE rid IN(!l)|,
        [ keys %rel ]
      )});
      push @{$vns{$_->{vid}}}, $_ for @$rel;
    }
  }

  return wantarray ? ($r, $np) : $r;
}


# Arguments: uid vid status notes
# vid can be an arrayref only when the rows are already present, in which case an update is done
# status and notes can be undef when an update is done, in which case these fields aren't updated
sub dbVNListAdd {
  my($self, $uid, $vid, $stat, $notes) = @_;
    $self->dbExec(
      'UPDATE vnlists !H WHERE uid = ? AND vid IN(!l)',
      {defined($stat) ? ('status = ?' => $stat ):(),
       defined($notes)? ('notes = ?'  => $notes):()},
      $uid, ref($vid) ? $vid : [ $vid ]
    )
  ||
    $self->dbExec(
      'INSERT INTO vnlists (uid, vid, status, notes) VALUES(?, ?, ?, ?)',
      $uid, $vid, $stat||0, $notes||''
    );
}


# Arguments: uid, vid
sub dbVNListDel {
  my($self, $uid, $vid) = @_;
  $self->dbExec(
    'DELETE FROM vnlists WHERE uid = ? AND vid IN(!l)',
    $uid, ref($vid) ? $vid : [ $vid ]
  );
}


# Arguments: uid rid status
# rid can be an arrayref only when the rows are already present, in which case an update is done
sub dbRListAdd {
  my($self, $uid, $rid, $stat) = @_;
    $self->dbExec(
      'UPDATE rlists SET status = ? WHERE uid = ? AND rid IN(!l)',
      $stat, $uid, ref($rid) ? $rid : [ $rid ]
    )
  ||
    $self->dbExec(
      'INSERT INTO rlists (uid, rid, status) VALUES(?, ?, ?)',
      $uid, $rid, $stat
    );
}


# Arguments: uid, rid
sub dbRListDel {
  my($self, $uid, $rid) = @_;
  $self->dbExec(
    'DELETE FROM rlists WHERE uid = ? AND rid IN(!l)',
    $uid, ref($rid) ? $rid : [ $rid ]
  );
}


# Options: uid vid hide hide_ign results page what sort reverse
# what: user, vn
sub dbVoteGet {
  my($self, %o) = @_;
  $o{results} ||= 50;
  $o{page} ||= 1;
  $o{what} ||= '';
  $o{sort} ||= 'date';
  $o{reverse} //= 1;

  my %where = (
    $o{uid} ? ( 'n.uid = ?' => $o{uid} ) : (),
    $o{vid} ? ( 'n.vid = ?' => $o{vid} ) : (),
    $o{hide} ? ( 'u.show_list = TRUE' => 1 ) : (),
    $o{hide_ign} ? ( '(NOT u.ign_votes OR u.id = ?)' => $self->authInfo->{id}||0 ) : (),
    $o{vn_char}  ? ( 'LOWER(SUBSTR(vr.title, 1, 1)) = ?' => $o{vn_char} ) : (),
    defined $o{vn_char} && !$o{vn_char} ? (
      '(ASCII(vr.title) < 97 OR ASCII(vr.title) > 122) AND (ASCII(vr.title) < 65 OR ASCII(vr.title) > 90)' => 1 ) : (),
    $o{user_char} ? ( 'LOWER(SUBSTR(u.username, 1, 1)) = ?' => $o{user_char} ) : (),
    defined $o{user_char} && !$o{user_char} ? (
      '(ASCII(u.username) < 97 OR ASCII(u.username) > 122) AND (ASCII(u.username) < 65 OR ASCII(u.username) > 90)' => 1 ) : (),
  );

  my @select = (
    qw|n.vid n.vote n.uid|, q|extract('epoch' from n.date) as date|,
    $o{what} =~ /user/ ? ('u.username') : (),
    $o{what} =~ /vn/ ? (qw|vr.title vr.original|) : (),
  );

  my @join = (
    $o{what} =~ /vn/ ? (
      'JOIN vn v ON v.id = n.vid',
      'JOIN vn_rev vr ON vr.id = v.latest'
    ) : (),
    $o{what} =~ /user/ || $o{hide} ? (
      'JOIN users u ON u.id = n.uid'
    ) : (),
  );

  my $order = sprintf {
    date     => 'n.date %s',
    username => 'u.username %s',
    title    => 'vr.title %s',
    vote     => 'n.vote %s',
  }->{$o{sort}}, $o{reverse} ? 'DESC' : 'ASC';

  my($r, $np) = $self->dbPage(\%o, q|
    SELECT !s
      FROM votes n
      !s
      !W
      ORDER BY !s|,
    join(',', @select), join(' ', @join), \%where, $order
  );

  return wantarray ? ($r, $np) : $r;
}


# Arguments: (uid|vid), id, use_ignore_list
# Returns an arrayref with 10 elements containing the number of votes for index+1
sub dbVoteStats {
  my($self, $col, $id, $ign) = @_;
  my $u = $self->authInfo->{id};
  my $r = [ qw| 0 0 0 0 0 0 0 0 0 0 | ];
  $r->[$_->{vote}-1] = $_->{votes} for (@{$self->dbAll(q|
    SELECT vote, COUNT(vote) as votes
      FROM votes
      !s
      !W
      GROUP BY vote|,
    $ign ? 'JOIN users ON id = uid AND (NOT ign_votes'.($u?sprintf(' OR id = %d',$u):'').')' : '',
    $col ? { '!s = ?' => [ $col, $id ] } : {},
  )});
  return $r;
}


# Adds a new vote or updates an existing one
# Arguments: vid, uid, vote
# vid can be an arrayref only when the rows are already present, in which case an update is done
sub dbVoteAdd {
  my($self, $vid, $uid, $vote) = @_;
  $self->dbExec(q|
    UPDATE votes
      SET vote = ?, date = NOW()
      WHERE vid IN(!l)
      AND uid = ?|,
    $vote, ref($vid) ? $vid : [$vid], $uid
  ) || $self->dbExec(q|
    INSERT INTO votes
      (vid, uid, vote)
      VALUES (!l)|,
    [ $vid, $uid, $vote ]
  );
}


# Arguments: uid, vid
# vid can be an arrayref
sub dbVoteDel {
  my($self, $uid, $vid) = @_;
  $self->dbExec('DELETE FROM votes !W',
    { 'vid IN(!l)' => [ref($vid)?$vid:[$vid]], 'uid = ?' => $uid }
  );
}


# %options->{ uid vid wstat what page results sort reverse }
# what: vn
# sort: title added wstat
sub dbWishListGet {
  my($self, %o) = @_;

  $o{page} ||= 1;
  $o{results} ||= 50;
  $o{what} ||= '';

  my %where = (
    'wl.uid = ?' => $o{uid},
    $o{vid} ? ( 'wl.vid = ?' => $o{vid} ) : (),
    defined $o{wstat} ? ( 'wl.wstat = ?' => $o{wstat} ) : (),
  );

  my $select = q|wl.vid, wl.wstat, extract('epoch' from wl.added) AS added|;
  my @join;
  if($o{what} =~ /vn/) {
    $select .= ', vr.title, vr.original';
    push @join, 'JOIN vn v ON v.id = wl.vid',
    'JOIN vn_rev vr ON vr.id = v.latest';
  }

  my $order = sprintf  {
    title => 'vr.title %s',
    added => 'wl.added %s',
    wstat => 'wl.wstat %2$s, vr.title ASC',
  }->{ $o{sort}||'added' }, $o{reverse} ? 'DESC' : 'ASC', $o{reverse} ? 'ASC' : 'DESC';

  my($r, $np) = $self->dbPage(\%o, q|
    SELECT !s
      FROM wlists wl
      !s
      !W
      ORDER BY !s|,
    $select, join(' ', @join), \%where, $order,
  );

  return wantarray ? ($r, $np) : $r;
}


# Updates or adds a whishlist item
# Arguments: vid, uid, wstat
sub dbWishListAdd {
  my($self, $vid, $uid, $wstat) = @_;
    $self->dbExec(
      'UPDATE wlists SET wstat = ? WHERE uid = ? AND vid IN(!l)',
      $wstat, $uid, ref($vid) eq 'ARRAY' ? $vid : [ $vid ]
    )
  ||
    $self->dbExec(
      'INSERT INTO wlists (uid, vid, wstat) VALUES(!l)',
      [ $uid, $vid, $wstat ]
    );
}


# Arguments: uid, vids
sub dbWishListDel {
  my($self, $uid, $vid) = @_;
  $self->dbExec(
    'DELETE FROM wlists WHERE uid = ? AND vid IN(!l)',
    $uid, ref($vid) eq 'ARRAY' ? $vid : [ $vid ]
  );
}


1;

