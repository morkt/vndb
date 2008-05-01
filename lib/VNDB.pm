package VNDB;

use strict;
use warnings;

BEGIN { require 'global.pl'; }
our $DEBUG;
our %VNDBopts = (
  CookieDomain  => '.vndb.org',
  root_url      => $DEBUG ? 'http://beta.vndb.org' : 'http://vndb.org',
  static_url    => $DEBUG ? 'http://static.beta.vndb.org' : 'http://static.vndb.org',
  debug         => $DEBUG,
  tplopts       => {
    filename      => 'main',
    searchdir     => '/www/vndb/data/tpl',
    compiled      => '/www/vndb/data/tplcompiled.pm',
    namespace     => 'VNDB::Util::Template::tpl',
    pre_chomp     => 1,
    post_chomp    => 1,
    rm_newlines   => 0,
    deep_reload   => $DEBUG,
  },
  ranks => [
    [ [ qw| visitor loser user mod admin | ], [] ],
    {map{$_,1}qw| hist                                     |}, # 0 - visitor (not logged in)
    {map{$_,1}qw| hist                                     |}, # 1 - loser
    {map{$_,1}qw| hist edit                                |}, # 2 - user
    {map{$_,1}qw| hist edit mod lock                       |}, # 3 - mod
    {map{$_,1}qw| hist edit mod lock del userlist useredit |}, # 4 - admin
  ],
  imgpath => '/www/vndb/static/cv',
  mappath => '/www/vndb/data/rg',
  docpath => '/www/vndb/data/docs',
);
$VNDBopts{ranks}[0][1] = { (map{$_,1} map { keys %{$VNDBopts{ranks}[$_]} } 1..5) };

require Time::HiRes if $DEBUG;
require Data::Dumper if $DEBUG;
use VNDB::Util::Template;
use VNDB::Util::Request;
use VNDB::Util::Response;
use VNDB::Util::DB;
use VNDB::Util::Tools;
use VNDB::Util::Auth;
use VNDB::HomePages;
use VNDB::Producers;
use VNDB::Releases;
use VNDB::VNLists;
use VNDB::Users;
use VNDB::Votes;
use VNDB::VN;


my %VNDBuris = ( # wildcards: * -> (.+), + -> ([0-9]+)
  '/'           => sub { shift->HomePage },
  'd+'          => sub { shift->DocPage(shift) },
  nospam        => sub { shift->ResAddTpl(error => { err => 'formerr' }) },
  hist =>   {'*'=> sub { shift->History(undef, undef, $_[1]) } },
 # users
  u => {
    login       => sub { shift->UsrLogin },
    logout      => sub { shift->UsrLogout },
    register    => sub { shift->UsrReg },
    newpass     => sub { shift->UsrPass },
    list => {
      '/'       => sub { shift->UsrList },
      '*'       => sub { $_[3] =~ /^([a-z0]|all)$/ ? shift->UsrList($_[2]) : shift->ResNotFound },
    },
  },
  'u+' => {
    '/'         => sub { shift->UsrPage(shift) },
    votes       => sub { shift->VNVotes(shift) },
    edit        => sub { shift->UsrEdit(shift) },
    pending     => sub { shift->UsrPending(shift) },
    list        => sub { shift->VNMyList(shift) },
    hist => {'*'=> sub { shift->History('u', shift, $_[1]) } },
  },
 # visual novels
  v => {
    '/'         => sub { shift->VNBrowse },
    new         => sub { shift->VNEdit(0); },
    '*'         => sub { $_[2] =~ /^([a-z0]|all|search|cat)$/ ? shift->VNBrowse($_[1]) : shift->ResNotFound; },
  },
  'v+' => {
    '/'         => sub { shift->VNPage(shift) },
    stats       => sub { shift->VNPage(shift, shift) },
    rg          => sub { shift->VNPage(shift, shift) },
    edit        => sub { shift->VNEdit(shift) },
    del         => sub { shift->VNDel(shift)  },
    vote        => sub { shift->VNVote(shift) },
    list        => sub { shift->VNListMod(shift) },
    add         => sub { shift->REdit('v', shift) },
    lock        => sub { shift->VNLock(shift) },     
    hide        => sub { shift->VNHide(shift) },
    hist => {'*'=> sub { shift->History('v', shift, $_[1]) } },
  },
 # releases
  'r+' => {
    '/'         => sub { shift->RPage(shift) },
    edit        => sub { shift->REdit('r', shift) },
    lock        => sub { shift->RLock(shift) },
    del         => sub { shift->RDel(shift)  },
    hide        => sub { shift->RHide(shift) },
    hist => {'*'=> sub { shift->History('r', shift, $_[1]) } },
  },
 # producers
  p => {
    '/'         => sub { shift->PBrowse },
    add         => sub { shift->PEdit(0) },
    '*'         => sub { $_[2] =~ /^([a-z0]|all)$/ ? shift->PBrowse($_[1]) : shift->ResNotFound; }
  },
  'p+' => {
    '/'         => sub { shift->PPage(shift) },
    edit        => sub { shift->PEdit(shift) },
    del         => sub { shift->PDel(shift) },
    lock        => sub { shift->PLock(shift) },
    hide        => sub { shift->PHide(shift) },
    hist => {'*'=> sub { shift->History('p', shift, $_[1]) } },
  },
 # stuff (.xml extension to make sure they aren't counted as pageviews)
  xml => {
    'producers.xml'   => sub { shift->PXML },
    'vn.xml'          => sub { shift->VNXML },
  },
);


