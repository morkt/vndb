
package VNDB::DB::ULists;

use strict;
use warnings;
use Exporter 'import';


our @EXPORT = qw|
  dbVNListGet dbVNListList dbVNListAdd dbVNListDel
  dbVoteGet dbVoteStats dbVoteAdd dbVoteDel
  dbWishListGet dbWishListAdd dbWishListDel
|;


# Simpler and more efficient version of dbVNListList below
# %options->{ uid rid }
sub dbVNListGet {
  my($self, %o) = @_;

  my %where = (
    'uid = ?' => $o{uid},
    $o{rid} && !ref $o{rid} ? (
      'rid = ?' => $o{rid} ) : (),
    $o{rid} && ref $o{rid} ? (
      'rid IN(!l)' => [$o{rid}] ) : (),
  );

  return $self->dbAll(q|
    SELECT uid, rid, rstat, vstat
      FROM rlists
      !W|,
    \%where
  );
}


# %options->{ uid order char voted page results }
# NOTE: this function is mostly copied from 1.x, may need some rewriting...
sub dbVNListList {
  my($self, %o) = @_;

  $o{results} ||= 50;
  $o{page}    ||= 1;
  $o{order}   ||= 'vr.title ASC';
  $o{voted}   ||= 0;  # -1: only non-voted, 0: all, 1: only voted

  # construct the global WHERE clause
  my $where = $o{voted} != -1 ? 'vo.vote IS NOT NULL' : '';
  $where .= ($where?' OR ':'').q|v.id IN(
  SELECT irv.vid
    FROM rlists irl
    JOIN releases ir ON ir.id = irl.rid
    JOIN releases_vn irv ON irv.rid = ir.latest
    WHERE uid = ?
  )| if $o{voted} != 1;
  $where = '('.$where.') AND LOWER(SUBSTR(vr.title, 1, 1)) = \''.$o{char}.'\'' if $o{char};
  $where = '('.$where.') AND (ASCII(vr.title) < 97 OR ASCII(vr.title) > 122) AND (ASCII(vr.title) < 65 OR ASCII(vr.title) > 90)' if defined $o{char} && !$o{char};
  $where = '('.$where.') AND vo.vote IS NULL' if $o{voted} == -1;

  # execute query
  my($r, $np) = $self->dbPage(\%o, qq|
    SELECT vr.vid, vr.title, vr.original, v.c_released, v.c_languages, v.c_platforms, COALESCE(vo.vote, 0) AS vote
      FROM vn v
      JOIN vn_rev vr ON vr.id = v.latest
      !s JOIN votes vo ON vo.vid = v.id AND vo.uid = ?
      WHERE $where
      ORDER BY !s|,
    $o{voted} == 1 ? '' : 'LEFT', $o{uid},   # JOIN if we only want votes, LEFT JOIN if we also want rlist items
    $o{voted} != 1 ? $o{uid} : (), $o{order},
  );

  # fetch releases and link to VNs
  if(@$r) {
    my %vns = map {
      $_->{rels}=[];
      $_->{vid}, $_->{rels}
    } @$r;

    push @{$vns{$_->{vid}}}, $_ for (@{$self->dbAll(q|
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

  return wantarray ? ($r, $np) : $r;
}


# %options->{ uid rid rstat vstat }
sub dbVNListAdd {
  my($self, %o) = @_;

  my %s = (
    defined $o{rstat} ? ( 'rstat = ?', $o{rstat} ) : (),
    defined $o{vstat} ? ( 'vstat = ?', $o{vstat} ) : (),
  );
  $o{rstat}||=0;
  $o{vstat}||=0;

    $self->dbExec(
      'UPDATE rlists !H WHERE uid = ? AND rid IN(!l)',
      \%s, $o{uid}, ref($o{rid}) eq 'ARRAY' ? $o{rid} : [ $o{rid} ]
    )
  ||
    $self->dbExec(
      'INSERT INTO rlists (uid, rid, rstat, vstat) VALUES(!l)',
      [@o{qw| uid rid rstat vstat |}]
    );
}


# Arguments: uid, rid
sub dbVNListDel {
  my($self, $uid, $rid) = @_;
  $self->dbExec(
    'DELETE FROM rlists WHERE uid = ? AND rid IN(!l)',
    $uid, ref($rid) eq 'ARRAY' ? $rid : [ $rid ]
  );
}


# %options->{ uid vid hide order results page what }
# what: user, vn
sub dbVoteGet {
  my($self, %o) = @_;
  $o{order} ||= 'n.date DESC';
  $o{results} ||= 50;
  $o{page} ||= 1;
  $o{what} ||= '';

  my %where = (
    $o{uid} ? ( 'n.uid = ?' => $o{uid} ) : (),
    $o{vid} ? ( 'n.vid = ?' => $o{vid} ) : (),
    $o{hide} ? ( 'u.show_list = TRUE' => 1 ) : (),
  );

  my @select = (
    qw|n.vid n.vote n.date n.uid|,
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

  my($r, $np) = $self->dbPage(\%o, q|
    SELECT !s
      FROM votes n
      !s
      !W
      ORDER BY !s|,
    join(',', @select), join(' ', @join), \%where, $o{order}
  );

  return wantarray ? ($r, $np) : $r;
}


# Arguments: (uid|vid), id
# Returns an arrayref with 10 elements containing the number of votes for index+1
sub dbVoteStats {
  my($self, $col, $id) = @_;
  my $r = [ qw| 0 0 0 0 0 0 0 0 0 0 | ];
  $r->[$_->{vote}-1] = $_->{votes} for (@{$self->dbAll(q|
    SELECT vote, COUNT(vote) as votes
      FROM votes
      !W
      GROUP BY vote|,
    $col ? { '!s = ?' => [ $col, $id ] } : {},
  )});
  return $r;
}


# Adds a new vote or updates an existing one
# Arguments: vid, uid, vote
sub dbVoteAdd {
  my($self, $vid, $uid, $vote) = @_;
  $self->dbExec(q|
    UPDATE votes
      SET vote = ?
      WHERE vid = ?
      AND uid = ?|,
    $vote, $vid, $uid
  ) || $self->dbExec(q|
    INSERT INTO votes
      (vid, uid, vote, date)
      VALUES (!l)|,
    [ $vid, $uid, $vote, time ]
  );
}


# Arguments: uid, vid
sub dbVoteDel {
  my($self, $uid, $vid) = @_;
  $self->dbExec('DELETE FROM votes !W',
    { 'vid = ?' => $vid, 'uid = ?' => $uid }
  );
}


# %options->{ uid vid wstat what order page results }
# what: vn
sub dbWishListGet {
  my($self, %o) = @_;

  $o{order} ||= 'wl.wstat ASC';
  $o{page} ||= 1;
  $o{results} ||= 50;
  $o{what} ||= '';

  my %where = (
    'wl.uid = ?' => $o{uid},
    $o{vid} ? ( 'wl.vid = ?' => $o{vid} ) : (),
    defined $o{wstat} ? ( 'wl.wstat = ?' => $o{wstat} ) : (),
  );

  my $select = 'wl.vid, wl.wstat, wl.added';
  my @join;
  if($o{what} =~ /vn/) {
    $select .= ', vr.title, vr.original';
    push @join, 'JOIN vn v ON v.id = wl.vid',
    'JOIN vn_rev vr ON vr.id = v.latest';
  }

  my($r, $np) = $self->dbPage(\%o, q|
    SELECT !s
      FROM wlists wl
      !s
      !W
      ORDER BY !s|,
    $select, join(' ', @join), \%where, $o{order},
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

