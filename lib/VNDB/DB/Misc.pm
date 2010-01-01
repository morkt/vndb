
package VNDB::DB::Misc;

use strict;
use warnings;
use Exporter 'import';

our @EXPORT = qw|
  dbStats dbItemEdit dbRevisionGet dbItemMod dbRandomQuote
|;


# Returns: hashref, key = section, value = number of (visible) entries
# Sections: vn, producers, releases, users, threads, posts
sub dbStats {
  my $s = shift;
  return { map {
    $_->{section} eq 'threads_posts' ? 'posts' : $_->{section}, $_->{count}
  } @{$s->dbAll('SELECT * FROM stats_cache')}};
}


# Inserts a new revision into the database
# Arguments: type [vrp], revision id, %options->{ editsum uid + db[item]RevisionInsert }
#  revision id = changes.id of the revision this edit is based on, undef to create a new DB item
# Returns: { iid, cid, rev }
sub dbItemEdit {
  my($self, $type, $oid, %o) = @_;

  die "Only VNs are supported at this moment!" if $type ne 'v';
  $self->dbExec('SELECT edit_!s_init(?)',
    {qw|v vn r releases p producers|}->{$type}, $oid);
  $self->dbExec('UPDATE edit_revision SET requester = ?, ip = ?, comments = ?',
    $o{uid}||$self->authInfo->{id}, $self->reqIP, $o{editsum});

  $self->dbVNRevisionInsert(      \%o) if $type eq 'v';
  #$self->dbProducerRevisionInsert(\%o) if $type eq 'p';
  #$self->dbReleaseRevisionInsert( \%o) if $type eq 'r';

  return $self->dbRow('SELECT * FROM edit_vn_commit()');
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
    qw|c.id c.type c.requester c.comments c.rev|,
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