# provide redirects for old URIs
my %OLDuris = (
  faq           => sub { shift->ResRedirect('/d6', 'perm') },
  vn => {
    rss         => sub { shift->ResRedirect('/hist/rss?t=v&e=1', 'perm') },
    '*'         => sub { shift->ResRedirect('/v/'.$_[1], 'perm') },
  },
  'v+' => {
    votes       => sub { shift->ResRedirect('/v'.(shift).'/stats', 'perm') },
  },
  u => {
    '*' => {
      '*'       => sub {
        if($_[2] =~ /^_(login|logout|register|newpass|list)$/) {
          $_[3] eq '/' ? $_[0]->ResRedirect('/u/'.$1, 'perm') : $_[0]->ResRedirect('/u/'.$1.'/'.$_[3], 'perm');
        } else {
          my $id = $_[0]->DBGetUser(username => $_[2])->[0]{id};
          $id ? $_[0]->ResRedirect('/u'.$id.'/'.$_[3], 'perm') : $_[0]->ResNotFound;
        }
      },
    }
  }
);



sub new {
  my $self = shift;
  my $type = ref($self) || $self;
  my %args = @_;

  my $me = bless {
    %args,
    _DB => VNDB::Util::DB->new(@VNDB::DBLOGIN),
    _TPL => VNDB::Util::Template->new(%{$args{tplopts}}),
  }, $type;
  
  return $me;
}


sub get_page {
  my $self = shift;
  my $r = shift;

  $self->{_Req} = VNDB::Util::Request->new($r);
  $self->{_Res} = VNDB::Util::Response->new($self->{_TPL});

  $self->AuthCheckCookie();
  $self->checkuri();

  my $res = $self->ResSetModPerl($r);
  $self->DBCommit();

  return($self, $res);
}


sub checkuri {
  my $self = shift;
  (my $uri = lc($self->ReqUri)) =~ s/^\/+//;
  $uri =~ s/\?.*$//;
  return $self->ResRedirect("/$uri", 'perm') if $uri =~ s/\/+$//;
  $uri =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg; # ugly hack, but we only accept ASCII anyway
  return $self->ResNotFound() if $uri !~ /^[a-z0-9\-\._~\/]*$/; # rfc3986 section 2.3, "Unreserved Characters"
  my @uri;
  defined $_ and push(@uri, $_) for (split(/\/+/, $uri));
  my @ouri = @uri; # items in @uri can be modified by uri2page
  $self->uri2page(\%VNDBuris, \@uri, 0);
  $self->uri2page(\%OLDuris, \@ouri, 0) # provide redirects for old uris
    if $self->{_Res}->{code} == 404;
}


sub uri2page {
  my($s, $o, $u, $i) = @_;
  $u->[$i] = '/' if !defined $u->[$i];
  my $n = $o->{$u->[$i]} ? $u->[$i] : ((map { 
    if(/[\*\+]/) {
      my $t = "^$_\$";
      /\*/ ? ($t =~ s/\*/(.+)/) : ($t =~ s/\+/([1-9][0-9]*)/);
      $u->[$i] =~ /$t/ ? ($u->[$i] = $1) && $_ : ();
    } else { () } }
    sort { length($b) <=> length($a) } keys %$o)[0] || '*');
  ref($o->{$n}) eq 'HASH' && $n ne '/' ?
    $s->uri2page($o->{$n}, $u, ++$i) :
    ref($o->{$n}) eq 'CODE' && $i == $#$u ?
    &{$o->{$n}}($s, @$u) :
    $s->ResNotFound();
}


