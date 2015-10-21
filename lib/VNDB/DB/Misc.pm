
package VNDB::DB::Misc;

use strict;
use warnings;
use Exporter 'import';

our @EXPORT = qw|
  dbStats dbItemEdit dbRevisionGet dbRandomQuote
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
# Arguments: type [vrp], itemid, rev, %options->{ editsum uid ihid ilock + db[item]RevisionInsert }
#  rev = changes.rev of the revision this edit is based on, undef to create a new DB item
# Returns: { itemid, chid, rev }
sub dbItemEdit {
  my($self, $type, $itemid, $rev, %o) = @_;

  $self->dbExec('SELECT edit_!s_init(?, ?)', $type, $itemid, $rev);
  $self->dbExec('UPDATE edit_revision !H', {
    'requester = ?' => $o{uid}||$self->authInfo->{id},
    'ip = ?'        => $self->reqIP,
    'comments = ?'  => $o{editsum},
    exists($o{ihid})  ? ('ihid = ?'  => $o{ihid} ?1:0) : (),
    exists($o{ilock}) ? ('ilock = ?' => $o{ilock}?1:0) : (),
  });

  $self->dbVNRevisionInsert(      \%o) if $type eq 'v';
  $self->dbProducerRevisionInsert(\%o) if $type eq 'p';
  $self->dbReleaseRevisionInsert( \%o) if $type eq 'r';
  $self->dbCharRevisionInsert(    \%o) if $type eq 'c';
  $self->dbStaffRevisionInsert(   \%o) if $type eq 's';

  return $self->dbRow('SELECT * FROM edit_!s_commit()', $type);
}


# Options: type, itemid, uid, auto, hidden, edit, page, results, releases
sub dbRevisionGet {
  my($self, %o) = @_;
  $o{results} ||= 10;
  $o{page} ||= 1;
  $o{auto} ||= 0;   # 0:show, -1:only, 1:hide
  $o{hidden} ||= 0;
  $o{edit} ||= 0;   # 0:both, -1:new, 1:edits
  $o{releases} = 0 if !$o{type} || $o{type} ne 'v' || !$o{itemid};

  my %where = (
    $o{releases} ? (
      # This selects all changes of releases that are currently linked to the VN, not release revisions that are linked to the VN.
      # The latter seems more useful, but is also a lot more expensive.
      q{((c.type = 'v' AND c.itemid = ?) OR (c.type = 'r' AND c.itemid = ANY(ARRAY(SELECT rv.id FROM releases_vn rv WHERE rv.vid = ?))))} => [$o{itemid}, $o{itemid}],
    ) : (
      $o{type} ? (
        'c.type IN(!l)' => [ ref($o{type})?$o{type}:[$o{type}] ] ) : (),
      $o{itemid} ? (
        'c.itemid = ?' => [ $o{itemid} ] ) : (),
    ),
    $o{uid} ? (
      'c.requester = ?' => $o{uid} ) : (),
    $o{auto} ? (
      'c.requester !s 1' => $o{auto} < 0 ? '=' : '<>' ) : (),
    $o{hidden} ? (
     '!s EXISTS(SELECT 1 FROM changes c2 WHERE c2.type = c.type AND c2.itemid = c.itemid AND c2.ihid AND'.
        ' c2.rev = (SELECT MAX(c3.rev) FROM changes c3 WHERE c3.type = c.type AND c3.itemid = c.itemid))' => $o{hidden} == 1 ? 'NOT' : '') : (),
    $o{edit} ? (
      'c.rev !s 1' => $o{edit} < 0 ? '=' : '>' ) : (),
  );

  my($r, $np) = $self->dbPage(\%o, q|
    SELECT c.id, c.type, c.itemid, c.requester, c.comments, c.rev, extract('epoch' from c.added) as added, u.username
      FROM changes c
      JOIN users u ON c.requester = u.id
      !W
      ORDER BY c.id DESC|, \%where
  );

  # I couldn't find a way to fetch the titles the main query above without slowing it down considerably, so let's just do it this way.
  if(@$r) {
    my %r = map +($_->{id}, $_), @$r;
    my $w = join ' OR ', ('(type = ? AND id = ?)') x @$r;
    my @w = map +($_->{type}, $_->{id}), @$r;

    $r{ $_->{id} }{ititle} = $_->{title}, $r{ $_->{id} }{ioriginal} = $_->{original} for(@{$self->dbAll("
        SELECT id, title, original FROM (
                    SELECT 'v'::dbentry_type, chid, title, original FROM vn_hist
          UNION ALL SELECT 'r'::dbentry_type, chid, title, original FROM releases_hist
          UNION ALL SELECT 'p'::dbentry_type, chid, name,  original FROM producers_hist
          UNION ALL SELECT 'c'::dbentry_type, chid, name,  original FROM chars_hist
          UNION ALL SELECT 's'::dbentry_type, sh.chid, name, original FROM staff_hist sh JOIN staff_alias_hist sah ON sah.chid = sh.chid AND sah.aid = sh.aid
        ) x(type, id, title, original)
        WHERE $w
      ", @w
    )});
  }

  return wantarray ? ($r, $np) : $r;
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

