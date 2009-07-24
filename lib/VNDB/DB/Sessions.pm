
package VNDB::DB::Sessions;

use strict;
use warnings;
use Exporter 'import';

our @EXPORT = qw| dbSessionAdd dbSessionDel dbSessionCheck |;


# uid, 40 character session token, expiration time (int)
sub dbSessionAdd {
  my($s, @o) = @_;
  $s->dbExec(q|INSERT INTO sessions (uid, token, expiration) VALUES(?, ?, ?)|,
    @o[0..2]);
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
  return $s->dbRow(q|SELECT count(uid) AS count FROM sessions WHERE uid = ? AND token = ? LIMIT 1|, @o);
}


1;
