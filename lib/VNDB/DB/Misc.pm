
package VNDB::DB::Misc;

use strict;
use warnings;
use Exporter 'import';

our @EXPORT = qw|
  dbStats dbRevisionInsert dbItemInsert dbRevisionGet
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


# Options: type, iid, uid, auto, hidden, page, results
sub dbRevisionGet {
  my($self, %o) = @_;
  $o{results} ||= 10;
  $o{page} ||= 1;
  $o{auto} ||= 0;   # 0:show, -1:only, 1:hide
  $o{hidden} ||= 0;

  my %where = (
    $o{type} ? (
      'c.type = ?' => { v=>0, r=>1, p=>2 }->{$o{type}} ) : (),
    $o{iid} ? (
      '!sr.!sid = ?' => [ $o{type}, $o{type}, $o{iid} ] ) : (),
    $o{uid} ? (
      'c.requester = ?' => $o{uid} ) : (),
    $o{auto} ? (
      'c.requester !s 1' => $o{auto} < 0 ? '=' : '<>' ) : (),
    $o{hidden} == 1 ? (
      '(v.hidden IS NOT NULL AND v.hidden = FALSE OR r.hidden IS NOT NULL AND r.hidden = FALSE OR p.hidden IS NOT NULL AND p.hidden = FALSE)' => 1,
    ) : $o{hidden} == -1 ? (
      '(v.hidden IS NOT NULL AND v.hidden = TRUE OR r.hidden IS NOT NULL AND r.hidden = TRUE OR p.hidden IS NOT NULL AND p.hidden = TRUE)' => 1,
    ) : (),
  );

  my @join = (
    $o{iid} || $o{what} =~ /item/ || $o{hidden} ? (
      'LEFT JOIN vn_rev vr ON c.type = 0 AND c.id = vr.id',
      'LEFT JOIN releases_rev rr ON c.type = 1 AND c.id = rr.id',
      'LEFT JOIN producers_rev pr ON c.type = 2 AND c.id = pr.id',
    ) : (),
    $o{hidden} ? (
      'LEFT JOIN vn v ON c.type = 0 AND vr.vid = v.id',
      'LEFT JOIN releases r ON c.type = 1 AND rr.rid = r.id',
      'LEFT JOIN producers p ON c.type = 2 AND pr.pid = p.id',
    ) : (),
    $o{what} =~ /user/ ? 'JOIN users u ON c.requester = u.id' : (),
  );

  my @select = (
    qw|c.id c.type c.added c.requester c.comments c.rev c.causedby|,
    $o{what} =~ /user/ ? 'u.username' : (),
    $o{what} =~ /item/ ? (
      'COALESCE(vr.vid, rr.rid, pr.pid) AS iid',
      'COALESCE(vr.title, rr.title, pr.name) AS ititle',
      'COALESCE(vr.original, rr.original, pr.original) AS ioriginal',
    ) : (),
  );

  my($r, $np) = $self->dbPage(\%o, q|
    SELECT !s
      FROM changes c
      !s
      !W
      ORDER BY c.id DESC|,
    join(', ', @select), join(' ', @join), \%where
  );
  return wantarray ? ($r, $np) : $r;
}


1;