1;


__END__

#   O L D   C O D E   -   N O T   U S E D   A N Y M O R E


# Apache 2 handler
sub handler ($$) {
  my $r = shift;

 # we don't handle internal redirects! (fixes ErrorDocument directives)
  return Apache2::Const::DECLINED
    if $r->prev || $r->next;

  my $start = [Time::HiRes::gettimeofday()] if $DEBUG;
  @WARN = ();
  my($code, $res, $err);
  $SIG{__WARN__} = sub { push(@VNDB::WARN, @_); warn @_; };
  
  $err = eval {

    @Time::CTime::DoW = qw|Sun Mon Tue Wed Thu Fri Sat|;
    @Time::CTime::DayOfWeek = qw|Sunday Monday Tuesday Wednesday Thursday Friday Saturday|;
    @Time::CTime::MoY = qw|Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec|;
    @Time::CTime::MonthOfYear = qw|January February March April May June July August September October November December|;

    $VNDB = VNDB->new(%VNDBopts) if !$VNDB;
    $VNDB->{r} = $r;

   # let apache handle static files
    (my $uri = lc($r->uri())) =~ s/\/+//;
    if(index($uri, '..') == -1 && -f '/www/vndb/www/' . $uri) {
      $code = Apache2::Const::DECLINED;
      return $code;
    }

    $VNDB->DBCheck();
    ($res, $code) = $VNDB->get_page($r);
    if($DEBUG) {
      my($sqlt, $sqlc) = (0, 0);
      foreach (@{$res->{_DB}->{Queries}}) {
        if($_->[0]) {
          $sqlc++;
          $sqlt += $_->[1];
        }
      }
      my $time = Time::HiRes::tv_interval($start);
      my $tpl = $res->{_Res}->{_tpltime} ? $res->{_Res}->{_tpltime}/$time*100 : 0;
      my $gzip = 0;
      $gzip = 100 - $res->{_Res}->{_gzip}->[1]/$res->{_Res}->{_gzip}->[0]*100
        if($res->{_Res}->{_gzip} && ref($res->{_Res}->{_gzip}) eq 'ARRAY' && $res->{_Res}->{_gzip}->[0] > 0);
      printf STDERR "Took %3dms (SQL/TPL/perl: %4.1f%% %4.1f%% %4.1f%%) (GZIP: %4.1f%%) to parse %s\n",
        $time*1000, $sqlt/$time*100, $tpl, 100-($sqlt/$time*100)-$tpl, $gzip, $r->uri();
    }

  };

 # error occured, create a dump file
  if(!defined $err && $@ && $DEBUG) {
    undef $res->{_Res};
    undef $res->{_Req};
    die $@;
  } elsif(!defined $err && $@) {
    if(open(my $E, sprintf '>/www/vndb/data/errors/%04d-%02d-%02d-%d',
        (localtime)[5]+1900, (localtime)[4]+1, (localtime)[3], time)) {
      print $E 'Error @ ' . scalar localtime;

      print $E "\n\nRequest:\n" . $r->the_request . "\n";
      print $E "$_: " . $r->headers_in->{$_} . "\n"
        for (keys %{$r->headers_in});

      print $E "\nParams:\n";
      my $re = Apache2::Request->new($r);
      print $E "$_: " . $re->param($_) . "\n"
        for ($re->param());

      print $E "\nError:\n$@\n\n";
      print $E "Warnings:\n".join('', @WARN)."\n";
      close($E);
    }
    $VNDB->DBRollBack();
    undef $res->{_Res};
    undef $res->{_Req};
    die "Error, check dumpfile!\n";
  }

  undef $res->{_Res};
  undef $res->{_Req};
 # let apache handle 404's
  $code = Apache2::Const::DECLINED if $code == 404;
  return $code;
}


sub mod_perl_init {
  require Apache2::RequestRec;
  require Apache2::RequestIO;
  $VNDB = __PACKAGE__->new(%VNDBopts);
  return 0;
}


sub mod_perl_exit {
  $VNDB->DBExit() if defined $VNDB && ref $VNDB eq __PACKAGE__;
  return 0;
}

