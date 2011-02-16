
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
# Arguments: type [vrp], revision id, %options->{ editsum uid ihid ilock + db[item]RevisionInsert }
#  revision id = changes.id of the revision this edit is based on, undef to create a new DB item
# Returns: { iid, cid, rev }
sub dbItemEdit {
  my($self, $type, $oid, %o) = @_;

  my $fun = {qw|v vn r release p producer c char|}->{$type};
  $self->dbExec('SELECT edit_!s_init(?)', $fun, $oid);
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

  return $self->dbRow('SELECT * FROM edit_!s_commit()', $fun);
}


# Options: type, iid, uid, auto, hidden, edit, page, results, what, releases
# what: item user
# Not very fast in each situation. Can be further optimized by: putting indexes
# on *_rev.?id, or by caching iid, ititle and ihidden in the changes table.
sub dbRevisionGet {
  my($self, %o) = @_;
  $o{results} ||= 10;
  $o{page} ||= 1;
  $o{auto} ||= 0;   # 0:show, -1:only, 1:hide
  $o{hidden} ||= 0;
  $o{edit} ||= 0;   # 0:both, -1:new, 1:edits
  $o{what} ||= '';
  $o{releases} = 0 if !$o{type} || $o{type} ne 'v' || !$o{iid};

  my %tables = qw|v vn r releases p producers c chars|;
  # what types should we join?
  my @types = (
    !$o{type} ? ('v', 'r', 'p', 'c') :
    $o{type} ne 'v' ? $o{type} :
    $o{releases} ? ('v', 'r') : 'v'
  );

  my %where = (
    $o{releases} ? (
      q{((c.type = 'v' AND vr.vid = ?) OR (c.type = 'r' AND c.id = ANY(ARRAY(SELECT rv.rid FROM releases_vn rv WHERE rv.vid = ?))))} => [$o{iid}, $o{iid}],
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
    $o{hidden} ? (
      '('.join(' OR ', map sprintf('%s.hidden IS NOT NULL AND %s %1$s.hidden', $_, $o{hidden} == 1 ? 'NOT' : ''), @types).')' => 1 ) : (),
    $o{edit} ? (
      'c.rev !s 1' => $o{edit} < 0 ? '=' : '>' ) : (),
  );

  my @join = (
    $o{iid} || $o{what} =~ /item/ || $o{hidden} || $o{releases} ? (
      map sprintf(q|LEFT JOIN %s_rev %sr ON c.type = '%2$s' AND c.id = %2$sr.id|, $tables{$_}, $_), @types
    ) : (),
    $o{hidden} ? (
      map sprintf(q|LEFT JOIN %s %s ON c.type = '%2$s' AND %2$sr.%2$sid = %2$s.id|, $tables{$_}, $_), @types
    ) : (),
    $o{what} =~ /user/ ? 'JOIN users u ON c.requester = u.id' : (),
  );

  my @select = (
    qw|c.id c.type c.requester c.comments c.rev|,
    q|extract('epoch' from c.added) as added|,
    $o{what} =~ /user/ ? 'u.username' : (),
    $o{what} =~ /item/ ? (
      'COALESCE('.join(', ', map "${_}r.${_}id", @types).') AS iid',
      'COALESCE('.join(', ', map /[pc]/ ? "${_}r.name" : "${_}r.title", @types).') AS ititle',
      'COALESCE('.join(', ', map "${_}r.original", @types).') AS ioriginal',
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


# Returns a random quote (hashref with keys = vid, quote)
sub dbRandomQuote {
  return $_[0]->dbRow(q|
    SELECT vid, quote
      FROM quotes
      ORDER BY RANDOM()
      LIMIT 1|);
}




1;

