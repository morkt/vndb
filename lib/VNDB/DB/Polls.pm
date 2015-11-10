
package VNDB::DB::Polls;

use strict;
use warnings;
use Exporter 'import';

our @EXPORT = qw|dbPollGet dbPollVote dbPollAdd dbPollEdit|;


# Options: id, tid, uid, what
# What: votes
sub dbPollGet {
  my($self, %o) = @_;
  $o{what} ||= '';
  $o{uid} ||= $self->authInfo->{id};

  my %where = (
    $o{id}  ? ('p.id = ?'  => $o{id})  :
    $o{tid} ? ('p.tid = ?' => $o{tid}) : (),
  );

  my @select = (
    qw|p.id p.question p.max_options p.preview p.recast|,
    $o{what} =~ /votes/ ?
      ('(SELECT COUNT(DISTINCT uid) FROM polls_votes pv WHERE pv.pid = p.id) AS votes') : (),
  );
  my $p = $self->dbRow(q|
    SELECT !s
      FROM polls p
      !W|,
    join(', ', @select), \%where
  );
  return $p unless %$p;

  my $options_query = $o{what} =~ /votes/ ?
    q|SELECT id, option, COUNT(pv.optid) AS votes
        FROM polls_options po
        LEFT JOIN polls_votes pv ON po.id = pv.optid
        WHERE po.pid = ? GROUP BY id ORDER BY id| :
    q|SELECT id, option
        FROM polls_options po
        WHERE po.pid = ? ORDER BY id|;
  $p->{options} = $self->dbAll($options_query, $p->{id});

  $p->{user} = $o{uid} ? [
    map $_->{optid}, @{$self->dbAll(q|
      SELECT optid FROM polls_votes
        WHERE pid = ? AND uid = ?|, $p->{id}, $o{uid})}
  ] : [];

  return $p;
}


sub dbPollVote {
  my($self, $id, %o) = @_;

  $self->dbExec('DELETE FROM polls_votes WHERE pid = ? AND uid = ?', $id, $o{uid});
  $self->dbExec('INSERT INTO polls_votes (pid, uid, optid) VALUES (?, ?, ?)',
    $id, $o{uid}, $_) for @{$o{options}};
}


sub dbPollAdd {
  my($self, %o) = @_;

  my $id = $self->dbRow(q|
    INSERT INTO polls (tid, question, max_options, preview, recast)
      VALUES (?, ?, ?, ?, ?) RETURNING id|,
    $o{tid}, $o{question}, $o{max_options}, $o{preview}, $o{recast}
  )->{id};

  $self->dbExec('INSERT INTO polls_options (pid, option) VALUES (?, ?)', $id, $_)
    for @{$o{options}};

  return $id;
}


sub dbPollEdit {
  my($self, $id, %o) = @_;

  my %set = map exists $o{$_} ? ("$_ = ?" => $o{$_}) : (),
    qw|question max_options preview recast|;

  $self->dbExec('UPDATE polls !H WHERE id = ?', \%set, $id);
  $self->dbExec('DELETE FROM polls_options WHERE pid = ?', $id);
  $self->dbExec('INSERT INTO polls_options (pid, option) VALUES (?, ?)', $id, $_)
    for @{$o{options}};
}


1;

