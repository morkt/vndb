
package VNDB::Util::Request;

use strict;
use warnings;
use Encode;
use Exporter 'import';

our @EXPORT;
@EXPORT = qw| ReqParam ReqSaveUpload ReqCookie
  ReqMethod ReqHeader ReqUri ReqIP |;

sub new {
  return bless {}, ref($_[0]) || $_[0];              
}
sub ReqParam {
  my($s,$n) = @_;
  return wantarray
    ? map { decode 'UTF-8', defined $_ ? $_ : '' } $FCGI::Handler::c->param($n)
    : decode 'UTF-8', defined $FCGI::Handler::c->param($n) ? $FCGI::Handler::c->param($n) : '';
}
sub ReqSaveUpload {
  my($s,$n,$f) = @_;
  open my $F, '>', $f or die "Unable to write to $f: $!";
  print $F $FCGI::Handler::c->param($n);
  close $F;
}
sub ReqCookie {
  my $c = Cookie::XS->fetch;
  return $c && ref($c) eq 'HASH' && $c->{$_[1]} ? $c->{$_[1]}[0] : '';
}
sub ReqMethod {
  return ($ENV{REQUEST_METHOD}||'') =~ /post/i ? 'POST' : 'GET';
}
sub ReqHeader {
  (my $v = uc $_[1]) =~ tr/-/_/;
  return $ENV{"HTTP_$v"}||'';
}
sub ReqUri {
  return $ENV{REQUEST_URI};
}
sub ReqIP {
  return $ENV{REMOTE_ADDR};
}

1;
