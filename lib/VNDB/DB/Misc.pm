
package VNDB::DB::Misc;

use strict;
use warnings;
use Exporter 'import';

our @EXPORT = qw|
  dbStats dbItemEdit dbItemAdd dbRevisionGet dbItemMod dbRandomQuote
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
# Arguments: type [vrp], item ID, %options->{ editsum uid + db[item]RevisionInsert }
# Returns: local revision, global revision
sub dbItemEdit {
  my($self, $type, $iid, %o) = @_;

  my $table = {qw|v vn r releases p producers|}->{$type};

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
    $type, $o{uid}||$self->authInfo->{id}, $self->reqIP, $o{editsum},
    $table, $type, $iid
  );

  $self->dbVNRevisionInsert(      $c->{id}, $iid, \%o) if $type eq 'v';
  $self->dbProducerRevisionInsert($c->{id}, $iid, \%o) if $type eq 'p';
  $self->dbReleaseRevisionInsert( $c->{id}, $iid, \%o) if $type eq 'r';

  $self->dbExec(q|UPDATE !s SET latest = ? WHERE id = ?|, $table, $c->{id}, $iid);
  return ($c->{rev}, $c->{id});
}


# Comparable to dbItemEdit(), but creates a new item with a corresponding revision.
# Argumments: type [vrp] + same option hash as dbItemEdit()
# Returns: item id, global revision
sub dbItemAdd {
  my($self, $type, %o) = @_;

  my $table = {qw|v vn r releases p producers|}->{$type};

  my $cid = $self->dbRow(q|
    INSERT INTO changes (type, requester, ip, comments)
      VALUES (?, ?, ?, ?)
      RETURNING id|,
    $type, $o{uid}||$self->authInfo->{id}, $self->reqIP, $o{editsum}
  )->{id};

  my $iid = $self->dbRow(q|
    INSERT INTO !s (latest)
      VALUES (0)
      RETURNING id|,
    $table
  )->{id};

  $self->dbVNRevisionInsert(      $cid, $iid, \%o) if $type eq 'v';
  $self->dbProducerRevisionInsert($cid, $iid, \%o) if $type eq 'p';
  $self->dbReleaseRevisionInsert( $cid, $iid, \%o) if $type eq 'r';

  $self->dbExec(q|UPDATE !s SET latest = ? WHERE id = ?|, $table, $cid, $iid);

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
      q{((c.type = 'v' AND vr.vid = ?) OR (c.type = 'r' AND rv.vid = ?))} => [$o{iid}, $o{iid}],
    ) : (
      $o{type} ? (
        'c.type = ?' => $o{type} ) : (),
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
      q{LEFT JOIN vn_rev vr ON c.type = 'v' AND c.id = vr.id},
      q{LEFT JOIN releases_rev rr ON c.type = 'r' AND c.id = rr.id},
      q{LEFT JOIN producers_rev pr ON c.type = 'p' AND c.id = pr.id},
    ) : (),
    $o{hidden} || $o{releases} ? (
      q{LEFT JOIN vn v ON c.type = 'v' AND vr.vid = v.id},
      q{LEFT JOIN releases r ON c.type = 'r' AND rr.rid = r.id},
      q{LEFT JOIN producers p ON c.type = 'p' AND pr.pid = p.id},
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

