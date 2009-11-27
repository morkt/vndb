
package VNDB::Util::Auth;


use strict;
use warnings;
use Exporter 'import';
use Digest::MD5 'md5_hex';
use Digest::SHA qw|sha1_hex sha256_hex|;
use Time::HiRes;
use Encode 'encode_utf8';
use POSIX 'strftime';


our @EXPORT = qw| authInit authLogin authLogout authInfo authCan authPreparePass |;


# initializes authentication information and checks the vndb_auth cookie
sub authInit {
  my $self = shift;
  $self->{_auth} = undef;

  my $cookie = $self->reqCookie('vndb_auth');
  return 0 if !$cookie;
  return _rmcookie($self) if length($cookie) < 41;
  my $token = substr($cookie, 0, 40);
  my $uid  = substr($cookie, 40);
  $self->{_auth} = $uid =~ /^\d+$/ && $self->dbUserGet(uid => $uid, session => $token, what => 'extended')->[0];
  return _rmcookie($self) if !$self->{_auth};
}


# login, arguments: user, password, url-to-redirect-to-on-success
# returns 1 on success (redirected), 0 otherwise (no reply sent)
sub authLogin {
  my $self = shift;
  my $user = lc(scalar shift);
  my $pass = shift;
  my $to = shift;

  if(_authCheck($self, $user, $pass)) {
    my $token = sha1_hex(join('', Time::HiRes::gettimeofday()) . join('', map chr(rand(93)+33), 1..9));
    my $expiration = time + 31536000;  # 1yr
    my $cookie = $token . $self->{_auth}{id};
    $self->dbSessionAdd($self->{_auth}{id}, $token, $expiration);

    my $expstr = strftime("%a, %d %b %Y %H:%M:%S GMT", gmtime($expiration));
    $self->resRedirect($to, 'post');
    $self->resHeader('Set-Cookie', "vndb_auth=$cookie; expires=$expstr; path=/; domain=$self->{cookie_domain}");
    return 1;
  }

  return 0;
}


# clears authentication cookie and redirects to /
sub authLogout {
  my $self = shift;

  my $cookie = $self->reqCookie('vndb_auth');
  if ($cookie && length($cookie) >= 41) {
    my $token = substr($cookie, 0, 40);
    my $uid  = substr($cookie, 40);
    $self->dbSessionDel($uid, $token);
  }

  $self->resRedirect('/', 'temp');
  _rmcookie($self);
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
  my $r = $self->{_auth} ? $self->{_auth}{rank} : 0;
  return scalar grep $_ eq $act, @{$self->{user_ranks}[$r]}[0..$#{$self->{user_ranks}[$r]}];
}


# Checks for a valid login and writes information in _auth
# Arguments: user, pass
# Returns: 1 if login is valid, 0 otherwise
sub _authCheck {
  my($self, $user, $pass) = @_;

  return 0 if !$user || length($user) > 15 || length($user) < 2 || !$pass;

  my $d = $self->dbUserGet(username => $user, what => 'extended')->[0];
  return 0 if !defined $d->{id} || !$d->{rank};

  if(_authEncryptPass($self, $pass, $d->{salt}) eq $d->{passwd}) {
    $self->{_auth} = $d;
    return 1;
  }
  if(md5_hex($pass) eq $d->{passwd}) {
    $self->{_auth} = $d;
    my %o;
    ($o{passwd}, $o{salt}) = authPreparePass($self, $pass);
    $self->dbUserEdit($d->{id}, %o);
    return 1;
  }

  return 0;
}


# Encryption algorithm for user passwords
# Arguments: self, pass, salt
# Returns: encrypted password (in hex)
sub _authEncryptPass{
  my($self, $pass, $salt, $bin) = @_;
  return sha256_hex($self->{global_salt} . encode_utf8($pass) . encode_utf8($salt));
}


# Prepares a plaintext password for database storage
# Arguments: pass
# Returns: list (pass, salt)
sub authPreparePass{
  my($self, $pass) = @_;
  my $salt = join '', map chr(rand(93)+33), 1..9;
  my $hash = _authEncryptPass($self, $pass, $salt);
  return ($hash, $salt);
}


# removes the vndb_auth cookie
sub _rmcookie {
  $_[0]->resHeader('Set-Cookie',
    "vndb_auth= ; expires=Sat, 01-Jan-2000 00:00:00 GMT; path=/; domain=$_[0]->{cookie_domain}");
}


1;

