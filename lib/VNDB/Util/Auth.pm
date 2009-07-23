
package VNDB::Util::Auth;

# This module is just a small improvement of the 1.x equivalent
# and is designed to work with the cookies and database of VNDB 1.x
# without modifications. A proper and more secure (incompatible)
# implementation should be written at some point.

use strict;
use warnings;
use Exporter 'import';
use Digest::MD5 'md5_hex';
use Digest::SHA;
use Crypt::Lite;


our @EXPORT = qw| authInit authLogin authLogout authInfo authCan |;


# initializes authentication information and checks the vndb_auth cookie
sub authInit {
  my $self = shift;
  $self->{_auth} = undef;

  my $cookie = $self->reqCookie('vndb_auth');
  return 0 if !$cookie;
  my $str = Crypt::Lite->new()->decrypt($cookie, md5_hex($self->{cookie_key}));
  return 0 if length($str) < 36;
  my $pass = substr($str, 4, 32);
  my $user = substr($str, 36);
  _authCheck($self, $user, $pass);
}


# login, arguments: user, password, url-to-redirect-to-on-success
# returns 1 on success (redirected), 0 otherwise (no reply sent)
sub authLogin {
  my $self = shift;
  my $user = lc(scalar shift);
  my $pass = md5_hex(shift);
  my $to = shift;

  if(_authCheck($self, $user, $pass)) {
    (my $cookie = Crypt::Lite->new()->encrypt("VNDB$pass$user", md5_hex($self->{cookie_key}))) =~ s/\r?\n//g;
    $self->resRedirect($to, 'post');
    $self->resHeader('Set-Cookie', "vndb_auth=$cookie; expires=Sat, 01-Jan-2030 00:00:00 GMT; path=/; domain=$self->{cookie_domain}");
    return 1;
  }
  return 0;
}


# clears authentication cookie and redirects to /
sub authLogout {
  my $self = shift;
  $self->resRedirect('/', 'temp');
  $self->resHeader('Set-Cookie', "vndb_auth= ; expires=Sat, 01-Jan-2000 00:00:00 GMT; path=/; domain=$self->{cookie_domain}");
}


# returns a hashref with information about the current loggedin user
# the hash is identical to the hash returned by dbUserGet
# returns empty hash if no user is logged in.
sub authInfo {
  return shift->{_auth} || {};
}


# returns whether the currently loggedin or anonymous user can perform
# a certain action. Argument is the action name as defined in global.pl
sub authCan {
  my($self, $act) = @_;
  my $r = $self->{_auth}{rank}||0;
  return scalar grep $_ eq $act, @{$self->{user_ranks}[$r]}[1..$#{$self->{user_ranks}[$r]}];
}


# Checks for a valid login and writes information in _auth
# Arguments: user, md5_hex(pass)
# Returns: 1 if login is valid, 0 otherwise
sub _authCheck {
  my($self, $user, $pass) = @_;

  return 0 if
       !$user || length($user) > 15 || length($user) < 2
    || !$pass || length($pass) != 32;

  my $d = $self->dbUserGet(username => $user, passwd => $pass, what => 'mymessages')->[0];
  return 0 if !defined $d->{id} || !$d->{rank};

  $self->{_auth} = $d;
  return 1;
}


# Generates a 9 character salt
# Returns salt as a string
sub _generateSalt {
  my $s;
  for ($i = 0; $i < 9; $i++) {
    $s .= chr(rand(93) + 33);
  }
  return $s;
}

1;

