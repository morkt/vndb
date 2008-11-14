
package VNDB::DB::Misc;

use strict;
use warnings;
use Exporter 'import';

our @EXPORT = qw|
  dbStats dbRevisionInsert dbItemInsert
|;


# Arguments: array of elements to get stats from, options:
#   vn, producers, releases, users, threads, posts
# Returns: hashref, key = element, value = number of entries
# TODO: caching, see http://www.varlena.com/GeneralBits/120.php
sub dbStats { 
  my $s = shift;
  return { map {
    $_ => $s->dbRow('SELECT COUNT(*) as cnt FROM !s !W',
      /posts/ ? 'threads_posts' : $_,
      /producers|vn|releases|threads|posts/ ? { 'hidden = ?' => 0 } : {}
    )->{cnt} - (/users/ ? 1 : 0);
  } @_ };
}


# Inserts a new revision and updates the item to point to this revision
#  This function leaves the DB in an inconsistent state, the actual revision
#  will have to be inserted directly after calling this function, otherwise
#  the commit will fail.
# Arguments: type [0..2], item ID, edit summary
# Returns: local revision, global revision
sub dbRevisionInsert {
  my($self, $type, $iid, $editsum) = @_;

  my $table = [qw|vn releases producers|]->[$type];

  my $c = $self->dbRow(q|
    INSERT INTO changes (type, requester, ip, comments, rev)
      VALUES (?, ?, ?, ?, (
        SELECT c.rev+1
        FROM changes c
        JOIN !s_rev ir ON ir.id = c.id
        WHERE ir.!sid = ?
        ORDER BY c.id DESC
        LIMIT 1
      ))
      RETURNING id, rev|,
    $type, $self->authInfo->{id}, $self->reqIP, $editsum,
    $table, [qw|v r p|]->[$type], $iid
  );

  $self->dbExec(q|UPDATE !s SET latest = ? WHERE id = ?|, $table, $c->{id}, $iid);

  return ($c->{rev}, $c->{id});
}


# Comparable to RevisionInsert, but creates a new item with a corresponding
#  change. Same things about inconsistent state, etc.
# Argumments: type [0..2], edit summary
# Returns: item id, global revision
sub dbItemInsert {
  my($self, $type, $editsum) = @_;

  my $cid = $self->dbRow(q|
    INSERT INTO changes (type, requester, ip, comments)
      VALUES (?, ?, ?, ?)
      RETURNING id|,
    $type, $self->authInfo->{id}, $self->reqIP, $editsum
  )->{id};

  my $iid = $self->dbRow(q|
    INSERT INTO !s (latest)
      VALUES (?)
      RETURNING id|,
    [qw|vn releases producers|]->[$type], $cid
  )->{id};

  return ($iid, $cid);
}


1;

