
package VNDB::DB::Staff;

use strict;
use warnings;
use Exporter 'import';

our @EXPORT = qw|dbStaffGet dbStaffRevisionInsert|;

# options: results, page, id, aid, search, rev
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

  my $select = 's.id, sa.id AS aid, sa.name, sa.original, sr.gender, sr.lang, sr.id AS cid';
  $select .= ', sr.desc, sr.l_wp, sr.l_site, sr.l_twitter, sr.l_anidb, s.hidden, s.locked' if $o{what} =~ /extended/;
  $select .= q|, extract('epoch' from c.added) as added, c.requester, c.comments, s.latest, u.username, c.rev, c.ihid, c.ilock| if $o{what} =~ /changes/;

  my $order = 'ORDER BY sa.name';

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
        SELECT sa.rid, vr.vid, sa.name, sa.original, v.c_released, vr.title, vr.original AS t_original, vs.role, vs.note
          FROM vn_staff vs
          JOIN vn_rev vr ON vr.id = vs.vid
          JOIN vn v ON v.latest = vr.id
          JOIN staff_alias sa ON vs.aid = sa.id
          WHERE sa.rid IN(!l)
          ORDER BY v.c_released ASC, vr.title ASC, vs.role ASC|, [ keys %r ]
      )});
      push @{$r{ delete $_->{rid} }{cast}}, $_ for (@{$self->dbAll(q|
        SELECT sa.rid, vr.vid, sa.name, sa.original, v.c_released, vr.title, vr.original AS t_original, cr.cid, cr.name AS c_name, cr.original AS c_original, vs.note
          FROM vn_seiyuu vs
          JOIN vn_rev vr ON vr.id = vs.vid
          JOIN vn v ON v.latest = vr.id
          JOIN chars_rev cr ON cr.cid = vs.cid
          JOIN chars c ON c.latest = cr.id
          JOIN staff_alias sa ON vs.aid = sa.id
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
    qw|aid image gender lang desc l_wp l_site l_twitter l_anidb|;
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