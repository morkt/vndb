
package VNDB::DB::Tags;

use strict;
use warnings;
use Exporter 'import';

our @EXPORT = qw|dbTagGet dbTagEdit dbTagAdd|;


# %options->{ id page results order what }
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

  my %where = (
    $o{id} ? (
      't.id = ?' => $o{id} ) : (),
  );

  my($r, $np) = $self->dbPage(\%o, q|
    SELECT t.id, t.meta, t.name, t.aliases, t.description
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
    { map { +"$_ = ?" => $o{$_} } qw|name meta aliases description| }, $id);
  $self->dbExec('DELETE FROM tags_parents WHERE tag = ?', $id);
  $self->dbExec('INSERT INTO tags_parents (tag, parent) VALUES (?, ?)', $id, $_) for(@{$o{parents}});
  $self->dbExec('DELETE FROM tags_vn WHERE tag = ?', $id) if $o{meta};
}


# same args as dbTagEdit, without the first tag id
# returns the id of the new tag
sub dbTagAdd {
  my($self, %o) = @_;
  my $id = $self->dbRow('INSERT INTO tags (name, meta, aliases, description) VALUES (!l) RETURNING id',
    [ map $o{$_}, qw|name meta aliases description| ]
  )->{id};
  $self->dbExec('INSERT INTO tags_parents (tag, parent) VALUES (?, ?)', $id, $_) for(@{$o{parents}});
  return $id;
}


1;

