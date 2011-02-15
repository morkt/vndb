
package VNDB::Handler::Chars;

use strict;
use warnings;
use TUWF ':html';
use VNDB::Func;


TUWF::register(
  qr{c([1-9]\d*)(?:\.([1-9]\d*))?} => \&page,
);


sub page {
  my($self, $id, $rev) = @_;

  my $r = $self->dbCharGet(
    id => $id,
    what => 'extended'.($rev ? ' changes' : ''),
    $rev ? ( rev => $rev ) : ()
  )->[0];
  return $self->resNotFound if !$r->{id};

  $self->htmlHeader(title => $r->{name});
  $self->htmlMainTabs(c => $r);
  return if $self->htmlHiddenMessage('c', $r);

  if($rev) {
    my $prev = $rev && $rev > 1 && $self->dbCharGet(id => $id, rev => $rev-1, what => 'changes extended')->[0];
    $self->htmlRevision('c', $prev, $r,
      [ name      => diff => 1 ],
      [ original  => diff => 1 ],
      [ alias     => diff => qr/[ ,\n\.]/ ],
      [ desc      => diff => qr/[ ,\n\.]/ ],
    );
  }

  div class => 'mainbox';
   $self->htmlItemMessage('c', $r);
   h1 $r->{name};
   h2 class => 'alttitle', $r->{original} if $r->{original};
   if($r->{desc}) {
     p class => 'description';
      lit bb2html($r->{desc});
     end;
   }
  end;
  $self->htmlFooter;
}


1;

