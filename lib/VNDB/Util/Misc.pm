
package VNDB::Util::Misc;

use strict;
use warnings;
use Exporter 'import';
use Tie::ShareLite ':lock';

our @EXPORT = qw|multiCmd vnCacheUpdate|;


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


# Recalculates the vn.c_* columns and regenerates the related relation graphs on any change
# Arguments: list of vids to be updated
sub vnCacheUpdate {
  my($self, @vns) = @_;

  my $before = $self->dbVNGet(id => \@vns, order => 'v.id', what => 'relations');
  $self->dbVNCache(@vns);
  my $after = $self->dbVNGet(id => \@vns, order => 'v.id');

  my @upd = map {
    @{$before->[$_]{relations}} && (
      $before->[$_]{c_released} != $after->[$_]{c_released}
      || $before->[$_]{c_languages} ne $after->[$_]{c_languages}
    ) ? $before->[$_]{id} : ();
  } 0..$#$before;
  $self->multiCmd('relgraph '.join(' ', @upd)) if @upd;
}


1;
