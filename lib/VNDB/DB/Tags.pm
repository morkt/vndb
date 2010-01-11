
package VNDB::DB::Tags;

use strict;
use warnings;
use Exporter 'import';

our @EXPORT = qw|dbTagGet dbTagTree dbTagEdit dbTagAdd dbTagMerge dbTagLinks dbTagLinkEdit dbTagStats|;


# %options->{ id noid name search state meta page results what sort reverse  }
# what: parents childs(n) aliases addedby
# sort: id name added vns
sub dbTagGet {
  my $self = shift;
  my %o = (
    page => 1,
    results => 10,
    what => '',
    @_
  );

  $o{search} =~ s/%//g if $o{search};

  my %where = (
    $o{id} ? (
      't.id = ?' => $o{id} ) : (),
    $o{noid} ? (
      't.id <> ?' => $o{noid} ) : (),
    $o{name} ? (
      't.id = (SELECT id FROM tags LEFT JOIN tags_aliases ON id = tag WHERE lower(name) = ? OR lower(alias) = ? LIMIT 1)' => [ lc $o{name}, lc $o{name} ]) : (),
    defined $o{state} && $o{state} != -1 ? (
      't.state = ?' => $o{state} ) : (),
    !defined $o{state} && !$o{id} && !$o{name} ? (
      't.state <> 1' => 1 ) : (),
    $o{search} ? (
      't.id IN (SELECT id FROM tags LEFT JOIN tags_aliases ON id = tag WHERE name ILIKE ? OR alias ILIKE ?)' => [ "%$o{search}%", "%$o{search}%" ] ) : (),
    defined $o{meta} ? (
      't.meta = ?' => $o{meta}?1:0 ) : (),
  );
  my @select = (
    qw|t.id t.meta t.name t.description t.state t.c_vns|,
    q|extract('epoch' from t.added) as added|,
    $o{what} =~ /addedby/ ? ('t.addedby', 'u.username') : (),
  );
  my @join = $o{what} =~ /addedby/ ? 'JOIN users u ON u.id = t.addedby' : ();

  my $order = sprintf {
    id    => 't.id %s',
    name  => 't.name %s',
    added => 't.added %s',
    vns   => 't.c_vns %s',
  }->{ $o{sort}||'id' }, $o{reverse} ? 'DESC' : 'ASC';

  my($r, $np) = $self->dbPage(\%o, q|
    SELECT !s
      FROM tags t
      !s
      !W
      ORDER BY !s|,
    join(', ', @select), join(' ', @join), \%where, $order
  );

  if(@$r && $o{what} =~ /aliases/) {
    my %r = map {
      $_->{aliases} = [];
      ($_->{id}, $_->{aliases})
    } @$r;

    push @{$r{$_->{tag}}}, $_->{alias} for (@{$self->dbAll(q|
      SELECT tag, alias FROM tags_aliases WHERE tag IN(!l)|, [ keys %r ]
    )});
  }

  if($o{what} =~ /parents\((\d+)\)/) {
    $_->{parents} = $self->dbTagTree($_->{id}, $1, 1) for(@$r);
  }

  if($o{what} =~ /childs\((\d+)\)/) {
    $_->{childs} = $self->dbTagTree($_->{id}, $1) for(@$r);
  }

  return wantarray ? ($r, $np) : $r;
}


# Walks the tag tree
#  id = tag to start with, or 0 to start with top-level tags
#  lvl = max. recursion level
#  back = false for parent->child, true for child->parent
# Returns: [ { id, name, c_vns, sub => [ { id, name, c_vns, sub => [..] }, .. ] }, .. ]
sub dbTagTree {
  my($self, $id, $lvl, $back) = @_;
  $lvl ||= 15;
  my $r = $self->dbAll(q|
    WITH RECURSIVE tagtree(lvl, id, parent, name, c_vns) AS (
        SELECT ?::integer, id, 0, name, c_vns
        FROM tags
        !W
      UNION ALL
        SELECT tt.lvl-1, t.id, tt.id, t.name, t.c_vns
        FROM tagtree tt
        JOIN tags_parents tp ON !s
        JOIN tags t ON !s
        WHERE tt.lvl > 0
          AND t.state = 2
    ) SELECT DISTINCT id, parent, name, c_vns FROM tagtree ORDER BY name|, $lvl,
    $id ? {'id = ?' => $id} : {'NOT EXISTS(SELECT 1 FROM tags_parents WHERE tag = id)' => 1, 'state = 2' => 1},
    !$back ? ('tp.parent = tt.id', 't.id = tp.tag') : ('tp.tag = tt.id', 't.id = tp.parent')
  );
  for my $i (@$r) {
    $i->{'sub'} = [ grep $_->{parent} == $i->{id}, @$r ];
  }
  my @r = grep !delete($_->{parent}), @$r;
  return $id ? $r[0]{'sub'} : \@r;
}


