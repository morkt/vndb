
package VNDB::DB::Users;

use strict;
use warnings;
use Exporter 'import';

our @EXPORT = qw|
  dbUserGet dbUserEdit dbUserAdd dbUserDel
  dbSessionAdd dbSessionDel dbSessionUpdateLastUsed
  dbNotifyGet dbNotifyMarkRead dbNotifyRemove
|;


# %options->{ username passwd mail session uid ip registered search results page what sort reverse }
# what: notifycount stats extended
# sort: username registered votes changes tags
sub dbUserGet {
  my $s = shift;
  my %o = (
    page => 1,
    results => 10,
    what => '',
    @_
  );

  $o{search} =~ s/%// if $o{search};
  my %where = (
    $o{username} ? (
      'username = ?' => $o{username} ) : (),
    $o{firstchar} ? (
      'SUBSTRING(username from 1 for 1) = ?' => $o{firstchar} ) : (),
    !$o{firstchar} && defined $o{firstchar} ? (
      'ASCII(username) < 97 OR ASCII(username) > 122' => 1 ) : (),
    $o{mail} ? (
      'mail = ?' => $o{mail} ) : (),
    $o{uid} && !ref($o{uid}) ? (
      'id = ?' => $o{uid} ) : (),
    $o{uid} && ref($o{uid}) ? (
      'id IN(!l)' => [ $o{uid} ]) : (),
    !$o{uid} && !$o{username} ? (
      'id > 0' => 1 ) : (),
    $o{ip} ? (
      'ip = ?' => $o{ip} ) : (),
    $o{registered} ? (
      'registered > to_timestamp(?)' => $o{registered} ) : (),
    $o{search} ? (
      'username ILIKE ?' => "%$o{search}%") : (),
    $o{session} ? (
      q|s.token = decode(?, 'hex')| => $o{session} ) : (),
  );

  my @select = (
    qw|id username c_votes c_changes show_list c_tags|,
    q|extract('epoch' from registered) as registered|,
    $o{what} =~ /extended/ ? (
      qw|mail rank salt skin customcss show_nsfw ign_votes|,
      q|encode(passwd, 'hex') AS passwd|
    ) : (),
    $o{what} =~ /notifycount/ ?
      '(SELECT COUNT(*) FROM notifications WHERE uid = u.id AND read IS NULL) AS notifycount' : (),
    $o{what} =~ /stats/ ? (
      '(SELECT COUNT(*) FROM rlists WHERE uid = u.id) AS releasecount',
      '(SELECT COUNT(DISTINCT rv.vid) FROM rlists rl JOIN releases r ON rl.rid = r.id JOIN releases_vn rv ON rv.rid = r.latest WHERE uid = u.id) AS vncount',
      '(SELECT COUNT(*) FROM threads_posts WHERE uid = u.id) AS postcount',
      '(SELECT COUNT(*) FROM threads_posts WHERE uid = u.id AND num = 1) AS threadcount',
      '(SELECT COUNT(DISTINCT tag) FROM tags_vn WHERE uid = u.id) AS tagcount',
      '(SELECT COUNT(DISTINCT vid) FROM tags_vn WHERE uid = u.id) AS tagvncount',
    ) : (),
    $o{session} ? q|extract('epoch' from s.lastused) as session_lastused| : (),
  );

  my @join = (
    $o{session} ? 'JOIN sessions s ON s.uid = u.id' : (),
  );

  my $order = sprintf {
    username => 'u.username %s',
    registered => 'u.registered %s',
    votes => 'NOT u.show_list, u.c_votes %s',
    changes => 'u.c_changes %s',
    tags => 'u.c_tags %s',
  }->{ $o{sort}||'username' }, $o{reverse} ? 'DESC' : 'ASC';

  my($r, $np) = $s->dbPage(\%o, q|
    SELECT !s
      FROM users u
      !s
      !W
      ORDER BY !s|,
    join(', ', @select), join(' ', @join), \%where, $order
  );
  return wantarray ? ($r, $np) : $r;
}


