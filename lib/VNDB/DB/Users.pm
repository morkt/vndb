
package VNDB::DB::Users;

use strict;
use warnings;
use Exporter 'import';

our @EXPORT = qw|
  dbUserGet dbUserEdit dbUserAdd dbUserDel dbUserPrefSet
  dbSessionAdd dbSessionDel dbSessionUpdateLastUsed
  dbNotifyGet dbNotifyMarkRead dbNotifyRemove
|;


# %options->{ username passwd mail session uid ip registered search results page what sort reverse }
# what: notifycount stats extended prefs hide_list
# sort: username registered votes changes tags
sub dbUserGet {
  my $s = shift;
  my %o = (
    page => 1,
    results => 10,
    what => '',
    sort => '',
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
    qw|id username c_votes c_changes c_tags|,
    q|extract('epoch' from registered) as registered|,
    $o{what} =~ /extended/ ? (
      qw|mail rank salt ign_votes|,
      q|encode(passwd, 'hex') AS passwd|
    ) : (),
    $o{what} =~ /hide_list/ ? 'up.value AS hide_list' : (),
    $o{what} =~ /notifycount/ ?
      '(SELECT COUNT(*) FROM notifications WHERE uid = u.id AND read IS NULL) AS notifycount' : (),
    $o{what} =~ /stats/ ? (
      '(SELECT COUNT(*) FROM rlists WHERE uid = u.id) AS releasecount',
      '(SELECT COUNT(*) FROM vnlists WHERE uid = u.id) AS vncount',
      '(SELECT COUNT(*) FROM threads_posts WHERE uid = u.id) AS postcount',
      '(SELECT COUNT(*) FROM threads_posts WHERE uid = u.id AND num = 1) AS threadcount',
      '(SELECT COUNT(DISTINCT tag) FROM tags_vn WHERE uid = u.id) AS tagcount',
      '(SELECT COUNT(DISTINCT vid) FROM tags_vn WHERE uid = u.id) AS tagvncount',
    ) : (),
    $o{session} ? q|extract('epoch' from s.lastused) as session_lastused| : (),
  );

  my @join = (
    $o{session} ? 'JOIN sessions s ON s.uid = u.id' : (),
    $o{what} =~ /hide_list/ || $o{sort} eq 'votes' ?
      "LEFT JOIN users_prefs up ON up.uid = u.id AND up.key = 'hide_list'" : (),
  );

  my $order = sprintf {
    username => 'u.username %s',
    registered => 'u.registered %s',
    votes => 'up.value NULLS FIRST, u.c_votes %s',
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

  if(@$r && $o{what} =~ /prefs/) {
    my %r = map {
      $r->[$_]{prefs} = {};
      ($r->[$_]{id}, $r->[$_])
    } 0..$#$r;

    $r{$_->{uid}}{prefs}{$_->{key}} = $_->{value} for (@{$s->dbAll(q|
      SELECT uid, key, value
        FROM users_prefs
        WHERE uid IN(!l)|,
      [ keys %r ]
    )});
  }
  return wantarray ? ($r, $np) : $r;
}


# uid, %options->{ columns in users table }
sub dbUserEdit {
  my($s, $uid, %o) = @_;

  my %h;
  defined $o{$_} && ($h{$_.' = ?'} = $o{$_})
    for (qw| username mail rank salt ign_votes |);
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
  $_[0]->dbExec(q|DELETE FROM users WHERE id = ?|, $_[1]);
}


# uid, key, val
sub dbUserPrefSet {
  my($s, $uid, $key, $val) = @_;
  !$val ? $s->dbExec('DELETE FROM users_prefs WHERE uid = ? AND key = ?', $uid, $key)
   : $s->dbExec('UPDATE users_prefs SET value = ? WHERE uid = ? AND key = ?', $val, $uid, $key)
  || $s->dbExec('INSERT INTO users_prefs (uid, key, value) VALUES (?, ?, ?)', $uid, $key, $val);
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


# %options->{ uid id what results page reverse }
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
      ORDER BY n.id !s
  |, join(', ', @select), join(' ', @join), \%where, $o{reverse} ? 'DESC' : 'ASC');
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

