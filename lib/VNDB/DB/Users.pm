
package VNDB::DB::Users;

use strict;
use warnings;
use Exporter 'import';

our @EXPORT = qw|dbUserGet dbUserEdit dbUserAdd dbUserDel dbSessionAdd dbSessionDel dbSessionCheck|;


# %options->{ username passwd mail order uid ip registered search results page what }
# what: stats mymessages
sub dbUserGet {
  my $s = shift;
  my %o = (
    order => 'username ASC',
    page => 1,
    results => 10,
    what => '',
    @_
  );

  $o{search} =~ s/%// if $o{search};
  my %where = (
    $o{username} ? (
      'username = ?' => $o{username} ) : (),
    $o{passwd} ? (
      'passwd = decode(?, \'hex\')' => $o{passwd} ) : (),
    $o{firstchar} ? (
      'SUBSTRING(username from 1 for 1) = ?' => $o{firstchar} ) : (),
    !$o{firstchar} && defined $o{firstchar} ? (
      'ASCII(username) < 97 OR ASCII(username) > 122' => 1 ) : (),
    $o{mail} ? (
      'mail = ?' => $o{mail} ) : (),
    $o{uid} ? (
      'id = ?' => $o{uid} ) : (),
    !$o{uid} && !$o{username} ? (
      'id > 0' => 1 ) : (),
    $o{ip} ? (
      'ip = ?' => $o{ip} ) : (),
    $o{registered} ? (
      'registered > ?' => $o{registered} ) : (),
    $o{search} ? (
      'username ILIKE ?' => "%$o{search}%") : (),
  );

  my @select = (
    'u.*',
    $o{what} =~ /stats/ ? (
      '(SELECT COUNT(*) FROM rlists WHERE uid = u.id) AS releasecount',
      '(SELECT COUNT(DISTINCT rv.vid) FROM rlists rl JOIN releases r ON rl.rid = r.id JOIN releases_vn rv ON rv.rid = r.latest WHERE uid = u.id) AS vncount',
      '(SELECT COUNT(*) FROM threads_posts WHERE uid = u.id) AS postcount',
      '(SELECT COUNT(*) FROM threads_posts WHERE uid = u.id AND num = 1) AS threadcount',
      '(SELECT COUNT(DISTINCT tag) FROM tags_vn WHERE uid = u.id) AS tagcount',
      '(SELECT COUNT(DISTINCT vid) FROM tags_vn WHERE uid = u.id) AS tagvncount',
    ) : (),
    $o{what} =~ /mymessages/ ?
      '(SELECT COUNT(*) FROM threads_boards tb JOIN threads t ON t.id = tb.tid WHERE tb.type = \'u\' AND tb.iid = u.id AND t.hidden = FALSE) AS mymessages' : (),
  );

  my($r, $np) = $s->dbPage(\%o, q|
    SELECT !s
      FROM users u
      !W
      ORDER BY !s|,
    join(', ', @select), \%where, $o{order}
  );
  return wantarray ? ($r, $np) : $r;
}


# uid, %options->{ columns in users table }
sub dbUserEdit {
  my($s, $uid, %o) = @_;

  my %h;
  defined $o{$_} && ($h{$_.' = ?'} = $o{$_})
    for (qw| username mail rank show_nsfw show_list skin customcss salt |);
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
  $s->dbExec(q|INSERT INTO users (username, passwd, salt, mail, ip, registered) VALUES(?, decode(?, 'hex'), ?, ?, ?, ?)|,
    @o[0..3], $o[4]||$s->reqIP, time);
}


# uid
sub dbUserDel {
  my($s, $id) = @_;
  $s->dbExec($_, $id) for (
    q|DELETE FROM vnlists WHERE uid = ?|,
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
# If no expiration is supplied the database default is used
# uid, 40 character session token, expiration time (timestamp)
sub dbSessionAdd {
  my($s, @o) = @_;
  if (defined $o[2]) {
    $s->dbExec(q|INSERT INTO sessions (uid, token, expiration) VALUES(?, ?, ?)|,
      @o);
  } else {
    $s->dbExec(q|INSERT INTO sessions (uid, token) VALUES(?, ?)|,
      @o);
  }
}


# Deletes session(s) from the database
# If no token is supplied, all sessions for the uid are destroyed
# uid, token (optional)
sub dbSessionDel {
  my($s, @o) = @_;
  if (defined $o[1]) {
    $s->dbExec(q|DELETE FROM sessions WHERE uid = ? AND token = ?|,
      @o[0..1]);
  } else {
    $s->dbExec(q|DELETE FROM sessions WHERE uid = ?|,
      $o[0]);
  }
}


# Queries the database for the validity of a session
# Returns 1 if corresponding session found, 0 if not
# uid, token
sub dbSessionCheck {
  my($s, @o) = @_;
  return $s->dbRow(q|SELECT count(uid) AS count FROM sessions WHERE uid = ? AND token = ? LIMIT 1|, @o)->{count}||0;
}


1;
