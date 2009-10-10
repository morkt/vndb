
package VNDB::DB::Misc;

use strict;
use warnings;
use Exporter 'import';

our @EXPORT = qw|
  dbStats dbRevisionInsert dbItemInsert dbRevisionGet dbItemMod dbRandomQuote
|;


# Returns: hashref, key = section, value = number of (visible) entries
# Sections: vn, producers, releases, users, threads, posts
sub dbStats {
  my $s = shift;
  return { map {
    $_->{section} eq 'threads_posts' ? 'posts' : $_->{section}, $_->{count}
  } @{$s->dbAll('SELECT * FROM stats_cache')}};
}


# Inserts a new revision and updates the item to point to this revision
#  This function leaves the DB in an inconsistent state, the actual revision
#  will have to be inserted directly after calling this function, otherwise
#  the commit will fail.
# Arguments: type [0..2], item ID, edit summary
# Returns: local revision, global revision
sub dbRevisionInsert {
  my($self, $type, $iid, $editsum, $uid) = @_;

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
    $type, $uid||$self->authInfo->{id}, $self->reqIP, $editsum,
    $table, [qw|v r p|]->[$type], $iid
  );

  $self->dbExec(q|UPDATE !s SET latest = ? WHERE id = ?|, $table, $c->{id}, $iid);

  return ($c->{rev}, $c->{id});
}


# Comparable to RevisionInsert, but creates a new item with a corresponding
#  change. Same things about inconsistent state, etc.
# Argumments: type [0..2], edit summary, [uid]
# Returns: item id, global revision
sub dbItemInsert {
  my($self, $type, $editsum, $uid) = @_;

  my $cid = $self->dbRow(q|
    INSERT INTO changes (type, requester, ip, comments)
      VALUES (?, ?, ?, ?)
      RETURNING id|,
    $type, $uid||$self->authInfo->{id}, $self->reqIP, $editsum
  )->{id};

  my $iid = $self->dbRow(q|
    INSERT INTO !s (latest)
      VALUES (?)
      RETURNING id|,
    [qw|vn releases producers|]->[$type], $cid
  )->{id};

  return ($iid, $cid);
}


# Options: type, iid, uid, auto, hidden, edit, page, results, what, releases
# what: item user
sub dbRevisionGet {
  my($self, %o) = @_;
  $o{results} ||= 10;
  $o{page} ||= 1;
  $o{auto} ||= 0;   # 0:show, -1:only, 1:hide
  $o{hidden} ||= 0;
  $o{edit} ||= 0;   # 0:both, -1:new, 1:edits
  $o{what} ||= '';
  $o{releases} = 0 if !$o{type} || $o{type} ne 'v' || !$o{iid};

  my %where = (
    $o{releases} ? (
      '((c.type = ? AND vr.vid = ?) OR (c.type = ? AND rv.vid = ?))' => [0, $o{iid}, 1, $o{iid}],
    ) : (
      $o{type} ? (
        'c.type = ?' => { v=>0, r=>1, p=>2 }->{$o{type}} ) : (),
      $o{iid} ? (
        '!sr.!sid = ?' => [ $o{type}, $o{type}, $o{iid} ] ) : (),
    ),
    $o{uid} ? (
      'c.requester = ?' => $o{uid} ) : (),
    $o{auto} ? (
      'c.requester !s 1' => $o{auto} < 0 ? '=' : '<>' ) : (),
    $o{hidden} == 1 ? (
      '(v.hidden IS NOT NULL AND v.hidden = FALSE OR r.hidden IS NOT NULL AND r.hidden = FALSE OR p.hidden IS NOT NULL AND p.hidden = FALSE)' => 1,
    ) : $o{hidden} == -1 ? (
      '(v.hidden IS NOT NULL AND v.hidden = TRUE OR r.hidden IS NOT NULL AND r.hidden = TRUE OR p.hidden IS NOT NULL AND p.hidden = TRUE)' => 1,
    ) : (),
    $o{edit} ? (
      'c.rev !s 1' => $o{edit} < 0 ? '=' : '>' ) : (),
  );

  my @join = (
    $o{iid} || $o{what} =~ /item/ || $o{hidden} || $o{releases} ? (
      'LEFT JOIN vn_rev vr ON c.type = 0 AND c.id = vr.id',
      'LEFT JOIN releases_rev rr ON c.type = 1 AND c.id = rr.id',
      'LEFT JOIN producers_rev pr ON c.type = 2 AND c.id = pr.id',
    ) : (),
    $o{hidden} || $o{releases} ? (
      'LEFT JOIN vn v ON c.type = 0 AND vr.vid = v.id',
      'LEFT JOIN releases r ON c.type = 1 AND rr.rid = r.id',
      'LEFT JOIN producers p ON c.type = 2 AND pr.pid = p.id',
    ) : (),
    $o{what} =~ /user/ ? 'JOIN users u ON c.requester = u.id' : (),
    $o{releases} ? 'LEFT JOIN releases_vn rv ON c.id = rv.rid' : (),
  );

  my @select = (
    qw|c.id c.type c.requester c.comments c.rev c.causedby|,
    q|extract('epoch' from c.added) as added|,
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


# Lock or hide a DB item
# arguments: v/r/p, id, %options ->( hidden, locked )
sub dbItemMod {
  my($self, $type, $id, %o) = @_;
  $self->dbExec('UPDATE !s !H WHERE id = ?',
    {qw|v vn r releases p producers|}->{$type},
    { map { ($_.' = ?', int $o{$_}) } keys %o }, $id
  );
}


# Returns a random quote (hashref with keys = vid, quote)
sub dbRandomQuote {
  return $_[0]->dbRow(q|
    SELECT vid, quote
      FROM quotes
      ORDER BY RANDOM()
      LIMIT 1|);
}




1;

