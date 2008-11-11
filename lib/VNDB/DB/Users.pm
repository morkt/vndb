
package VNDB::DB::Users;

use strict;
use warnings;
use Exporter 'import';

our @EXPORT = qw|dbUserGet dbUserEdit dbUserAdd dbUserDel|;


# %options->{ username passwd mail order uid results page }
sub dbUserGet { 
  my $s = shift;
  my %o = (
    order => 'username ASC',
    page => 1,
    results => 10,
    what => '',
    @_
  );

  my %where = (
    $o{username} ? (
      'username = ?' => $o{username} ) : (),
    $o{passwd} ? (
      'passwd = decode(?, \'hex\')' => $o{passwd} ) : (),
    $o{mail} ? (
      'mail = ?' => $o{mail} ) : (),
    $o{uid} ? (
      'id = ?' => $o{uid} ) : (),
    !$o{uid} && !$o{username} ? (
      'id > 0' => 1 ) : (),
  );

  my($r, $np) = $s->dbPage(\%o, q|
    SELECT *
      FROM users u
      !W
      ORDER BY !s|,
    \%where,
    $o{order}
  );

  return wantarray ? ($r, $np) : $r;
}


# uid, %options->{ columns in users table }
sub dbUserEdit { 
  my($s, $uid, %o) = @_;

  my %h;
  defined $o{$_} && ($h{$_.' = ?'} = $o{$_})
    for (qw| username mail rank flags |);
  $h{'passwd = decode(?, \'hex\')'} = $o{passwd}
    if defined $o{passwd};

  return if scalar keys %h <= 0;
  return $s->dbExec(q|
    UPDATE users
    !H
    WHERE id = ?|,
  \%h, $uid);
}


# username, md5(pass), mail
sub dbUserAdd {
  my($s, @o) = @_;
  $s->dbExec(q|INSERT INTO users (username, passwd, mail) VALUES(?, decode(?, 'hex'), ?)|, @o);
}


# uid
sub dbUserDel {
  my($s, $id) = @_;
  $s->dbExec($_, $id) for (
    q|DELETE FROM vnlists WHERE uid = ?|,
    q|DELETE FROM rlists WHERE uid = ?|,
    q|DELETE FROM wlists WHERE uid = ?|,
    q|DELETE FROM votes WHERE uid = ?|,
    q|UPDATE changes SET requester = 0 WHERE requester = ?|,
    q|UPDATE threads_posts SET uid = 0 WHERE uid = ?|,
    q|DELETE FROM users WHERE id = ?|
  );
}


1;
