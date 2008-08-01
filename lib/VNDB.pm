package VNDB;

use strict;
use warnings;

BEGIN { require 'global.pl'; }
our $DEBUG;

require Time::HiRes if $DEBUG;
require Data::Dumper if $DEBUG;
use VNDB::Util::Template;
use VNDB::Util::Request;
use VNDB::Util::Response;
use VNDB::Util::DB;
use VNDB::Util::Tools;
use VNDB::Util::Auth;
use VNDB::Discussions;
use VNDB::HomePages;
use VNDB::Producers;
use VNDB::Releases;
use VNDB::VNLists;
use VNDB::Users;
use VNDB::VN;


my %VNDBuris = ( # wildcards: * -> (.+), + -> ([0-9]+)
  '/'           => sub { shift->HomePage },
  'd+'          => sub { shift->DocPage(shift) },
  'd+.+'        => sub { shift->ResRedirect('/d'.$_[0][0].'#'.$_[0][1]) },
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
    edit        => sub { shift->UsrEdit(shift) },
    del         => sub { shift->UsrDel(shift) },
    list        => sub { shift->RList(shift) },
    vlist       => sub { shift->VNMyList(shift) },
    wish        => sub { shift->WList(shift) },
    hist => {'*'=> sub { shift->History('u', shift, $_[1]) } },
  },
 # visual novels
  v => {
    '/'         => sub { shift->VNBrowse },
    new         => sub { shift->VNEdit(0); },
    '*'         => sub { $_[2] =~ /^([a-z0]|all|search)$/ ? shift->VNBrowse($_[1]) : shift->ResNotFound; },
  },
  'v+' => {
    '/'         => sub { shift->VNPage(shift) },
    stats       => sub { shift->VNPage(shift, shift) },
    rg          => sub { shift->VNPage(shift, shift) },
    edit        => sub { shift->VNEdit(shift) },
    vote        => sub { shift->VNVote(shift) },
    wish        => sub { shift->WListMod(shift) },
    add         => sub { shift->REdit('v', shift) },
    lock        => sub { shift->VNLock(shift) },     
    hide        => sub { shift->VNHide(shift) },
    hist => {'*'=> sub { shift->History('v', shift, $_[1]) } },
  },
  'v+.+'        => sub { shift->VNPage($_[0][0], '', $_[0][1]) },
 # releases
  'r+' => {
    '/'         => sub { shift->RPage(shift) },
    edit        => sub { shift->REdit('r', shift) },
    lock        => sub { shift->RLock(shift) },
    hide        => sub { shift->RHide(shift) },
    list        => sub { shift->RListMod(shift) },
    hist => {'*'=> sub { shift->History('r', shift, $_[1]) } },
  },
  'r+.+'        => sub { shift->RPage($_[0][0], $_[0][1]) },
 # producers
  p => {
    '/'         => sub { shift->PBrowse },
    add         => sub { shift->PEdit(0) },
    '*'         => sub { $_[2] =~ /^([a-z0]|all)$/ ? shift->PBrowse($_[1]) : shift->ResNotFound; }
  },
  'p+' => {
    '/'         => sub { shift->PPage(shift) },
    edit        => sub { shift->PEdit(shift) },
    lock        => sub { shift->PLock(shift) },
    hide        => sub { shift->PHide(shift) },
    hist => {'*'=> sub { shift->History('p', shift, $_[1]) } },
  },
  'p+.+'        => sub { shift->PPage($_[0][0], $_[0][1]) },
 # discussions
  t => {
    '/'         => sub { shift->TIndex },
    '*' => {
      '/'       => sub { shift->TTag($_[1]) },
      new       => sub { shift->TEdit(0, 0, $_[1]) }, 
    },
  },
  't+' => {
    '/'         => sub { shift->TThread(shift) },
    reply       => sub { shift->TEdit(shift) },
    '+'         => sub { shift->TThread(shift, shift) },
  },
  't+.+' => {
    edit        => sub { shift->TEdit($_[0][0], $_[0][1]) },
    '/'         => sub { $_[0]->ResRedirect('/t'.$_[1][0].($_[1][1]>$_[0]->{postsperpage}?'/'.ceil($_[1][1]/$_[0]->{postsperpagee}):'').'#'.$_[1][1], 'perm') },
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
  notes         => sub { shift->ResRedirect('/d8', 'perm') },
  vn => {
    rss         => sub { shift->ResRedirect('/hist/rss?t=v&e=1', 'perm') },
    '*'         => sub { shift->ResRedirect('/v/'.$_[1], 'perm') },
  },
  v => {
    cat         => sub {
      my $f = $_[0]->FormCheck({name=>'i',required=>0},{name=>'e',required=>0},{name=>'l',required=>0},
                               {name=>'p',required=>0},{name=>'o',required=>0},{name=>'s',required=>0});
      my %f;
      $f{$_} = $f->{$_} for (qw|p o s|);
      $f{q} = join ' ', (map $VNDB::CAT->{substr($_,0,1)}[1]{substr($_,1,2)}, split /,/, $f->{i}),
                        (map '-'.$VNDB::CAT->{substr($_,0,1)}[1]{substr($_,1,2)}, split /,/, $f->{e}),
                        (map $VNDB::LANG->{$_}, split /,/, $f->{l});
      !$f{$_}&&delete $f{$_} for keys %f;
      $_[0]->ResRedirect('/v/search'.(!(keys %f)?'':'?'.join(';', map $_.'='.$f{$_}, keys %f) ), 'perm');
    },
  },
  'v+' => {
    votes       => sub { shift->ResRedirect('/v'.(shift).'/stats', 'perm') },
    hist=>{rss  => sub { shift->ResRedirect('/v'.(shift).'/hist/rss.xml', 'perm') } },
    '/'         => sub {
      my $r=$_[0]->FormCheck({name=>'rev',required=>0,default=>0,template=>'int'})->{rev};
      my $i=$_[0]->DBGetHist(cid => [$r])->[0];
      $i && $i->{rev} ? $_[0]->ResRedirect('/'.((qw|v r p|)[$i->{type}]).$_[1].'.'.$i->{rev}, 'perm') : $_[0]->ResNotFound;
    },
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
  },
  'u+' => {
    votes       => sub { shift->ResRedirect('/u'.(shift).'/list', 'perm') },
    hist=>{rss  => sub { shift->ResRedirect('/u'.(shift).'/hist/rss.xml', 'perm') } },
  },
  'p+' => {
    hist=>{rss  => sub { shift->ResRedirect('/p'.(shift).'/hist/rss.xml', 'perm') } },
  },
  'r+' => {
    hist=>{rss  => sub { shift->ResRedirect('/r'.(shift).'/hist/rss.xml', 'perm') } },
  },
  hist=>{rss    => sub { shift->ResRedirect('/hist/rss.xml', 'perm') } },
);
$OLDuris{'r+'}{'/'} = $OLDuris{'p+'}{'/'} = $OLDuris{'v+'}{'/'};



sub new {
  my $self = shift;
  my $type = ref($self) || $self;
  my %args = @_;

  my $me = bless {
    debug => $VNDB::DEBUG,
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
      (my $t = "^$_\$") =~ s/\./\\./g;
      /\*/ ? ($t =~ s/\*/(.+)/g) : ($t =~ s/\+/([1-9][0-9]*)/g);
      $u->[$i] =~ /$t/ ? ($u->[$i] = $2?[$1,$2]:$1) && $_ : ();
    } else { () } }
    sort { length($b) <=> length($a) } keys %$o)[0] || '*');
  ref($o->{$n}) eq 'HASH' && $n ne '/' ?
    $s->uri2page($o->{$n}, $u, ++$i) :
    ref($o->{$n}) eq 'CODE' && $i == $#$u ?
    &{$o->{$n}}($s, @$u) :
    $s->ResNotFound();
}


1;

