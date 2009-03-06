
package VNDB::DB::Tags;

use strict;
use warnings;
use Exporter 'import';

our @EXPORT = qw|dbTagGet dbTagEdit dbTagAdd dbTagDel dbTagLinks dbTagLinkEdit dbVNTags dbTagVNs|;


# %options->{ id name search page results order what }
# what: parents childs(n)
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
    $o{name} ? (
      'lower(t.name) = ?' => lc $o{name} ) : (),
    $o{search} ? (
      '(t.name ILIKE ? OR t.alias ILIKE ?)' => [ "%$o{search}%", "%$o{search}%" ] ) : (),
  );

  my($r, $np) = $self->dbPage(\%o, q|
    SELECT t.id, t.meta, t.name, t.alias, t.description
      FROM tags t
      !W
      ORDER BY !s|,
    \%where, $o{order}
  );

  if($o{what} =~ /parents\((\d+)\)/) {
    $_->{parents} = $self->dbAll(q|SELECT lvl, tag, name FROM tag_tree(?, ?, false)|, $_->{id}, $1) for (@$r);
  }

  if($o{what} =~ /childs\((\d+)\)/) {
    $_->{childs} = $self->dbAll(q|SELECT lvl, tag, name FROM tag_tree(?, ?, true)|, $_->{id}, $1) for (@$r);
  }

  #if(@$r && $o{what} =~ /(?:parents)/) {
    #my %r = map {
    #  ($r->[$_]{id}, $_)
    #} 0..$#$r;
  #}

  return wantarray ? ($r, $np) : $r;
}


# args: tag id, %options->{ columns in the tags table + parents }
sub dbTagEdit {
  my($self, $id, %o) = @_;

  $self->dbExec('UPDATE tags !H WHERE id = ?',
    { map { +"$_ = ?" => $o{$_} } qw|name meta alias description| }, $id);
  $self->dbExec('DELETE FROM tags_parents WHERE tag = ?', $id);
  $self->dbExec('INSERT INTO tags_parents (tag, parent) VALUES (?, ?)', $id, $_) for(@{$o{parents}});
  $self->dbExec('DELETE FROM tags_vn WHERE tag = ?', $id) if $o{meta};
}


# same args as dbTagEdit, without the first tag id
# returns the id of the new tag
sub dbTagAdd {
  my($self, %o) = @_;
  my $id = $self->dbRow('INSERT INTO tags (name, meta, alias, description) VALUES (!l) RETURNING id',
    [ map $o{$_}, qw|name meta alias description| ]
  )->{id};
  $self->dbExec('INSERT INTO tags_parents (tag, parent) VALUES (?, ?)', $id, $_) for(@{$o{parents}});
  return $id;
}


sub dbTagDel {
  my($self, $id) = @_;
  $self->dbExec('DELETE FROM tags_parents WHERE tag = ? OR parent = ?', $id, $id);
  $self->dbExec('DELETE FROM tags_vn WHERE tag = ?', $id);
  $self->dbExec('DELETE FROM tags WHERE id = ?', $id);
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


# Fetch all tags related to a VN
# Argument: vid
sub dbVNTags {
  my($self, $vid) = @_;
  return $self->dbAll(q|
    SELECT t.id, t.name, count(tv.uid) as users, avg(tv.vote) as rating, COALESCE(avg(tv.spoiler), 0) as spoiler
      FROM tags t
      JOIN tags_vn tv ON tv.tag = t.id
      WHERE tv.vid = ?
      GROUP BY t.id, t.name|,
    $vid
  );
}


# Fetch all VNs from a tag, including VNs from child tags, and provide ratings for them.
# Argument: %options->{ tag order page results }
sub dbTagVNs {
  my($self, %o) = @_;
  $o{order} ||= 'tb.rating DESC';
  $o{page} ||= 1;
  $o{results} ||= 10;

  my($r, $np) = $self->dbPage(\%o, q|
    SELECT tb.tag, tb.vid, tb.users, tb.rating, tb.spoiler, vr.title, vr.original, v.c_languages, v.c_released, v.c_platforms, v.c_popularity
      FROM tags_vn_bayesian tb
      JOIN vn v ON v.id = tb.vid
      JOIN vn_rev vr ON vr.id = v.latest
      WHERE tag = ?
      ORDER BY !s|,
    $o{tag}, $o{order});
  return wantarray ? ($r, $np) : $r;
}

1;

