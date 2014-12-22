
package VNDB::DB::Staff;

use strict;
use warnings;
use Exporter 'import';

our @EXPORT = qw|dbStaffGet dbStaffRevisionInsert|;

# options: results, page, id, aid, vid, search, rev
# what: extended changes roles aliases
sub dbStaffGet {
  my $self = shift;
  my %o = (
    results => 10,
    page => 1,
    what => '',
    @_
  );

  $o{search} =~ s/%//g if $o{search};

  my %where = (
    !$o{id} && !$o{rev} ? ( 's.hidden = FALSE' => 1 ) : (),
    $o{id}  ? ( ref $o{id}  ? ('s.id IN(!l)'  => [$o{id}])  : ('s.id = ?' => $o{id}) ) : (),
    $o{aid} ? ( ref $o{aid} ? ('sa.id IN(!l)' => [$o{aid}]) : ('sa.id = ?' => $o{aid}) ) : (),
    $o{vid} ? ( 'vr.vid = ?' => $o{vid}) : (),
    $o{search} ?
      ( '(sa.name ILIKE ? OR sa.original ILIKE ?)', [ map '%%'.$o{search}.'%%', 1..2 ] ) : (),
    $o{char} ? ( 'LOWER(SUBSTR(sa.name, 1, 1)) = ?' => $o{char} ) : (),
    defined $o{char} && !$o{char} ?
      ( '(ASCII(sa.name) < 97 OR ASCII(sa.name) > 122) AND (ASCII(sa.name) < 65 OR ASCII(sa.name) > 90)' => 1 ) : (),
    $o{rev} ? ( 'c.rev = ?' => $o{rev} ) : (),
  );

  my @join;
  push @join, 'JOIN staff s ON '.($o{rev} ? 's.id = sr.sid' : 'sr.id = s.latest');
  push @join, 'JOIN staff_alias sa ON sa.rid = sr.id'.($o{id}?' AND sa.id = sr.aid':'');
  push @join, 'JOIN changes c ON c.id = sr.id' if $o{what} =~ /changes/ || $o{rev};
  push @join, 'JOIN users u ON u.id = c.requester' if $o{what} =~ /changes/;
  push @join,
    'JOIN vn_staff vs ON vs.aid = sa.id',
    'JOIN vn_rev vr ON vs.vid = vr.id',
    'JOIN vn v ON vr.id = v.latest' if $o{vid};
# fetch both staff and seiyuu in one query
#   push @join, q|
#     LEFT JOIN vn_staff vs ON vs.aid = sa.id
#     LEFT JOIN (chars_seiyuu cs JOIN chars c ON cs.cid = c.latest)
#     ON cs.aid = sa.id
#     JOIN (vn_rev vr JOIN vn v ON vr.id = v.latest)
#     ON vs.vid = vr.id OR cs.vid = v.id
#   | if $o{vid};

  my $select = 's.id, sr.aid, sa.name, sa.original, sr.gender, sr.lang, sr.id AS cid';
  $select .= ', sr.desc, sr.l_wp, s.hidden, s.locked' if $o{what} =~ /extended/;
  $select .= q|, extract('epoch' from c.added) as added, c.requester, c.comments, s.latest, u.username, c.rev, c.ihid, c.ilock| if $o{what} =~ /changes/;
  $select .= ', vs.role, vs.note' if $o{vid};

  my $order = $o{vid} ? 'ORDER BY vs.role ASC, sa.name ASC' : 'ORDER BY sa.name ASC';

  my($r, $np) = $self->dbPage(\%o, q|
    SELECT !s
      FROM staff_rev sr
      !s
      !W
      !s|,
    $select, join(' ', @join), \%where, $order
  );

  if (@$r && $o{what} =~ /roles|aliases/) {
    my %r = map {
      $_->{roles} = [];
      $_->{cast} = [];
      $_->{aliases} = [];
      ($_->{cid}, $_);
    } @$r;
    if ($o{what} =~ /roles/) {
      push @{$r{ delete $_->{rid} }{roles}}, $_ for (@{$self->dbAll(q|
        SELECT sa.rid, vr.vid, sa.name, v.c_released, vr.title, vr.original AS t_original, vs.role, vs.note
          FROM vn_staff vs
          JOIN vn_rev vr ON vr.id = vs.vid
          JOIN vn v ON v.latest = vr.id
          JOIN staff_alias sa ON vs.aid = sa.id
          WHERE sa.rid IN(!l)
          ORDER BY v.c_released ASC, vr.title ASC, vs.role ASC|, [ keys %r ]
      )});
      push @{$r{ delete $_->{rid} }{cast}}, $_ for (@{$self->dbAll(q|
        SELECT sa.rid, vr.vid, sa.name, v.c_released, vr.title, vr.original AS t_original, cr.cid, cr.name AS c_name, cs.note
          FROM chars_seiyuu cs
          JOIN chars_rev cr ON cr.id = cs.cid
          JOIN vn v ON v.id = cs.vid
          JOIN vn_rev vr ON v.latest = vr.id
          JOIN staff_alias sa ON cs.aid = sa.id
          WHERE sa.rid IN(!l)
          ORDER BY v.c_released ASC, vr.title ASC|, [ keys %r ]
      )});
    }
    if ($o{what} =~ /aliases/) {
      push @{$r{ delete $_->{rid} }{aliases}}, $_ for (@{$self->dbAll(q|
        SELECT sa.id, sa.rid, sa.name, sa.original
          FROM staff_alias sa
          JOIN staff_rev sr ON sr.id = sa.rid
          WHERE sr.id IN(!l) AND sr.aid <> sa.id
          ORDER BY sa.name ASC|, [ keys %r ]
      )});
    }
  }

  return wantarray ? ($r, $np) : $r;
}

# Updates the edit_* tables, used from dbItemEdit()
# Arguments: { columns in staff_rev and staff_alias},
sub dbStaffRevisionInsert {
  my($self, $o) = @_;

  $self->dbExec('DELETE FROM edit_staff_aliases');
  if ($o->{aid}) {
    $self->dbExec(q|
      INSERT INTO edit_staff_aliases (id, name, original) VALUES (?, ?, ?)|,
      $o->{aid}, $o->{name}, $o->{original});
  } else {
    $o->{aid} = $self->dbRow(q|
      INSERT INTO edit_staff_aliases (name, original) VALUES (?, ?) RETURNING id|,
      $o->{name}, $o->{original})->{id};
  }

  my %staff = map exists($o->{$_}) ? (qq|"$_" = ?|, $o->{$_}) : (),
    qw|aid image gender lang desc l_wp|;
  $self->dbExec('UPDATE edit_staff !H', \%staff) if %staff;
  for my $alias (@{$o->{aliases}}) {
    if ($alias->[0]) {
      $self->dbExec('INSERT INTO edit_staff_aliases (id, name, original) VALUES (!l)', $alias);
    } else {
      $self->dbExec('INSERT INTO edit_staff_aliases (name, original) VALUES (?, ?)',
        $alias->[1], $alias->[2]);
    }
  }
}

1;
