
package VNDB::Votes;

use strict;
use warnings;
use Exporter 'import';

use vars ('$VERSION', '@EXPORT');
$VERSION = $VNDB::VERSION;
@EXPORT = qw| VNVote VNVotes |;


sub VNVote {
  my $self = shift;
  my $id = shift;

  my $uid = $self->AuthInfo()->{id};
  return $self->ResDenied() if !$uid;

  my $f = $self->FormCheck(
    { name => 'v', required => 1, default => 0, enum => [ '-1','1'..'10'] }
  );
  return $self->ResNotFound() if $f->{_err};

  
  $self->DBDelVote($uid, $id) if $f->{v} == -1 || $self->DBGetVotes(uid => $uid, vid => $id)->[0]{vid};
  $self->DBAddVote($id, $uid, $f->{v}) if $f->{v} > 0;
   
  $self->ResRedirect('/v'.$id, 'temp');
}


sub VNVotes {
  my $self = shift;
  my $user = shift;
  
  my $u = $self->DBGetUser(uid => $user)->[0];
  return $self->ResNotFound if !$user || !$u || (($self->AuthInfo->{id}||0) != $user && !($u->{flags} & $VNDB::UFLAGS->{votes}));

  my $f = $self->FormCheck(
    { name => 's', required => 0, default => 'date', enum => [ qw|date title vote| ] },
    { name => 'o', required => 0, default => 'd', enum => [ 'a','d' ] },
    { name => 'p', required => 0, default => 1, template => 'int' },
  );
  return $self->ResNotFound if $f->{_err};

  my $order = $f->{s} . ($f->{o} eq 'a' ? ' ASC' : ' DESC');
  my ($votes, $np) = $self->DBGetVotes(
    uid => $u->{id},
    order => $order,
    results => 50,
    page => $f->{p}
  );

  $self->ResAddTpl(myvotes => {
    user => $u,
    votes => $votes,
    page => $f->{p},
    npage => $np,
    order => [ $f->{s}, $f->{o} ],
  });
}
