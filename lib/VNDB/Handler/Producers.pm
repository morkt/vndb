
package VNDB::Handler::Producers;

use strict;
use warnings;
use YAWF ':html';
use VNDB::Func;


YAWF::register(
  qr{p([1-9]\d*)}             => \&page,
  qr{p([1-9]\d*)/(lock|hide)} => \&mod,
);


sub page {
  my($self, $pid) = @_;

  my $p = $self->dbProducerGet(id => $pid, what => 'vn')->[0];
  return 404 if !$p->{id};

  $self->htmlHeader(title => $p->{name});
  $self->htmlMainTabs(p => $p);
  div class => 'mainbox producerpage';
   h1 $p->{name};
   h2 class => 'alttitle', $p->{original} if $p->{original};
   p class => 'center';
    txt "$self->{languages}{$p->{lang}} \L$self->{producer_types}{$p->{type}}";
    if($p->{website}) {
      txt "\n";
      a href => $p->{website}, $p->{website};
    }
   end;

   if($p->{desc}) {
     p class => 'description';
      lit bb2html $p->{desc};
     end;
   }

  end;
  div class => 'mainbox producerpage';
   h1 'Visual Novel Relations';
   if(!@{$p->{vn}}) {
     p 'We have currently no visual novels related to this producer.';
   } else {
     ul;
      for (@{$p->{vn}}) {
        li;
         i;
          lit datestr $_->{date};
         end;
         a href => "/v$_->{id}", title => $_->{original}, $_->{title};
        end;
      }
     end;
   }
  end;
  $self->htmlFooter;
}


# /hide and /lock
sub mod {
  my($self, $pid, $act) = @_;
  return $self->htmlDenied if !$self->authCan($act eq 'hide' ? 'del' : 'lock');
  my $p = $self->dbProducerGet(id => $pid)->[0];
  return 404 if !$p->{id};
  $self->dbProducerMod($pid, $act eq 'hide' ? (hidden => !$p->{hidden}) : (locked => !$p->{locked}));
  $self->resRedirect("/p$pid", 'temp');
}


1;

