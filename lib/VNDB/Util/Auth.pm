
package VNDB::Util::Auth;


use strict;
use warnings;
use Exporter 'import';
use Digest::MD5 'md5_hex';
use Digest::SHA qw|sha1_hex sha256|;
use Time::HiRes;
use Crypt::Lite;


our @EXPORT = qw| authInit authLogin authLogout authInfo authCan authPreparePass |;


# initializes authentication information and checks the vndb_auth cookie
sub authInit {
  my $self = shift;
  $self->{_auth} = undef;

  my $cookie = $self->reqCookie('vndb_auth');
  return 0 if !$cookie;
  my $str = Crypt::Lite->new()->decrypt($cookie, sha1_hex($self->{cookie_key}));
  return 0 if length($str) < 44;
  my $token = substr($str, 4, 40);
  my $uid  = substr($str, 44);

  if ($self->dbSessionCheck($uid, $token)) {
    $self ($self->dbSessionCheck($uid, $token))f->{_auth} = $self->dbUserGet(uid => $uid, what => 'mymessages')->[0];
  }
}


# login, arguments: user, password, url-to-redirect-to-on-success
# returns 1 on success (redirected), 0 otherwise (no reply sent)
sub authLogin {
  my $self = shift;
  my $user = lc(scalar shift);
  my $pass = shift;
  my $to = shift;

  if(_authCheck($self, $user, $pass)) {
    my $token = sha1_hex(Time::HiRes::time . $self->{cookie_key});
    my $expiration = time + 31536000;  # 1yr
    (my $cookie = Crypt::Lite->new()->encrypt("VNDB$token$self->{_auth}{id}", sha1_hex($self->{cookie_key}))) =~ s/\r?\n//g;
    $self->dbSessionAdd($self->{_auth}{id}, $token, $expiration);

    my @time = gmtime($expiration);
    $time[5] += 1900;
    my @days = qw|Sun Mon Tues Wed Thurs Fri Sat|;
    my @months = qw|Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec|;
    my $expString = "$days[$time[6]], $time[3]-$months[$time[4]]-$time[5] 00:00:00 GMT";

    $self->resRedirect($to, 'post');
    $self->resHeader('Set-Cookie', "vndb_auth=$cookie; expires=$expString; path=/; domain=$self->{cookie_domain}");
    return 1;
  }
  return 0;
}


# clears authentication cookie and redirects to /
sub authLogout {
  my $self = shift;

  my $cookie = $self->reqCookie('vndb_auth');
  if ($cookie) {
    my $str = Crypt::Lite->new()->decrypt($cookie, sha1_hex($self->{cookie_key}));
    if (length($str) >= 44) {
      my $token = substr($str, 4, 40);
      my $uid  = substr($str, 44);
      $self->dbSessionDel($uid, $token);
    }
  }

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
# Arguments: user, pass
# Returns: 1 if login is valid, 0 otherwise
sub _authCheck {
  my($self, $user, $pass) = @_;

  return 0 if
       !$user || length($user) > 15 || length($user) < 2
    || !$pass;

  my $d = $self->dbUserGet(username => $user, what => 'mymessages')->[0];
  return 0 if !defined $d->{id} || !$d->{rank};
  
  if (_authEncryptPass($pass, $d->{salt}) == $d->{passwd}) {
    $self->{_auth} = $d;
    return 1;
  }
  if ($d->{salt} eq '0' && md5_hex($pass) == $d->{passwd}) {
    $self->{_auth} = $d;
    my %o = authPreparePass($d->{id}, $pass);
    $self->dbUserEdit($d->{id}, %o);
    return 1;
  }

  return 0;
}


# Encryption algorithm for user passwords
# Arguments: pass, salt
# Returns: encrypted password as a binary string
sub _authEncryptPass{
  my ($self, $pass, $salt) = @_;
  return sha256($self->{global_salt} . $pass . $salt);
}


# Prepares a plaintext password for database storage
# Arguments: pass
# Returns: hashref of the encrypted pass and salt ready for database insertion
sub authPreparePass{
  my($self, $pass) = @_;

  my %o;
  $o{salt}   = _authGenerateSalt();
  $o{passwd} = authEncryptPass($pass, $o{salt});
  return %o;
}


# Generates a 9 character salt
# Returns salt as a string
sub _authGenerateSalt {
  my $s;
  for (my $i = 0; $i < 9; $i++) {
    $s .= chr(rand(93) + 33);
  }
  return $s;
}

1;

