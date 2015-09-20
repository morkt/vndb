
package VNDB::Util::Auth;


use strict;
use warnings;
use Exporter 'import';
use Digest::SHA qw|sha1 sha1_hex sha256|;
use Crypt::URandom 'urandom';
use Crypt::ScryptKDF 'scrypt_raw';
use Encode 'encode_utf8';
use TUWF ':html';
use VNDB::Func;


our @EXPORT = qw|
  authInit authLogin authLogout authInfo authCan authPreparePass
  authPrepareReset authValidateReset authGetCode authCheckCode authPref
|;


sub randomascii {
  return join '', map chr($_%92+33), unpack 'C*', urandom shift;
}


# Fetches and parses the auth cookie.
# Returns (uid, encrypted_token) on success, (0, '') on failure.
sub parsecookie {
  # Earlier versions of the auth cookie didn't have the dot separator, so that's optional.
  return ($_[0]->reqCookie('auth')||'') =~ /^([a-zA-Z0-9]{40})\.?(\d+)$/ ? ($2, sha1 pack 'H*', $1) : (0, '');
}


# initializes authentication information and checks the vndb_auth cookie
sub authInit {
  my $self = shift;

  my($uid, $token_e) = parsecookie($self);
  $self->{_auth} = $uid && $self->dbUserGet(uid => $uid, session => $token_e, what => 'extended notifycount prefs')->[0];

  # update the sessions.lastused column if lastused < now()-'6 hours'
  $self->dbSessionUpdateLastUsed($uid, $token_e) if $self->{_auth} && $self->{_auth}{session_lastused} < time()-6*3600;

  # Drop the cookie if it's not valid
  $self->resCookie(auth => undef) if !$self->{_auth} && $self->reqCookie('auth');
}


# login, arguments: user, password, url-to-redirect-to-on-success
# returns 1 on success (redirected), 0 otherwise (no reply sent)
sub authLogin {
  my $self = shift;
  my $user = lc(scalar shift);
  my $pass = shift;
  my $to = shift;

  if(_authCheck($self, $user, $pass)) {
    my $token = urandom(20);
    my $cookie = unpack('H*', $token).'.'.$self->{_auth}{id};
    $self->dbSessionAdd($self->{_auth}{id}, sha1 $token);

    $self->resRedirect($to, 'post');
    $self->resCookie(auth => $cookie, httponly => 1, expires => time + 31536000); # keep the cookie for 1 year
    return 1;
  }

  return 0;
}


# clears authentication cookie and redirects to /
sub authLogout {
  my $self = shift;

  my($uid, $token_e) = parsecookie($self);
  $self->dbSessionDel($uid, $token_e) if $uid;

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
  return $self->{_auth} ? $self->{_auth}{perm} & $self->{permissions}{$act} : 0;
}


# Checks for a valid login and writes information in _auth
# Arguments: user, pass
# Returns: 1 if login is valid, 0 otherwise
sub _authCheck {
  my($self, $user, $pass) = @_;

  return 0 if !$user || length($user) > 15 || length($user) < 2 || !$pass;

  my $d = $self->dbUserGet(username => $user, what => 'extended notifycount')->[0];
  return 0 if !$d->{id};

  # Old-style hashes
  if(length $d->{passwd} == 41) {
    return 0 if _authPreparePassSha256($self, $pass, substr $d->{passwd}, 0, 9) ne $d->{passwd};
    $self->{_auth} = $d;
    # Update database with new hash format, now that we have the plain text password
    $self->dbUserEdit($d->{id}, passwd => $self->authPreparePass($pass));
    return 1;
  }

  # New scrypt hashes
  if(length $d->{passwd} == 46) {
    my($N, $r, $p, $salt) = unpack 'NCCa8', $d->{passwd};
    return 0 if $self->authPreparePass($pass, $salt, $N, $r, $p) ne $d->{passwd};
    $self->{_auth} = $d;
    return 1;
  }

  return 0;
}


# Prepares a plaintext password for database storage
# Arguments: pass, optionally: salt, N, r, p
# Returns: encrypted password (as a binary string)
sub authPreparePass {
  my($self, $pass, $salt, $N, $r, $p) = @_;
  ($N, $r, $p) = @{$self->{scrypt_args}} if !$N;
  $salt ||= urandom(8);
  return pack 'NCCa8a*', $N, $r, $p, $salt, scrypt_raw($pass, $self->{scrypt_salt} . $salt, $N, $r, $p, 32);
}


# Same as authPreparePass, but for the old sha256 hash.
# Arguments: pass, optionally salt
# Returns: encrypted password (as a binary string)
sub _authPreparePassSha256 {
  my($self, $pass, $salt) = @_;
  $salt ||= encode_utf8(randomascii(9));
  return $salt.sha256($self->{global_salt} . encode_utf8($pass) . $salt);
}


# Generates a random token that can be used to reset the password.
# Returns: token (hex string), token-encrypted (binary string)
sub authPrepareReset {
  my $self = shift;
  my $token = unpack 'H*', urandom(20);
  my $salt = randomascii(9);
  my $token_e = encode_utf8($salt) . sha1(lc($token).$salt);
  return ($token, $token_e);
}


# Checks whether the password reset token is valid.
# Arguments: passwd (binary string), token (hex string)
sub authValidateReset {
  my($self, $passwd, $token) = @_;
  return 0 if length $passwd != 29;
  my $salt = substr $passwd, 0, 9;
  return 0 if $salt.sha1(lc($token).$salt) ne $passwd;
  return 1;
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
  my $uid = encode_utf8($self->{_auth} ? $self->{_auth}{id} : norm_ip($self->reqIP()));
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
  my $id = shift || $self->reqPath();
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

