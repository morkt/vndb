




#                               N E E D S   M O A R   S A L T !


package VNDB::Util::Auth;

use strict;
use warnings;
use Exporter 'import';
use Digest::MD5 'md5_hex';
use Crypt::Lite; # simple, small and easy encryption for cookies

use vars ('$VERSION', '@EXPORT');
$VERSION = $VNDB::VERSION;
@EXPORT = qw| AuthCheckCookie AuthLogin AuthLogout AuthInfo AuthCan AuthAddTpl |;


{ # local data for these 2 methods only
  my $crl = Crypt::Lite->new(debug => 0);
  my $scrt = md5_hex("73jkS39Sal2)"); # just a random string, as long as it doesn't change
  
sub AuthCheckCookie {
  my $self = shift;
  my $info = $self->{_Req} || $self;
  $info->{_auth} = {} if !exists $info->{_auth};

  my $cookie = $self->ReqCookie('vndb_auth');
  return 0 if !$cookie;
  my $str = $crl->decrypt($cookie, $scrt);
  return 0 if length($str) < 36;
  my $pass = substr($str, 4, 32);
  my $user = substr($str, 36);
  return _AuthCheck($self, $user, $pass);
}
 
sub AuthLogin {
  my $self = shift;
  my $user = lc(scalar shift);
  my $psbk = shift;
  my $pass = md5_hex($psbk);
  my $keep = shift;
  my $to = shift;
  my $status = _AuthCheck($self, $user, $pass);
  if($status == 1) {
    (my $cookie = $crl->encrypt("VNDB$pass$user", $scrt)) =~ s/\r?\n//g;
    $self->ResRedirect($to, "post");
    $self->ResAddHeader('Set-Cookie', "vndb_auth=$cookie; " . ($keep ? 'expires=Sat, 01-Jan-2030 00:00:00 GMT; ' : ' ') . "path=/; domain=$self->{CookieDomain}");
    return 1;
  }
  return $status;
}
} # end of local data

sub AuthLogout {
  my $self = shift;
  $self->ResRedirect('/', 'temp');
  $self->ResAddHeader('Set-Cookie', "vndb_auth= ; expires=Sat, 01-Jan-2000 00:00:00 GMT; path=/; domain=$self->{CookieDomain}");
}

sub AuthInfo {
  my $self = shift;
  my $info = $self->{_Req} || shift;
  return $info->{_auth} || {};
}

sub AuthCan {
  my $self = shift;
  my $act = shift;
  my $info = $self->{_Req} || shift;
  return $self->{ranks}[($info->{_auth}{rank}||0)+1]{$act};
}

sub _AuthCheck {
  my $self = shift;
  my $user = shift;
  my $pass = shift;
  my $info = $self->{_Req} || shift;

  $info->{_auth} = undef;

  return 2 if !$user || length($user) > 15 || length($user) < 2;
  return 3 if !$pass || length($pass) != 32;

  my $d = $self->DBGetUser(username => $user, passwd => $pass)->[0];
  return 4 if !defined $d->{id};
  return 5 if !$d->{rank};

  $info->{_auth} = $d;

  return 1;
}


# adds the keys AuthLoggedin, AuthRank, AuthUsername, AuthMail, AuthId
sub AuthAddTpl {
  my $self = shift;
  my $info = $self->{_Req} || shift;
  my %tpl;
  
  if($info->{_auth}{id}) {
    %tpl = (
      AuthLoggedin => 1,
      AuthRank => $info->{_auth}{rank},
      AuthRankname => $self->{ranks}[0][0][$info->{_auth}{rank}],
      AuthUsername => $info->{_auth}{username},
      AuthMail => $info->{_auth}{mail},
      AuthId => $info->{_auth}{id},
      AuthNsfw => $info->{_auth}{flags} & $VNDB::UFLAGS->{nsfw},
    );
  } else {
    %tpl = (
      AuthLoggedin => 0,
      AuthRank => '',
      AuthRankname => '',
      AuthUsername => '',
      AuthMail => '',
      AuthId => 0,
      AuthNsfw => 0,
    );
  }
  $tpl{'Auth'.$_} = $self->{ranks}[($info->{_auth}{rank}||0)+1]{$_}
    for (keys %{$self->{ranks}[0][1]});
  $self->ResAddTpl(%tpl);
}

1;

