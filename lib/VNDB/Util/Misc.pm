
package VNDB::Util::Misc;

use strict;
use warnings;
use Exporter 'import';
use Tie::ShareLite ':lock';

our @EXPORT = qw|multiCmd|;


# Sends a command to Multi
# Argument: the commands to add to the queue, or none to send the queue to Multi
sub multiCmd {
  my $self = shift;

  $self->{_multiCmd} = [] if !$self->{_multiCmd};
  return push @{$self->{_multiCmd}}, @_ if @_;

  return if !@{$self->{_multiCmd}};

  my $s = tie my %s, 'Tie::ShareLite', -key => $self->{sharedmem_key}, -create => 'yes', -destroy => 'no', -mode => 0666;
  $s->lock(LOCK_EX);
  my @q = ( ($s{queue} ? @{$s{queue}} : ()), @{$self->{_multiCmd}} );
  $s{queue} = \@q;
  $s->unlock();
  $self->{_multiCmd} = [];
}


1;

