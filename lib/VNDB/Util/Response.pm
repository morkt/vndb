
package VNDB::Util::Response;


use strict;
use warnings;
use POSIX ();
use Encode;
use XML::Writer;
use Compress::Zlib;
use Exporter 'import';
require bytes;

use vars ('$VERSION', '@EXPORT');
$VERSION = $NTL::VERSION;
@EXPORT = qw| ResRedirect ResNotFound ResDenied ResFile
  ResForceBody ResSetContentType ResAddHeader ResAddTpl ResAddDefaultStuff
  ResStartXML ResGetXML ResGetBody ResGet ResGetCGI ResSetModPerl |;

sub new {
  my $self = shift;
  my $tplo = shift;
  my $type = ref($self) || $self;
  my $me = bless {
    headers => [ ],
    contenttype => 'text/html; charset=UTF-8',
    code => 200,
    tplo => $tplo,
    tpl => { },
    body => undef,
    xmlobj => undef,
    xmldata => undef,
    whattouse => 1,
  }, $type;
 
  return $me;
}


## Some ready-to-use methods
sub ResRedirect {
  my $self = shift;
  my $url = shift; # should start with '/', if no URL specified, use referer or '/'
  my $type = shift;
  my $info = $self->{_Res} || $self;
  
  if(!$url) {
    $url = "/";
    my $ref = $self->ReqHeader('Referer');
    ($url = $ref) =~ s/^$self->{root_url}// if $ref;
  }
  
  my $code = !$type ? 301 :
    $type eq 'temp' ? 307 :
    $type eq 'post' ? 303 : 301;
  $info->{body} = 'Redirecting...';
  $info->{code} = $code;
  $info->{headers} = [ 'Location', "$self->{root_url}$url" ];
  $info->{contenttype} = 'text/html; charset=UTF-8';
  $info->{whattouse} = 1;
}

sub ResNotFound {
  my $s = shift;
  my $i = $s->{_Res};
  $i->{code} = 404;
  $i->{whattouse} = 2;
  $i->{tpl} = {
    page => { error => {
      err => 'notfound'
    }},
  };
}

sub ResDenied {
  my $self = shift;
  $self->ResRedirect('/u/register?n=1', 'temp');
}

sub ResFile {
  my($s,$f,@h) = @_;
  my $i = $s->{_Res};
  $i->{whattouse} = 4;
  $i->{code} = 200;
  $i->{contenttype} = '';
  push @{$i->{headers}},
    'X-Sendfile' => $f,
    'Cache-Control' => sprintf('max-age=%d, public', 7*24*3600),
    @h;
}

## And some often-used methods
sub ResForceBody {
  my $self = shift;
  my $body = shift; 
  my $info = $self->{_Res} || $self;
  $info->{whattouse} = 1;
  $info->{body} = $body;
}

sub ResSetContentType {
  my $self = shift;
  my $ctype = shift;
  my $info = $self->{_Res} || $self;
  $info->{contenttype} = $ctype;
  return 1;
}

sub ResAddHeader {
  my $self = shift;
  die("Odd number in parameters, must be in key => value format!") unless ((@_ % 2) == 0);
  my $info = $self->{_Res} || $self;
  $info->{headers} = [ @{$info->{headers}}, @_ ];
  return 1;
}

sub ResAddTpl {
  my $self = shift;
  die("Odd number in parameters, must be in key=>value format") unless ((@_ % 2) == 0);
  my $info = $self->{_Res} || $self;
  $info->{tpl} = { page => { } } if !$info->{tpl}->{page};
  $info->{tpl}->{page} = { %{$info->{tpl}->{page}}, @_ };
  $info->{whattouse} = 2;
  return 1;  
}

sub ResStartXML {
  my $self = shift;
  my $info = $self->{_Res} || $self;
  $info->{xmldata} = undef;
  $info->{xmlobj} = XML::Writer->new(
    OUTPUT => \$info->{xmldata}, 
    NEWLINES => 0, 
    ENCODING => 'UTF-8', 
    DATA_MODE => 1, 
    DATA_INDENT => 2,
  );
  $info->{xmlobj}->xmlDecl();
  $info->{contenttype} = "text/xml; charset=UTF-8";
 # disable caching on XML content, IE < 7 has "some" bugs...
  $self->ResAddHeader('Cache-Control' => 'must-revalidate, post-check=0, pre-check=0',
                      'Pragma' => 'public');
  $info->{whattouse} = 3;
  return $info->{xmlobj};
}

## And of course some methods to get the information
sub ResGetXML {
  my $self = shift;
  my $info = $self->{_Res} || $self;
  return undef if !$info->{xmlobj} || !$info->{xmldata};
  $info->{xmlobj}->end();
  my $tmpvar = $info->{xmldata};
  undef $info->{xmldata};
  return $tmpvar;
}

sub ResGetBody {
  my $self = shift;
  my $info = $self->{_Res} || $self;
  my $whattouse = shift || $info->{whattouse};
  if($whattouse == 1)  { return $info->{body};  }
  if($whattouse == 2)  {
    $self->AddDefaultStuff() if exists $info->{tpl}->{page};
    my $start = [Time::HiRes::gettimeofday()] if $self->{debug} && $Time::HiRes::VERSION;
    my $output = $info->{tplo}->compile($info->{tpl});
    $info->{_tpltime} = Time::HiRes::tv_interval($start) if $self->{debug} && $Time::HiRes::VERSION;
    return $output;
  }
  if($whattouse == 3)  { return $self->ResGetXML; }
}

sub ResGet {
  my $self = shift;
  my $info = $self->{_Res} || $self;
  my $whattouse = shift || $info->{whattouse};

  return ($info->{code}, $info->{headers}, $info->{contenttype}, $self->ResGetBody($whattouse));
}


my %scodes = (
 # just a few useful codes
  200 => 'OK',
  301 => 'Moved Permanently',
  302 => 'Found',
  303 => 'See Other',
  304 => 'Not Modified',
  307 => 'Temporary Redirect',
  403 => 'Forbidden',
  404 => 'Not Found',
  500 => 'Internal Server Error'
);

# don't rename!
sub ResSetModPerl {
  my $s = shift;
  my $i = $s->{_Res};
  printf "Status: %d %s\r\n", $i->{code}, $scodes{$i->{code}};
  print  "X-Powered-By: Perl\r\n";
  printf "Content-Type: %s\r\n", $i->{contenttype} if $i->{contenttype};
  my $c=0;
  printf "%s: %s\r\n", $i->{headers}[$c++], $i->{headers}[$c++]
    while ($c<$#{$i->{headers}});

  my $b = $s->ResGetBody||'';
  if($b && $s->ReqHeader('Accept-Encoding') =~ /gzip/ && $i->{contenttype} =~ /^text/) {
    my $ol = bytes::length($b) if $s->{debug};
    $b = Compress::Zlib::memGzip(Encode::encode_utf8($b));
    $i->{_gzip} = [ $ol, bytes::length($b) ];
    print "Content-Encoding: gzip\n";
  }
  my $l = bytes::length($b);
  printf "Content-Length: %d\r\n", $l if $l;
  print  "\r\n";
  print  $b;
  $FCGI::Handler::outputted = 1;
}

1;
