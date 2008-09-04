#!/usr/bin/perl

package FCGI::Handler;

use strict;
use warnings;
use lib '/www/vndb/lib';

use strict;
use warnings;
use FCGI;
use CGI::Minimal ();
use CGI::Cookie::XS;
use Time::HiRes;
use VNDB;

my $elog = "/www/err.log";

our $req = FCGI::Request();
our $c;
our $outputted = 0;

my $VNDB = VNDB->new(%VNDB::VNDBopts);

our @WRN;
$SIG{__WARN__} = sub { push @FCGI::Handler::WRN, @_; };

while($req->Accept() >= 0) {
 # lighty doesn't always split the query string from REQUEST_URI
  ($ENV{REQUEST_URI}, $ENV{QUERY_STRING}) = split /\?/, $ENV{REQUEST_URI}
    if ($ENV{REQUEST_URI}||'') =~ /\?/;

 # re-init CGI::Minimal (can die())
  eval {
    CGI::Minimal::reset_globals;
    CGI::Minimal::allow_hybrid_post_get(1);
    CGI::Minimal::max_read_size(5*1024*1024); # allow 5MB of POST data
    $c = CGI::Minimal->new();
  };
  if($@) {
    send500();
    $req->Finish();
    next;
  }

 # figure out some required variables
  my $o = $VNDB;
  my $start = [ Time::HiRes::gettimeofday ] if $o->{debug};

 # call appropriate functions in VNDB.pm
  my $e = eval {
    if($c->truncated) {
      send500();
      warn "Truncated post request!\n";
    } else {
      $o->DBCheck;
      $o->get_page; # automatically calls DBCommit on success
    }
    1;
  };

 # Error handling 
  if(@WRN && $e && !$@ && open(my $F, '>>', $elog)) {
    for (@WRN) {
      chomp;
      printf $F "[%s] %s: %s\n", scalar localtime(), $ENV{HTTP_HOST}.$ENV{REQUEST_URI}.'?'.$ENV{QUERY_STRING}, $_;
    }
    close $F;
  }
  if(!defined $e && $@ && open(my $F, '>>', $elog)) {
    printf $F "[%s] %s: FATAL ERROR!\n", scalar localtime(), $ENV{HTTP_HOST}.$ENV{REQUEST_URI}.'?'.$ENV{QUERY_STRING};
    print  $F " ENV-dump:\n";
    printf $F "  %s: %s\n", $_, $ENV{$_} for (sort keys %ENV);
    print  $F " PARAM-dump:\n";
    printf $F "  %s: %s\n", $_, $c->param($_) for (sort $c->param());
    my $err = $@; chomp($err);
    printf $F " ERROR:\n  %s\n", $err;
    if(@WRN) {
      print  $F " WARNINGS:\n";
      for (@WRN) {
        chomp;
        printf $F "  %s\n", $_;
      }
    }
    print $F "\n";
    close $F;
    eval { $o->DBRollBack; };
    send500() if !$outputted;
  }

 # Debug info
  if($o->{debug} && open(my $F, '>>', $elog)) {
    my($sqlt, $sqlc) = (0, 0);
    for (@{$o->{_DB}->{Queries}}) {
      if($_->[0]) {
        $sqlc++;
        $sqlt += $_->[1];
      }
    }
    my $time = Time::HiRes::tv_interval($start);
    my $tpl = $o->{_Res}->{_tpltime} ? $o->{_Res}->{_tpltime}/$time*100 : 0;
    my $gzip = 0;
    $gzip = 100 - $o->{_Res}->{_gzip}->[1]/$o->{_Res}->{_gzip}->[0]*100
      if($o->{_Res}->{_gzip} && ref($o->{_Res}->{_gzip}) eq 'ARRAY' && $o->{_Res}->{_gzip}->[0] > 0);
    printf $F "Took %3dms (SQL/TPL/perl: %4.1f%% %4.1f%% %4.1f%%) (GZIP: %4.1f%%) to parse %s\n",
      $time*1000, $sqlt/$time*100, $tpl, 100-($sqlt/$time*100)-$tpl, $gzip, $ENV{REQUEST_URI};   
    close $F;
  }
 
 # reset vars
  @WRN = ();
  $outputted = 0;
  undef $o->{_Res};
  undef $o->{_Req};

  $req->Finish();
}

sub send500 {
  print "Status: 500 Internal Server Error\n";
  print "Content-Type: text/html\n";
  print "X-Sendfile: /www/vndb/www/files/err.html\n\n";
}

