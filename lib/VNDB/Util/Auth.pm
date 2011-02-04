
package VNDB::Util::Auth;


use strict;
use warnings;
use Exporter 'import';
use Digest::MD5 'md5_hex';
use Digest::SHA qw|sha1_hex sha256_hex|;
use Time::HiRes;
use Encode 'encode_utf8';
use POSIX 'strftime';
use TUWF ':html';
use VNDB::Func;


our @EXPORT = qw| authInit authLogin authLogout authInfo authCan authPreparePass authGetCode authCheckCode authPref |;


# initializes authentication information and checks the vndb_auth cookie
sub authInit {
  my $self = shift;
  $self->{_auth} = undef;

  my $cookie = $self->reqCookie('auth');
  return 0 if !$cookie;
  return $self->resCookie(auth => undef) if length($cookie) < 41;
  my $token = substr($cookie, 0, 40);
  my $uid  = substr($cookie, 40);
  $self->{_auth} = $uid =~ /^\d+$/ && $self->dbUserGet(uid => $uid, session => $token, what => 'extended notifycount prefs')->[0];
  # update the sessions.lastused column if lastused < now()'6 hours'
  $self->dbSessionUpdateLastUsed($uid, $token) if $self->{_auth} && $self->{_auth}{session_lastused} < time()-6*3600;
  return $self->resCookie(auth => undef) if !$self->{_auth};
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
    my $cookie = $token . $self->{_auth}{id};
    $self->dbSessionAdd($self->{_auth}{id}, $token);

    $self->resRedirect($to, 'post');
    $self->resCookie(auth => $cookie, expires => time + 31536000); # keep the cookie for 1 year
    return 1;
  }

  return 0;
}


# clears authentication cookie and redirects to /
sub authLogout {
  my $self = shift;

  my $cookie = $self->reqCookie('auth');
  if ($cookie && length($cookie) >= 41) {
    my $token = substr($cookie, 0, 40);
    my $uid  = substr($cookie, 40);
    $self->dbSessionDel($uid, $token);
  }

  $self->resRedirect('/', 'temp');
  $self->resCookie(auth => undef);

  # set l10n cookie if the user has a preferred language set
  my $l10n = $self->authPref('l10n');
  $self->resCookie(l10n => $l10n, expires => time()+31536000) if $l10n; # keep 1 year
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

  my $d = $self->dbUserGet(username => $user, what => 'extended notifycount')->[0];
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


# Generate a code to be used later on to validate that the form was indeed
# submitted from our site and by the same user/visitor. Not limited to
# logged-in users.
# Arguments:
#   form-id (string, can be empty, but makes the validation stronger)
#   time (optional, time() to encode in the code)
sub authGetCode {
  my $self = shift;
  my $id = shift;
  my $time = (shift || time)/3600; # accuracy of an hour
  my $uid = pack('N', $self->{_auth} ? $self->{_auth}{id} : 0);
  return lc substr sha1_hex($self->{form_salt} . $uid . encode_utf8($id||'') . pack('N', int $time)), 0, 16;
}


# Validates the correctness of the returned code, creates an error page and
# returns false if it's invalid, returns true otherwise. Codes are valid for at
# least two and at most three hours.
# Arguments:
#   [ form-id, [ code ] ]
# If the code is not given, uses the 'formcode' form parameter instead. If
# form-id is not given, the path of the current requests is used.
sub authCheckCode {
  my $self = shift;
  my $id = shift || '/'.$self->reqPath();
  my $code = shift || $self->reqParam('formcode');
  return _incorrectcode($self) if !$code || $code !~ qr/^[0-9a-f]{16}$/;
  my $time = time;
  return 1 if $self->authGetCode($id, $time) eq $code;
  return 1 if $self->authGetCode($id, $time-3600) eq $code;
  return 1 if $self->authGetCode($id, $time-2*3600) eq $code;
  return _incorrectcode($self);
}


sub _incorrectcode {
  my $self = shift;
  $self->resInit;
  $self->htmlHeader(title => mt '_formcode_title', noindex => 1);

  div class => 'mainbox';
   h1 mt '_formcode_title';
   div class => 'warning';
    p mt '_formcode_msg';
   end;
  end;

  $self->htmlFooter;
  return 0;
}


sub authPref {
  my($self, $key, $val) = @_;
  my $nfo = $self->authInfo;
  return '' if !$nfo->{id};
  return $nfo->{prefs}{$key}||'' if @_ == 2;
  $nfo->{prefs}{$key} = $val;
  $self->dbUserPrefSet($nfo->{id}, $key, $val);
}

1;

