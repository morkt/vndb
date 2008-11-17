
package VNDB::Handler::VN;

use strict;
use warnings;
use YAWF ':html';


YAWF::register(
  qr{v([1-9]\d*)}       => \&page,
);


sub page {
  my($self, $vid) = @_;

  my $v = $self->dbVNGet(id => $vid, what => 'extended')->[0];
  return 404 if !$v->{id};

  $self->htmlHeader(title => $v->{title});
  $self->htmlMainTabs('v', $v);
  div class => 'mainbox';
   h1 $v->{title};
   h2 class => 'alttitle', $v->{original} if $v->{original};

   div class => 'vndetails';
    div class => 'vnimg';
     # TODO: check for img_nsfw
     if($v->{image}) {
       img src => sprintf("%s/cv/%02d/%d.jpg", $self->{url_static}, $v->{image}%100, $v->{image}), alt => $v->{title};
     } else {
       p 'No image uploaded yet';
     }
    end;
    table;
     my $i = 0;
     if($v->{length}) {
       Tr ++$i % 2 ? (class => 'odd') : ();
        td 'Length';
        td "$self->{vn_lengths}[$v->{length}][0] ($self->{vn_lengths}[$v->{length}][1])";
       end;
     }
     if($v->{alias}) {
       Tr ++$i % 2 ? (class => 'odd') : ();
        td 'Aliases';
        td $v->{alias};
       end;
     }
    end;
   end;
  end;
  $self->htmlFooter;
}


1;

