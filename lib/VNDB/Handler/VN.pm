
package VNDB::Handler::VN;

use strict;
use warnings;
use YAWF ':html';
use VNDB::Func;


YAWF::register(
  qr{v([1-9]\d*)}       => \&page,
);


sub page {
  my($self, $vid) = @_;

  # TODO: revision-awareness, hidden/locked flag check

  my $v = $self->dbVNGet(id => $vid, what => 'extended')->[0];
  return 404 if !$v->{id};

  $self->htmlHeader(title => $v->{title});
  $self->htmlMainTabs('v', $v);
  div class => 'mainbox';
   h1 $v->{title};
   h2 class => 'alttitle', $v->{original} if $v->{original};

   div class => 'vndetails';

    # image 
    div class => 'vnimg';
     # TODO: check for img_nsfw and processing flag
     if($v->{image}) {
       img src => sprintf("%s/cv/%02d/%d.jpg", $self->{url_static}, $v->{image}%100, $v->{image}), alt => $v->{title};
     } else {
       p 'No image uploaded yet';
     }
    end;

    # general info
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
     my @links = (
       $v->{l_wp} ?      [ 'Wikipedia', 'http://en.wikipedia.org/wiki/%s', $v->{l_wp} ] : (),
       $v->{l_encubed} ? [ 'Encubed',   'http://novelnews.net/tag/%s/', $v->{l_encubed} ] : (),
       $v->{l_renai} ?   [ 'Renai.us',  'http://renai.us/game/%s.shtml', $v->{l_renai} ] : (),
       $v->{l_vnn}  ?    [ 'V-N.net',   'http://visual-novels.net/vn/index.php?option=com_content&task=view&id=%d', $v->{l_vnn} ] : (),
     );
     if(@links) {
       Tr ++$i % 2 ? (class => 'odd') : ();
        td 'Links';
        td;
         for(@links) {
           a href => sprintf($_->[1], $_->[2]), $_->[0];
           txt ', ' if $_ ne $links[$#links];
         }
        end;
       end;
     }

     # TODO: producers, categories, relations, anime

    end;
   end;

   # description
   div class => 'vndescription';
    h2 'Description';
    p;
     lit bb2html $v->{desc};
    end;
   end;
  end;

  # TODO: Releases, stats, relation graph, screenshots

  $self->htmlFooter;
}


1;

