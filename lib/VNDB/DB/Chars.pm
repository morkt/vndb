
package VNDB::DB::Chars;

use strict;
use warnings;
use Exporter 'import';

our @EXPORT = qw|dbCharGet dbCharGetRev dbCharRevisionInsert dbCharImageId|;


# options: id instance tagspoil trait_inc trait_exc char what results page gender bloodt
#   bust_min bust_max waist_min waist_max hip_min hip_max height_min height_max weight_min weight_max role
# what: extended traits vns changes
sub dbCharGet {
  my $self = shift;
  my %o = (
    page => 1,
    results => 10,
    what => '',
    tagspoil => 0,
    @_
  );

  $o{search} =~ s/%//g if $o{search};

  my %where = (
    !$o{id} ? ( 'c.hidden = FALSE' => 1 ) : (),
    $o{id}  ? ( 'c.id IN(!l)' => [ ref $o{id} ? $o{id} : [$o{id}] ] ) : (),
    $o{notid}    ? ( 'c.id <> ?'   => $o{notid} ) : (),
    $o{instance} ? ( 'c.main = ?' => $o{instance} ) : (),
    $o{vid}      ? ( 'c.id IN(SELECT id FROM chars_vns WHERE vid = ?)' => $o{vid} ) : (),
    defined $o{gender}     ? ( 'c.gender IN(!l)' => [ ref $o{gender} ? $o{gender} : [$o{gender}] ]) : (),
    defined $o{bloodt}     ? ( 'c.bloodt IN(!l)' => [ ref $o{bloodt} ? $o{bloodt} : [$o{bloodt}] ]) : (),
    defined $o{bust_min}   ? ( 'c.s_bust >= ?' => $o{bust_min} ) : (),
    defined $o{bust_max}   ? ( 'c.s_bust <= ? AND c.s_bust > 0' => $o{bust_max} ) : (),
    defined $o{waist_min}  ? ( 'c.s_waist >= ?' => $o{waist_min} ) : (),
    defined $o{waist_max}  ? ( 'c.s_waist <= ? AND c.s_waist > 0' => $o{waist_max} ) : (),
    defined $o{hip_min}    ? ( 'c.s_hip >= ?' => $o{hip_min} ) : (),
    defined $o{hip_max}    ? ( 'c.s_hip <= ? AND c.s_hip > 0' => $o{hip_max} ) : (),
    defined $o{height_min} ? ( 'c.height >= ?' => $o{height_min} ) : (),
    defined $o{height_max} ? ( 'c.height <= ? AND c.height > 0' => $o{height_max} ) : (),
    defined $o{weight_min} ? ( 'c.weight >= ?' => $o{weight_min} ) : (),
    defined $o{weight_max} ? ( 'c.weight <= ? AND c.weight > 0' => $o{weight_max} ) : (),
    $o{search} ? (
      '(c.name ILIKE ? OR c.original ILIKE ? OR c.alias ILIKE ?)', [ map '%'.$o{search}.'%', 1..3 ] ) : (),
    $o{char} ? (
      'LOWER(SUBSTR(c.name, 1, 1)) = ?' => $o{char} ) : (),
    defined $o{char} && !$o{char} ? (
      '(ASCII(c.name) < 97 OR ASCII(c.name) > 122) AND (ASCII(c.name) < 65 OR ASCII(c.name) > 90)' => 1 ) : (),
    $o{role} ? (
      'EXISTS(SELECT 1 FROM chars_vns cvi WHERE cvi.id = c.id AND cvi.role IN(!l))',
      [ ref $o{role} ? $o{role} : [$o{role}] ] ) : (),
    $o{trait_inc} ? (
      'c.id IN(SELECT cid FROM traits_chars WHERE tid IN(!l) AND spoil <= ? GROUP BY cid HAVING COUNT(tid) = ?)',
      [ ref $o{trait_inc} ? $o{trait_inc} : [$o{trait_inc}], $o{tagspoil}, ref $o{trait_inc} ? $#{$o{trait_inc}}+1 : 1 ]) : (),
    $o{trait_exc} ? (
      'c.id NOT IN(SELECT cid FROM traits_chars WHERE tid IN(!l))' => [ ref $o{trait_exc} ? $o{trait_exc} : [$o{trait_exc}] ] ) : (),
  );

  my @select = (qw|c.id c.name c.original c.gender|);
  push @select, qw|c.hidden c.locked c.alias c.desc c.image c.b_month c.b_day c.s_bust c.s_waist c.s_hip c.height c.weight c.bloodt c.main c.main_spoil| if $o{what} =~ /extended/;

  my($r, $np) = $self->dbPage(\%o, q|
    SELECT !s
      FROM chars c
      !W
      ORDER BY c.name|,
    join(', ', @select), \%where
  );

  return _enrich($self, $r, $np, 0, $o{what}, $o{vid});
}


sub dbCharGetRev {
  my $self = shift;
  my %o = (what => '', @_);

  $o{rev} ||= $self->dbRow('SELECT MAX(rev) AS rev FROM changes WHERE type = \'c\' AND itemid = ?', $o{id})->{rev};

  my $select = 'c.itemid AS id, ch.name, ch.original, ch.gender';
  $select .= ', extract(\'epoch\' from c.added) as added, c.requester, c.comments, u.username, c.rev, c.ihid, c.ilock';
  $select .= ', c.id AS cid, NOT EXISTS(SELECT 1 FROM changes c2 WHERE c2.type = c.type AND c2.itemid = c.itemid AND c2.rev = c.rev+1) AS lastrev';
  $select .= ', ch.alias, ch.desc, ch.image, ch.b_month, ch.b_day, ch.s_bust, ch.s_waist, ch.s_hip, ch.height, ch.weight, ch.bloodt, ch.main, ch.main_spoil, co.hidden, co.locked' if $o{what} =~ /extended/;

  my $r = $self->dbAll(q|
    SELECT !s
      FROM changes c
      JOIN chars co ON co.id = c.itemid
      JOIN chars_hist ch ON ch.chid = c.id
      JOIN users u ON u.id = c.requester
      WHERE c.type = 'c' AND c.itemid = ? AND c.rev = ?|,
    $select, $o{id}, $o{rev}
  );

  return _enrich($self, $r, 0, 1, $o{what});
}


sub _enrich {
  my($self, $r, $np, $rev, $what, $vid) = @_;

  if(@$r && $what =~ /vns|traits/) {
    my($col, $hist, $colname) = $rev ? ('cid', '_hist', 'chid') : ('id', '', 'id');
    my %r = map {
      $_->{traits} = [];
      $_->{vns} = [];
      ($_->{$col}, $_)
    } @$r;

    if($what =~ /traits/) {
      push @{$r{ delete $_->{xid} }{traits}}, $_ for (@{$self->dbAll(qq|
        SELECT ct.$colname AS xid, ct.tid, ct.spoil, t.name, t.sexual, t."group", tg.name AS groupname
          FROM chars_traits$hist ct
          JOIN traits t ON t.id = ct.tid
          JOIN traits tg ON tg.id = t."group"
         WHERE ct.$colname IN(!l)
         ORDER BY tg."order", t.name|, [ keys %r ]
      )});
    }

    if($what =~ /vns(?:\((\d+)\))?/) {
      push @{$r{ delete $_->{xid} }{vns}}, $_ for (@{$self->dbAll("
        SELECT cv.$colname AS xid, cv.vid, cv.rid, cv.spoil, cv.role, v.title AS vntitle, r.title AS rtitle
          FROM chars_vns$hist cv
          JOIN vn v ON cv.vid = v.id
          LEFT JOIN releases r ON cv.rid = r.id
          !W
          ORDER BY v.c_released",
        { "cv.$colname IN(!l)" => [[keys %r]], $1 ? ('cv.vid = ?', $1) : () }
      )});
    }
  }

  # Depends on the VN revision rather than char revision
  if(@$r && $what =~ /seiyuu/) {
    my %r = map {
      $_->{seiyuu} = [];
      ($_->{id}, $_)
    } @$r;

    push @{$r{ delete $_->{cid} }{seiyuu}}, $_ for (@{$self->dbAll(q|
      SELECT vs.cid, s.id AS sid, sa.name, sa.original, vs.note, v.id AS vid, v.title AS vntitle
        FROM vn_seiyuu vs
        JOIN staff_alias sa ON sa.aid = vs.aid
        JOIN staff s ON s.id = sa.id
        JOIN vn v ON v.id = vs.id
        !W
        ORDER BY v.c_released, sa.name|, {
          's.hidden = FALSE' => 1,
          'vs.cid IN(!l)' => [[ keys %r ]],
          $vid ? ('v.id = ?' => $vid) : (),
        }
    )});
  }

  return wantarray ? ($r, $np) : $r;
}


# Updates the edit_* tables, used from dbItemEdit()
# Arguments: { columns in chars_rev + traits + vns },
sub dbCharRevisionInsert {
  my($self, $o) = @_;

  my %set = map exists($o->{$_}) ? (qq|"$_" = ?|, $o->{$_}) : (),
    qw|name original alias desc image b_month b_day s_bust s_waist s_hip height weight bloodt gender main main_spoil|;
  $self->dbExec('UPDATE edit_char !H', \%set) if keys %set;

  if($o->{traits}) {
    $self->dbExec('DELETE FROM edit_char_traits');
    $self->dbExec('INSERT INTO edit_char_traits (tid, spoil) VALUES (?,?)', $_->[0],$_->[1]) for (@{$o->{traits}});
  }
  if($o->{vns}) {
    $self->dbExec('DELETE FROM edit_char_vns');
    $self->dbExec('INSERT INTO edit_char_vns (vid, rid, spoil, role) VALUES(!l)', $_) for (@{$o->{vns}});
  }
}


# fetches an ID for a new image
sub dbCharImageId {
  return shift->dbRow("SELECT nextval('charimg_seq') AS ni")->{ni};
}


1;

