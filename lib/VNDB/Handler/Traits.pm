
package VNDB::Handler::Traits;

use strict;
use warnings;
use TUWF ':html';
use VNDB::Func;


TUWF::register(
  qr{i([1-9]\d*)},  \&traitpage,
);


sub traitpage {
  my($self, $trait) = @_;

  my $t = $self->dbTraitGet(id => $trait, what => 'parents(0) childs(2) aliases')->[0];
  return $self->resNotFound if !$t;

  my $title = mt '_traitp_title', $t->{meta}?0:1, $t->{name};
  $self->htmlHeader(title => $title, noindex => $t->{state} != 2);

  if($t->{state} != 2) {
    div class => 'mainbox';
     h1 $title;
     if($t->{state} == 1) {
       div class => 'warning';
        h2 mt '_traitp_del_title';
        p;
         lit mt '_traitp_del_msg';
        end;
       end;
     } else {
       div class => 'notice';
        h2 mt '_traitp_pending_title';
        p mt '_traitp_pending_msg';
       end;
     }
    end 'div';
  }

  div class => 'mainbox';
   h1 $title;

   parenttags($t, mt('_traitp_indexlink'), 'i');

   if($t->{description}) {
     p class => 'description';
      lit bb2html $t->{description};
     end;
   }
   if(@{$t->{aliases}}) {
     p class => 'center';
      b mt('_traitp_aliases');
      br;
      lit xml_escape($_).'<br />' for (@{$t->{aliases}});
     end;
   }
  end 'div';

  childtags($self, mt('_traitp_childs'), 'i', $t) if @{$t->{childs}};

  # TODO: list of characters
  
  $self->htmlFooter;
}


1;

__END__

Simple test database:

  INSERT INTO traits (name, description, state, meta, addedby) VALUES
    ('Blood Type', 'Describes the blood type of the character', 2, true, 2),
    ('Blood Type O', '', 2, true, 2),
    ('Blood Type B', '', 2, true, 2);
  INSERT INTO traits_parents (trait, parent) VALUES (2, 1), (3, 1);


