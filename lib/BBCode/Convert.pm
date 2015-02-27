# bbcode->html converter with length check and input escape

package BBCode::Convert;

use strict;
use warnings;
use parent 'BBCode::Base';


sub _start {
  my $self = shift;
  $self->SUPER::_start(@_);
  $self->{length} = 0;
  $self->{rmnewline} = 0;
  $_[0] =~ s/\r//g;
}


sub _append_text {
  my($self, $text, $l) = @_;
  return undef if $self->{maxlength} && $self->{length} > $self->{maxlength};
  $self->{length} += $l // length $text;
  return $self->_append($text);
}


# escapes, returns string, and takes care of $length and $maxlength; also
# takes care to remove newlines and double spaces when necessary
sub _escape {
  my $self = shift;
  local $_ = shift;
  s/^\n// if $self->{rmnewline} && $self->{rmnewline}--;
  if($self->{open}[-1] ne 'code') {
    s/\n{5,}/\n\n/g;
    s/  +/ /g;
  }
  my $l = length;
  if($self->{maxlength} && ($l+$self->{length}) > $self->{maxlength}) {
    $_ = substr($_, 0, $self->{maxlength}-($l+$self->{length}));
    s/[ \.,:;]+[^ \.,:;]*$//; # cleanly cut off on word boundary
  }
  s/&/&amp;/g;
  s/>/&gt;/g;
  s/</&lt;/g;
  s/\n/<br \/>/g if !$self->{oneline};
  s/\n/ /g       if $self->{oneline};
  return ($_, $l);
}


sub _finish {
  my $self = shift;
  $self->_append('...') if $self->{maxlength} && $self->{length} > $self->{maxlength};
  return $self->SUPER::_finish;
}


1;
