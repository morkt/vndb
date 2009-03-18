
package VNDB::DB::Tags;

use strict;
use warnings;
use Exporter 'import';

our @EXPORT = qw|dbTagGet dbTagTree dbTagEdit dbTagAdd dbTagMerge dbTagLinks dbTagLinkEdit dbTagStats dbTagVNs|;


# %options->{ id noid name search state meta page results order what }
# what: parents childs(n) aliases
sub dbTagGet {
  my $self = shift;
  my %o = (
    order => 't.id ASC',
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

  my($r, $np) = $self->dbPage(\%o, q|
    SELECT t.id, t.meta, t.name, t.description, t.added, t.state, t.c_vns
      FROM tags t
      !W
      ORDER BY !s|,
    \%where, $o{order}
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
    $_->{parents} = $self->dbTagTree($_->{id}, $1, 0) for(@$r);
  }

  if($o{what} =~ /childs\((\d+)\)/) {
    $_->{childs} = $self->dbTagTree($_->{id}, $1, 1) for(@$r);
  }

  return wantarray ? ($r, $np) : $r;
}


# plain interface to the tag_tree() stored procedure in pgsql
sub dbTagTree {
  my($self, $id, $lvl, $dir) = @_;
  return $self->dbAll('SELECT * FROM tag_tree(?, ?, ?)', $id, $lvl||0, $dir?1:0);
}


# args: tag id, %options->{ columns in the tags table + parents + aliases }
sub dbTagEdit {
  my($self, $id, %o) = @_;

  $self->dbExec('UPDATE tags !H WHERE id = ?', {
    $o{upddate} ? ('added = ?' => time) : (),
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
  my $id = $self->dbRow('INSERT INTO tags (name, meta, description, state) VALUES (!l) RETURNING id',
    [ map $o{$_}, qw|name meta description state| ]
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
# Argument: %options->{ uid vid minrating results what page order }
# what: vns
sub dbTagStats {
  my($self, %o) = @_;
  $o{results} ||= 10;
  $o{page}  ||= 1;
  $o{order} ||= 't.name ASC';
  $o{what}  ||= '';

  my %where = (
    $o{uid} ? (
      'tv.uid = ?' => $o{uid} ) : (),
    $o{vid} ? (
      'tv.vid = ?' => $o{vid} ) : (),
  );
  my($r, $np) = $self->dbPage(\%o, q|
    SELECT t.id, t.name, count(*) as cnt, avg(tv.vote) as rating, COALESCE(avg(tv.spoiler), 0) as spoiler
      FROM tags t
      JOIN tags_vn tv ON tv.tag = t.id
      !W
      GROUP BY t.id, t.name
      !s
      ORDER BY !s|,
    \%where, defined $o{minrating} ? "HAVING avg(tv.vote) > $o{minrating}" : '',
    $o{order}
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


# Fetch all VNs from a tag, including VNs from child tags, and provide ratings for them.
# Argument: %options->{ tag order page results maxspoil }
sub dbTagVNs {
  my($self, %o) = @_;
  $o{order} ||= 'tb.rating DESC';
  $o{page} ||= 1;
  $o{results} ||= 10;

  my %where = (
    'tag = ?' => $o{tag},
    defined $o{maxspoil} ? (
      'tb.spoiler <= ?' => $o{maxspoil} ) : (),
  );

  my($r, $np) = $self->dbPage(\%o, q|
    SELECT tb.tag, tb.vid, tb.users, tb.rating, tb.spoiler, vr.title, vr.original, v.c_languages, v.c_released, v.c_platforms, v.c_popularity
      FROM tags_vn_stored tb
      JOIN vn v ON v.id = tb.vid
      JOIN vn_rev vr ON vr.id = v.latest
      !W
      ORDER BY !s|,
    \%where, $o{order});
  return wantarray ? ($r, $np) : $r;
}

1;

