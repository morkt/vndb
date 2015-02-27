# VNDBID->[url] converter

package BBCode::VNDBLinks;

use strict;
use warnings;
use parent 'BBCode::Base';


# required option: vndb => reference to the TUWF object
sub new {
  my $class = shift;
  my $self = BBCode::_define(verbatim => 1, @_);
  $self->{dblink} = sub {
    my($self, $link) = @_;
    if($link =~ $self->{dbidre}) {
      $self->{lookup}{$1}{$2} = 1;
      return [ $link, $& ];
    }
    return $link;
  };
  return bless $self, $class;
}


sub _start {
  my $self = shift;
  $self->{lookup} = {};
  # nodes are either strings or array references [ matched_text, link_id ]
  $self->{nodes} = [];
}


sub _append {
  my $self = shift;
  push @{$self->{nodes}}, $_[0];
}


# map db type to the item retrieval method.
my %def = qw(
  v dbVNGet
  c dbCharGet
  s dbStaffGet
  p dbProducerGet
  g dbTagGet
  i dbTraitGet
);

sub _finish {
  my $self = shift;
  return join('', @{$self->{nodes}}) unless %{$self->{lookup}};

  # lookup parsed links
  my %links;
  while(my($t, $ids) = each %{$self->{lookup}}) {
    if(my $dbfunc = $self->{vndb}->can($def{$t})) {
      $links{$t.$_->{id}} = $_->{$t eq 'v' ? 'title' : 'name'}
        for @{$dbfunc->($self->{vndb}, id => [keys %$ids], results => 50)};
    }
  }
  my $result = '';
  for(@{$self->{nodes}}) {
    if(ref) {
      $_ = $links{$_->[1]} ?
        sprintf('[url=/%s]%s[/url]', $_->[0], $links{$_->[1]}) : $_->[0];
    }
    $result .= $_;
  }
  return $result;
}


1;
