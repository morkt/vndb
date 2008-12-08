
package VNDB::DB::VNList;

use strict;
use warnings;
use Exporter 'import';


our @EXPORT = qw|dbVNListGet dbVNListAdd dbVNListDel|;


# %options->{ uid order char voted page results }
# NOTE: this function is mostly copied from 1.x, may need some rewriting...
sub dbVNListGet {
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



1;