# args: tag id, %options->{ columns in the tags table + parents + aliases }
sub dbTagEdit {
  my($self, $id, %o) = @_;

  $self->dbExec('UPDATE tags !H WHERE id = ?', {
    $o{upddate} ? ('added = NOW()' => 1) : (),
    map { +"$_ = ?" => $o{$_} } qw|name meta description state|
  }, $id);
  $self->dbExec('DELETE FROM tags_aliases WHERE tag = ?', $id);
  $self->dbExec('INSERT INTO tags_aliases (tag, alias) VALUES (?, ?)', $id, $_) for (@{$o{aliases}});
  $self->dbExec('DELETE FROM tags_parents WHERE tag = ?', $id);
  $self->dbExec('INSERT INTO tags_parents (tag, parent) VALUES (?, ?)', $id, $_) for(@{$o{parents}});
  $self->dbExec('DELETE FROM tags_vn WHERE tag = ?', $id) if $o{meta} || $o{state} == 1;
}


# same args as dbTagEdit, without the first tag id
# returns the id of the new tag
sub dbTagAdd {
  my($self, %o) = @_;
  my $id = $self->dbRow('INSERT INTO tags (name, meta, description, state, addedby) VALUES (!l, ?) RETURNING id',
    [ map $o{$_}, qw|name meta description state| ], $o{addedby}||$self->authInfo->{id}
  )->{id};
  $self->dbExec('INSERT INTO tags_parents (tag, parent) VALUES (?, ?)', $id, $_) for(@{$o{parents}});
  $self->dbExec('INSERT INTO tags_aliases (tag, alias) VALUES (?, ?)', $id, $_) for (@{$o{aliases}});
  return $id;
}


sub dbTagMerge {
  my($self, $id, @merge) = @_;
  $self->dbExec('UPDATE tags_vn SET tag = ? WHERE tag IN(!l)', $id, \@merge);
  $self->dbExec('UPDATE tags_aliases SET tag = ? WHERE tag IN(!l)', $id, \@merge);
  $self->dbExec('INSERT INTO tags_aliases (tag, alias) VALUES (?, ?)', $id, $_->{name})
    for (@{$self->dbAll('SELECT name FROM tags WHERE id IN(!l)', \@merge)});
  $self->dbExec('DELETE FROM tags_parents WHERE tag IN(!l)', \@merge);
  $self->dbExec('DELETE FROM tags WHERE id IN(!l)', \@merge);
}


# Directly fetch rows from tags_vn
# Arguments: %options->{ vid uid tag }
sub dbTagLinks {
  my($self, %o) = @_;
  return $self->dbAll(
    'SELECT tag, vid, uid, vote, spoiler FROM tags_vn !W',
    { map { +"$_ = ?" => $o{$_} } keys %o }
  );
}


# Change a user's tags for a VN entry
# Arguments: uid, vid, [ [ tag, vote, spoiler ], .. ]
sub dbTagLinkEdit {
  my($self, $uid, $vid, $tags) = @_;
  $self->dbExec('DELETE FROM tags_vn WHERE vid = ? AND uid = ?', $vid, $uid);
  $self->dbExec('INSERT INTO tags_vn (tag, vid, uid, vote, spoiler) VALUES (?, ?, ?, ?, ?)',
    $_->[0], $vid, $uid, $_->[1], $_->[2] == -1 ? undef : $_->[2]
  ) for (@$tags);
}


# Fetch all tags related to a VN or User
# Argument: %options->{ uid vid minrating results what page sort reverse }
# what: vns
# sort: name, count, rating
sub dbTagStats {
  my($self, %o) = @_;
  $o{results} ||= 10;
  $o{page}  ||= 1;
  $o{what}  ||= '';

  my %where = (
    $o{uid} ? (
      'tv.uid = ?' => $o{uid} ) : (),
    $o{vid} ? (
      'tv.vid = ?' => $o{vid} ) : (),
  );

  my $order = sprintf {
    name => 't.name %s',
    count => 'count(*) %s',
    rating => 'avg(tv.vote) %s',
  }->{ $o{sort}||'name' }, $o{reverse} ? 'DESC' : 'ASC';

  my($r, $np) = $self->dbPage(\%o, q|
    SELECT t.id, t.name, count(*) as cnt, avg(tv.vote) as rating, COALESCE(avg(tv.spoiler), 0) as spoiler
      FROM tags t
      JOIN tags_vn tv ON tv.tag = t.id
      !W
      GROUP BY t.id, t.name
      !s
      ORDER BY !s|,
    \%where, defined $o{minrating} ? "HAVING avg(tv.vote) > $o{minrating}" : '',
    $order
  );

  if(@$r && $o{what} =~ /vns/ && $o{uid}) {
    my %r = map {
      $_->{vns} = [];
      ($_->{id}, $_->{vns})
    } @$r;

    push @{$r{$_->{tag}}}, $_ for (@{$self->dbAll(q|
      SELECT tv.tag, tv.vote, tv.spoiler, vr.vid, vr.title, vr.original
        FROM tags_vn tv
        JOIN vn v ON v.id = tv.vid
        JOIN vn_rev vr ON vr.id = v.latest
        WHERE tv.uid = ?
          AND tv.tag IN(!l)
        ORDER BY vr.title ASC|,
      $o{uid}, [ keys %r ]
    )});
  }

  return wantarray ? ($r, $np) : $r;
}


1;

