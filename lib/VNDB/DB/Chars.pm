
package VNDB::DB::Chars;

use strict;
use warnings;
use Exporter 'import';

our @EXPORT = qw|dbCharGet dbCharRevisionInsert dbCharImageId|;


# options: id rev instance tagspoil trait_inc trait_exc char what results page gender bloodt
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
    !$o{id} && !$o{rev} ? ( 'c.hidden = FALSE' => 1 ) : (),
    $o{id} ? (
      'c.id IN(!l)' => [ ref $o{id} ? $o{id} : [$o{id}] ] ) : (),
    $o{rev} ? ( 'h.rev = ?' => $o{rev} ) : (),
    $o{notid}    ? ( 'c.id <> ?'   => $o{notid} ) : (),
    $o{instance} ? ( 'cr.main = ?' => $o{instance} ) : (),
    $o{vid}      ? ( 'cr.id IN(SELECT cid FROM chars_vns WHERE vid = ?)' => $o{vid} ) : (),
    defined $o{gender} ? ( 'cr.gender IN(!l)' => [ ref $o{gender} ? $o{gender} : [$o{gender}] ]) : (),
    defined $o{bloodt} ? ( 'cr.bloodt IN(!l)' => [ ref $o{bloodt} ? $o{bloodt} : [$o{bloodt}] ]) : (),
    defined $o{bust_min} ? ( 'cr.s_bust >= ?' => $o{bust_min} ) : (),
    defined $o{bust_max} ? ( 'cr.s_bust <= ? AND cr.s_bust > 0' => $o{bust_max} ) : (),
    defined $o{waist_min} ? ( 'cr.s_waist >= ?' => $o{waist_min} ) : (),
    defined $o{waist_max} ? ( 'cr.s_waist <= ? AND cr.s_waist > 0' => $o{waist_max} ) : (),
    defined $o{hip_min} ? ( 'cr.s_hip >= ?' => $o{hip_min} ) : (),
    defined $o{hip_max} ? ( 'cr.s_hip <= ? AND cr.s_hip > 0' => $o{hip_max} ) : (),
    defined $o{height_min} ? ( 'cr.height >= ?' => $o{height_min} ) : (),
    defined $o{height_max} ? ( 'cr.height <= ? AND cr.height > 0' => $o{height_max} ) : (),
    defined $o{weight_min} ? ( 'cr.weight >= ?' => $o{weight_min} ) : (),
    defined $o{weight_max} ? ( 'cr.weight <= ? AND cr.weight > 0' => $o{weight_max} ) : (),
    $o{search} ? (
      '(cr.name ILIKE ? OR cr.original ILIKE ? OR cr.alias ILIKE ?)', [ map '%'.$o{search}.'%', 1..3 ] ) : (),
    $o{char} ? (
      'LOWER(SUBSTR(cr.name, 1, 1)) = ?' => $o{char} ) : (),
    defined $o{char} && !$o{char} ? (
      '(ASCII(cr.name) < 97 OR ASCII(cr.name) > 122) AND (ASCII(cr.name) < 65 OR ASCII(cr.name) > 90)' => 1 ) : (),
    $o{role} ? (
      'EXISTS(SELECT 1 FROM chars_vns cvi WHERE cvi.cid = cr.id AND cvi.role IN(!l))',
      [ ref $o{role} ? $o{role} : [$o{role}] ] ) : (),
    $o{trait_inc} ? (
      'c.id IN(SELECT cid FROM traits_chars WHERE tid IN(!l) AND spoil <= ? GROUP BY cid HAVING COUNT(tid) = ?)',
      [ ref $o{trait_inc} ? $o{trait_inc} : [$o{trait_inc}], $o{tagspoil}, ref $o{trait_inc} ? $#{$o{trait_inc}}+1 : 1 ]) : (),
    $o{trait_exc} ? (
      'c.id NOT IN(SELECT cid FROM traits_chars WHERE tid IN(!l))' => [ ref $o{trait_exc} ? $o{trait_exc} : [$o{trait_exc}] ] ) : (),
  );

  my @select = (qw|c.id cr.name cr.original cr.gender|, 'cr.id AS cid');
  push @select, qw|c.hidden c.locked cr.alias cr.desc cr.image cr.b_month cr.b_day cr.s_bust cr.s_waist cr.s_hip cr.height cr.weight cr.bloodt cr.main cr.main_spoil| if $o{what} =~ /extended/;
  push @select, qw|h.requester h.comments c.latest u.username h.rev h.ihid h.ilock|, "extract('epoch' from h.added) as added" if $o{what} =~ /changes/;

  my @join;
  push @join, $o{rev} ? 'JOIN chars c ON c.id = cr.cid' : 'JOIN chars c ON cr.id = c.latest';
  push @join, 'JOIN changes h ON h.id = cr.id' if $o{what} =~ /changes/ || $o{rev};
  push @join, 'JOIN users u ON u.id = h.requester' if $o{what} =~ /changes/;

  my($r, $np) = $self->dbPage(\%o, q|
    SELECT !s
      FROM chars_rev cr
      !s
      !W
      ORDER BY cr.name|,
    join(', ', @select), join(' ', @join), \%where
  );

  if(@$r && $o{what} =~ /vns|traits|seiyuu/) {
    my %r = map {
      $_->{traits} = [];
      $_->{vns} = [];
      $_->{seiyuu} = [];
      ($_->{cid}, $_)
    } @$r;

    if($o{what} =~ /traits/) {
      push @{$r{ delete $_->{cid} }{traits}}, $_ for (@{$self->dbAll(q|
        SELECT ct.cid, ct.tid, ct.spoil, t.name, t.sexual, t."group", tg.name AS groupname
          FROM chars_traits ct
          JOIN traits t ON t.id = ct.tid
          LEFT JOIN traits tg ON tg.id = t."group"
         WHERE cid IN(!l)
         ORDER BY tg."order", t.name|, [ keys %r ]
      )});
    }

    if($o{what} =~ /vns(?:\((\d+)\))?/) {
      push @{$r{ delete $_->{cid} }{vns}}, $_ for (@{$self->dbAll(q|
        SELECT cv.cid, cv.vid, cv.rid, cv.spoil, cv.role, vr.title AS vntitle, rr.title AS rtitle
          FROM chars_vns cv
          JOIN vn v ON cv.vid = v.id
          JOIN vn_rev vr ON vr.id = v.latest
          LEFT JOIN releases r ON cv.rid = r.id
          LEFT JOIN releases_rev rr ON rr.id = r.latest
          !W
          ORDER BY v.c_released|,
        { 'cv.cid IN(!l)' => [[keys %r]], $1 ? ('cv.vid = ?', $1) : () }
      )});
    }

    if($o{what} =~ /seiyuu/) {
      push @{$r{ delete $_->{cid} }{seiyuu}}, $_ for (@{$self->dbAll(q|
        SELECT cr.id AS cid, s.id AS sid, sa.name, sa.original, vs.note, v.id AS vid, vr.title AS vntitle
          FROM vn_seiyuu vs
          JOIN chars_rev cr ON cr.cid = vs.cid
          JOIN staff_alias sa ON sa.id = vs.aid
          JOIN staff s ON sa.rid = s.latest
          JOIN vn_rev vr ON vr.id = vs.vid
          JOIN vn v ON v.latest = vs.vid
          !W
          ORDER BY v.c_released, sa.name|, {
            's.hidden = FALSE' => 1,
            'cr.id IN(!l)' => [[ keys %r ]],
            $o{vid} ? ('v.id = ?' => $o{vid}) : (),
          }
      )});
    }
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

