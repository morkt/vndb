
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

  my $fun = {qw|v vn r release p producer c char s staff|}->{$type};
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
  $self->dbStaffRevisionInsert(   \%o) if $type eq 's';

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

  my %tables = qw|v vn r releases p producers c chars s staff|;
  # what types should we join?
  my @types = (
    !$o{type} ? qw(v r p c s) :
    ref($o{type}) ? @{$o{type}} :
    $o{type} ne 'v' ? $o{type} :
    $o{releases} ? ('v', 'r') : 'v'
  );

  my %where = (
    $o{releases} ? (
      q{((h.type = 'v' AND vr.vid = ?) OR (h.type = 'r' AND h.id = ANY(ARRAY(SELECT rv.rid FROM releases_vn rv WHERE rv.vid = ?))))} => [$o{iid}, $o{iid}],
    ) : (
      $o{type} ? (
        'h.type IN(!l)' => [ ref($o{type})?$o{type}:[$o{type}] ] ) : (),
      $o{iid} ? (
        '!sr.!sid = ?' => [ $o{type}, $o{type}, $o{iid} ] ) : (),
    ),
    $o{uid} ? (
      'h.requester = ?' => $o{uid} ) : (),
    $o{auto} ? (
      'h.requester !s 1' => $o{auto} < 0 ? '=' : '<>' ) : (),
    $o{hidden} ? (
      '('.join(' OR ', map sprintf('%s.hidden IS NOT NULL AND %s %1$s.hidden', $_, $o{hidden} == 1 ? 'NOT' : ''), @types).')' => 1 ) : (),
    $o{edit} ? (
      'h.rev !s 1' => $o{edit} < 0 ? '=' : '>' ) : (),
  );

  my @join = (
    $o{iid} || $o{what} =~ /item/ || $o{hidden} || $o{releases} ? (
      map sprintf(q|LEFT JOIN %s_rev %sr ON h.type = '%2$s' AND h.id = %2$sr.id|, $tables{$_}, $_), @types
    ) : (),
    $o{hidden} ? (
      map sprintf(q|LEFT JOIN %s %s ON h.type = '%2$s' AND %2$sr.%2$sid = %2$s.id|, $tables{$_}, $_), @types
    ) : (),
    $o{what} =~ /user/ ? 'JOIN users u ON h.requester = u.id' : (),
  );
  push @join, 'LEFT JOIN staff_alias sa ON sa.rid = sr.id AND sa.id = sr.aid' if grep /s/, @types;

  my %tcolumns = qw(v vr.title r rr.title p pr.name c cr.name s sa.name);
  my @select = (
    qw|h.id h.type h.requester h.comments h.rev|,
    q|extract('epoch' from h.added) as added|,
    $o{what} =~ /user/ ? 'u.username' : (),
    $o{what} =~ /item/ ? (
      'COALESCE('.join(', ', map "${_}r.${_}id", @types).') AS iid',
      'COALESCE('.join(', ', map $tcolumns{$_}, @types).') AS ititle',
      'COALESCE('.join(', ', map /s/ ? 'sa.original' : "${_}r.original", @types).') AS ioriginal',
    ) : (),
  );

  my($r, $np) = $self->dbPage(\%o, q|
    SELECT !s
      FROM changes h
      !s
      !W
      ORDER BY h.id DESC|,
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