# uid, %options->{ columns in users table }
sub dbUserEdit {
  my($s, $uid, %o) = @_;

  my %h;
  defined $o{$_} && ($h{$_.' = ?'} = $o{$_})
    for (qw| username mail rank show_nsfw show_list skin customcss salt ign_votes |);
  $h{'passwd = decode(?, \'hex\')'} = $o{passwd}
    if defined $o{passwd};

  return if scalar keys %h <= 0;
  return $s->dbExec(q|
    UPDATE users
    !H
    WHERE id = ?|,
  \%h, $uid);
}


# username, pass(ecrypted), salt, mail, [ip]
sub dbUserAdd {
  my($s, @o) = @_;
  $s->dbExec(q|INSERT INTO users (username, passwd, salt, mail, ip) VALUES(?, decode(?, 'hex'), ?, ?, ?)|,
    @o[0..3], $o[4]||$s->reqIP);
}


# uid
sub dbUserDel {
  my($s, $id) = @_;
  $s->dbExec($_, $id) for (
    q|DELETE FROM rlists WHERE uid = ?|,
    q|DELETE FROM wlists WHERE uid = ?|,
    q|DELETE FROM votes WHERE uid = ?|,
    q|DELETE FROM sessions WHERE uid = ?|,
    q|UPDATE changes SET requester = 0 WHERE requester = ?|,
    q|UPDATE threads_posts SET uid = 0 WHERE uid = ?|,
    q|DELETE FROM users WHERE id = ?|
  );
}


# Adds a session to the database
# uid, 40 character session token
sub dbSessionAdd {
  $_[0]->dbExec(q|INSERT INTO sessions (uid, token) VALUES(?, decode(?, 'hex'))|, @_[1,2]);
}


# Deletes session(s) from the database
# If no token is supplied, all sessions for the uid are destroyed
# uid, token (optional)
sub dbSessionDel {
  my($s, @o) = @_;
  my %where = ('uid = ?' => $o[0]);
  $where{"token = decode(?, 'hex')"} = $o[1] if $o[1];
  $s->dbExec('DELETE FROM sessions !W', \%where);
}


# uid, token
sub dbSessionUpdateLastUsed {
  $_[0]->dbExec(q|UPDATE sessions SET lastused = NOW() WHERE uid = ? AND token = decode(?, 'hex')|, $_[1], $_[2]);
}


# %options->{ uid id what results page }
# what: titles
sub dbNotifyGet {
  my($s, %o) = @_;
  $o{what} ||= '';
  $o{results} ||= 10;
  $o{page} ||= 1;

  my %where = (
    'n.uid = ?' => $o{uid},
    $o{id} ? (
      'n.id = ?' => $o{id} ) : (),
    defined($o{read}) ? (
      'n.read !s' => $o{read} ? 'IS NOT NULL' : 'IS NULL' ) : (),
  );

  my @join = (
    $o{what} =~ /titles/ ? 'LEFT JOIN users u ON n.c_byuser = u.id' : (),
  );

  my @select = (
    qw|n.id n.ntype n.ltype n.iid n.subid|,
    q|extract('epoch' from n.date) as date|,
    q|extract('epoch' from n.read) as read|,
    $o{what} =~ /titles/ ? qw|u.username n.c_title| : (),
  );

  my($r, $np) = $s->dbPage(\%o, q|
    SELECT !s
      FROM notifications n
      !s
      !W
      ORDER BY n.id
  |, join(', ', @select), join(' ', @join), \%where);
  return wantarray ? ($r, $np) : $r;
}


# ids
sub dbNotifyMarkRead {
  my $s = shift;
  $s->dbExec('UPDATE notifications SET read = NOW() WHERE id IN(!l)', \@_);
}


# ids
sub dbNotifyRemove {
  my $s = shift;
  $s->dbExec('DELETE FROM notifications WHERE id IN(!l)', \@_);
}


1;

