
package VNDB::Users;

use strict;
use warnings;
use Exporter 'import';
use Digest::MD5 'md5_hex';

our $VERSION = $VNDB::VERSION;
our @EXPORT = qw| UsrLogin UsrLogout UsrReg UsrPass UsrEdit UsrList UsrPage |;


sub UsrLogin {
  my $self = shift;
  
  (return $self->ResRedirect('/', 'temp')) if $self->AuthInfo()->{id};
  
  my $frm = {};
  if($self->ReqMethod() eq 'POST') {
    $frm = $self->FormCheck(
      { name => 'username', required => 1, minlength => 2, maxlength => 15, template => 'pname' },
      { name => 'userpass', required => 1, minlength => 4, maxlength => 15, template => 'asciiprint' },
    );
    if(!$frm->{_err}) {
      (my $ref = $self->ReqHeader('Referer')||'/') =~ s/^$self->{root_url}//;
      my $r = $self->AuthLogin($frm->{username}, $frm->{userpass}, 1, $ref);
      $r == 1 ? (return) : ($frm->{_err} = [ 'loginerr' ]);
    }
  }
  
  $self->ResAddTpl(userlogin => {
    log => $frm,
  } );
}


sub UsrLogout {
  shift->AuthLogout();
}


sub UsrReg {
  my $self = shift;

  (return $self->ResRedirect('/', 'temp')) if $self->AuthInfo()->{id};

  my $frm = {};
  if($self->ReqMethod() eq 'POST') {
    $frm = $self->FormCheck(
      { name => 'username',    required => 1, minlength => 2, maxlength => 15, template => 'pname' },
      { name => 'mail',        required => 1, template => 'mail' },
      { name => 'pass1',       required => 1, minlength => 4, maxlength => 15, template => 'asciiprint' },
      { name => 'pass2',       required => 1, minlength => 4, maxlength => 15, template => 'asciiprint' },
    );
    $frm->{_err} = $frm->{_err} ? [ @{$frm->{_err}}, 'badpass' ] : [ 'badpass' ]
      if $frm->{pass1} ne $frm->{pass2};
    $frm->{_err} = $frm->{_err} ? [ @{$frm->{_err}}, 'usrexists' ] : [ 'usrexists' ]
      if $frm->{username} eq 'anonymous' || $self->DBGetUser(username => $frm->{username})->[0];
    $frm->{_err} = $frm->{_err} ? [ @{$frm->{_err}}, 'mailexists' ] : [ 'mailexists' ]
      if $frm->{mail} && $self->DBGetUser(mail => $frm->{mail})->[0];

    if(!$frm->{_err}) {
      $self->DBAddUser($frm->{username}, md5_hex($frm->{pass1}), $frm->{mail}, 2);
      return $self->AuthLogin($frm->{username}, $frm->{pass1}, 1, '/');
    }
  }
  $self->ResAddTpl(userreg => {
    reg => $frm,
  });
}


