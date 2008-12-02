
package VNDB::Handler::Releases;

use strict;
use warnings;
use YAWF ':html';
use VNDB::Func;


YAWF::register(
  qr{r([1-9]\d*)},  \&page,
);


sub page {
  my($self, $rid) = @_;

  my $r = $self->dbReleaseGet(id => $rid, what => 'vn producers platforms media')->[0];
  return 404 if !$r->{id};

  $self->htmlHeader(title => $r->{title});
  $self->htmlMainTabs('r', $r);
  div class => 'mainbox release';
   h1 $r->{title};
   h2 class => 'alttitle', $r->{original} if $r->{original};

   _infotable($self, $r);

   if($r->{notes}) {
     p class => 'description';
      lit bb2html $r->{notes};
     end;
   }

  end;
  $self->htmlFooter;
}


sub _infotable {
  my($self, $r) = @_;
  table;
   Tr;
    td class => 'key', ' ';
    td ' ';
   end;
   my $i = 0;

   Tr ++$i % 2 ? (class => 'odd') : ();
    td 'Relation';
    td;
     for (@{$r->{vn}}) {
       a href => "/v$_->{vid}", title => $_->{original}||$_->{title}, shorten $_->{title}, 60;
       br if $_ != $r->{vn}[$#{$r->{vn}}];
     }
    end;
   end;

   Tr ++$i % 2 ? (class => 'odd') : ();
    td 'Type';
    td;
     my $type = $self->{release_types}[$r->{type}];
     acronym class => 'icons '.lc(substr $type, 0, 3), title => $type, ' ';
     txt ' '.$type;
    end;
   end;

   Tr ++$i % 2 ? (class => 'odd') : ();
    td 'Language';
    td;
     acronym class => "icons lang $r->{language}", title => $self->{languages}{$r->{language}}, ' ';
     txt ' '.$self->{languages}{$r->{language}};
    end;
   end;

   if(@{$r->{platforms}}) {
     Tr ++$i % 2 ? (class => 'odd') : ();
      td 'Platform'.($#{$r->{platforms}} ? 's' : '');
      td;
       for(@{$r->{platforms}}) {
         acronym class => "icons $_", title => $self->{platforms}{$_}, ' ';
         txt ' '.$self->{platforms}{$_};
         br if $_ ne $r->{platforms}[$#{$r->{platforms}}];
       }
      end;
     end;
   }

   if(@{$r->{media}}) {
     Tr ++$i % 2 ? (class => 'odd') : ();
      td 'Medi'.($#{$r->{media}} ? 'a' : 'um');
      td join ', ', map {
        my $med = $self->{media}{$_->{medium}};
        $med->[1] ? sprintf('%d %s%s', $_->{qty}, $med->[0], $_->{qty}>1?'s':'') : $med->[0]
      } @{$r->{media}};
     end;
   }

   Tr ++$i % 2 ? (class => 'odd') : ();
    td 'Released';
    td;
     lit datestr $r->{released};
    end;
   end;

   if($r->{minage} >= 0) {
     Tr ++$i % 2 ? (class => 'odd') : ();
      td 'Age rating';
      td $self->{age_ratings}{$r->{minage}};
     end;
   }

   if(@{$r->{producers}}) {
     Tr ++$i % 2 ? (class => 'odd') : ();
      td 'Producer'.($#{$r->{producers}} ? 's' : '');
      td;
       for (@{$r->{producers}}) {
         a href => "/p$_->{id}", title => $_->{original}||$_->{name}, shorten $_->{name}, 60;
         br if $_ != $r->{producers}[$#{$r->{producers}}];
       }
      end;
     end;
   }

   if($r->{gtin}) {
     Tr ++$i % 2 ? (class => 'odd') : ();
      td gtintype $r->{gtin};
      td $r->{gtin};
     end;
   }

   if($r->{website}) {
     Tr ++$i % 2 ? (class => 'odd') : ();
      td 'Links';
      td;
       a href => $r->{website}, rel => 'nofollow', 'Official website';
      end;
     end;
   }

  end;
}



1;

