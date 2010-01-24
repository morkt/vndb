
package SkinFile;

use strict;
use warnings;
use Fcntl 'LOCK_SH', 'SEEK_SET';


sub new {
  my($class, $root, $open) = @_;
  my $self = bless { root => $root }, $class;
  $self->open($open) if $open;
  return $self;
}


sub list {
  return map /\/([^\/]+)\/conf/?$1:(), glob "$_[0]{root}/*/conf";
}


sub open {
  my($self, $dir, $force) = @_;
  return if $self->{"s_$dir"} && !$force;
  my %o;
  open my $F, '<:utf8', "$self->{root}/$dir/conf" or die $!;
  flock $F, LOCK_SH or die $!;
  seek $F, 0, SEEK_SET or die $!;
  while(<$F>) {
    chomp;
    s/\r//g;
    s{[\t\s]*//.+$}{};
    next if !/^([a-z0-9]+)[\t\s]+(.+)$/;
    $o{$1} = $2;
  }
  close $F;
  $self->{"s_$dir"} = \%o;
  $self->{opened} = $dir;
}


sub get {
  my($self, $dir, $var) = @_;
  $self->open($dir) if defined $var;
  $var = $dir if !defined $var;
  $var ? $self->{"s_$self->{opened}"}{$var} : keys %{$self->{"s_$self->{opened}"}};
}


1;


__END__

=pod

=head1 NAME

SkinFile - Simple object oriented interface to parsing skin configuration files

=head1 USAGE

  use SkinFile;
  my $s = SkinFile->new($dir);
  my @skins = $s->list;

  $s->open($skins[0]);
  my $name = $s->get('name');

  # same as above, but in one function
  my $name = $s->get($skins[0], 'name');