sub UsrPass {
  my $self = shift;

  (return $self->ResRedirect('/', 'temp')) if $self->AuthInfo()->{id};

  my $d = $self->ReqParam('d');

  my $frm = {};
  if(!$d && $self->ReqMethod() eq 'POST') {
    $frm = $self->FormCheck({ name => 'mail', required => 1, template => 'mail' });
    my $unfo;
    if(!$frm->{_err}) {
      $frm->{mail} =~ s/%//g;
      $unfo = $self->DBGetUser(mail => $frm->{mail})->[0];
      $frm->{_err} = $frm->{_err} ? [ @{$frm->{_err}}, 'nomail' ] : [ 'nomail' ]
        if !$unfo;
    }
    if(!$frm->{_err}) {
      my @chars = ( 'A'..'Z', 'a'..'z', 0..9 );
      my $pass = join('', map $chars[int rand $#chars+1], 0..8);
      $self->DBUpdateUser($unfo->{id}, passwd => md5_hex($pass));
      $self->SendMail(sprintf(<<__, $unfo->{username}, $unfo->{username}, $pass),
Hello %s,

Your password has been reset, you can now login at http://vndb.org/ with the
following information:

Username: %s
Password: %s

Now don't forget your password again! :-)

vndb.org
__
        To => $frm->{mail},
        Subject => sprintf('Password request for %s', $unfo->{username}),
      );
      return $self->ResRedirect('/u/newpass?d=1', 'post');
    }
  }

  $self->ResAddTpl(userpass => {
    pas => $frm,
    done => $d,
  });
}


sub UsrEdit {
  my $self = shift;
  my $user = shift;

  my $u = $self->AuthInfo();
  return $self->ResDenied if !$u->{id};
  my $adm = $u->{id} != $user;
  return $self->ResDenied if $adm && !$self->AuthCan('useredit');
  $u = $self->DBGetUser(uid => $user)->[0] if $adm;
  return $self->ResNotFound if !$u->{id};

  my $d = $self->ReqParam('d');
  
  my $frm = {};
  if(!$d && $self->ReqMethod() eq 'POST') {
    $frm = $self->FormCheck(
      { name => 'mail',  required => 1, template => 'mail' },
      { name => 'pass1', required => 0, template => 'asciiprint' },
      { name => 'pass2', required => 0, template => 'asciiprint' },
      { name => 'rank',  required => $adm, enum => [ '1'..($#{$self->{ranks}}-1) ] },
      { name => 'pvotes',required => 0 },
      { name => 'plist', required => 0 },
      { name => 'pign_nsfw', required => 0 },
    );
    if(($frm->{pass1} || $frm->{pass2}) && $frm->{pass1} ne $frm->{pass2}) {
      $frm->{_err} = [] if !$frm->{_err};
      push(@{$frm->{_err}}, 'badpass');
    }
    if(!$frm->{_err}) {
      my $pass = $frm->{pass1} ? md5_hex($frm->{pass1}) : '';
      my %opts = (
        'mail'        => $frm->{mail},
      );
      $opts{passwd}    = $pass if $pass;
      $opts{rank}      = $frm->{rank} if $adm;
      $opts{flags}     = $frm->{pvotes} ? $VNDB::UFLAGS->{votes} : 0;
      $opts{flags}    += $VNDB::UFLAGS->{list} if $frm->{plist};
      $opts{flags}    += $VNDB::UFLAGS->{nsfw} if $frm->{pign_nsfw};
      $self->DBUpdateUser($u->{id}, %opts);
      return $adm ? $self->ResRedirect('/u'.$user.'/edit?d=1', 'post') :
            $pass ? $self->AuthLogin($user, $frm->{pass1}, 1, '/u'.$user.'/edit?d=1') :
                    $self->ResRedirect('/u'.$user.'/edit?d=1', 'post');
    }
  }

  $frm->{$_} ||= $u->{$_}
    for (qw| username mail rank |);
  $frm->{pvotes}    ||= $u->{flags} & $VNDB::UFLAGS->{votes};
  $frm->{plist}     ||= $u->{flags} & $VNDB::UFLAGS->{list};
  $frm->{pign_nsfw} ||= $u->{flags} & $VNDB::UFLAGS->{nsfw};
  $self->ResAddTpl(useredit => {
    form => $frm,
    done => $d,
    adm => $adm,
    user => $user,
  });
}


sub UsrList {
  my $self = shift;
  my $chr = shift;
  $chr = 'all' if !defined $chr;
  
  my $f = $self->FormCheck(
    { name => 's', required => 0, default => 'username', enum => [ qw|username mail rank registered| ] },
    { name => 'o', required => 0, default => 'a', enum => [ 'a','d' ] },
    { name => 'p', required => 0, default => 1, template => 'int' },
  );

  my($unfo, $np) = $self->DBGetUser(
    order => $f->{s}.($f->{o} eq 'a' ? ' ASC' : ' DESC'),
    $chr ne 'all' ? (
      firstchar => $chr ) : (),
    results => 50,
    page => $f->{p},
    what => 'list',
  );

  $self->ResAddTpl(userlist => {
    users => $unfo, 
    chr => $chr,
    page => $f->{p},
    npage => $np,
    order => [ $f->{s}, $f->{o} ],
  } );
}


sub UsrPage {
  my($self, $id) = @_;
  
  my $u = $self->DBGetUser(uid => $id, what => 'list')->[0];
  return $self->ResNotFound if !$u;

  $self->ResAddTpl(userpage => {
    user => $u,
    lists => {
      latest => scalar $self->DBGetVNList(uid => $id, results => 7),
      graph => $self->DBVNListStats(uid => $id),
    },
    votes => {
      latest => scalar $self->DBGetVotes(uid => $id, results => 10),
      graph => $self->DBVoteStats(uid => $id),
    },
  });
}

1;

