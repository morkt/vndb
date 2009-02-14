
package VNDB::Handler::Tags;


use strict;
use warnings;
use YAWF ':html';
use VNDB::Func;


YAWF::register(
  qr{g([1-9]\d*)},      \&tagpage,
  qr{g},                \&tagtree,
);


sub tagpage {
  my($self, $tag) = @_;

  # fetch tag
  my $t = $self->dbTagGet(id => $tag, what => 'parents childs(2)')->[0];
  return 404 if !$t;
 
  my $title = ($t->{meta} ? 'Meta tag: ' : 'Tag: ').$t->{name};
  $self->htmlHeader(title => $title);
  div class => 'mainbox';
   h1 $title;
   h2 class => 'alttitle', 'a.k.a. '.join(', ', split /\n/, $t->{aliases}) if $t->{aliases};

   # TODO: handle multiple parents here
   p;
    a href => '/g', 'Tags';
    for (sort { $a->{lvl} <=> $b->{lvl} } @{$t->{parents}}) {
      txt ' > ';
      a href => "/g$_->{tag}", $_->{name};
    }
    txt ' > '.$t->{name};
   end;

   if($t->{description}) {
     p;
      lit bb2html $t->{description};
     end;
   }

   if(@{$t->{childs}}) {
     ul class => 'tagtree';
      li 'Child tags';
      my $lvl = $t->{childs}[0]{lvl} + 1;
      for (@{$t->{childs}}) {
        map ul,  1..($lvl-$_->{lvl}) if $lvl > $_->{lvl};
        map end, 1..($_->{lvl}-$lvl) if $lvl < $_->{lvl};
        $lvl = $_->{lvl};
        li;
         txt ' > ';
         a href => "/g$_->{tag}", $_->{name};
        end;
      }
      map end, 0..($t->{childs}[0]{lvl}-$lvl);
     end;
   }

  end;
  $self->htmlFooter;
}


sub tagtree {
  my $self = shift;

  $self->htmlHeader(title => '[DEBUG] The complete tag tree');
  div class => 'mainbox';
   h1 '[DEBUG] The complete tag tree';

   my $t = $self->dbAll('SELECT * FROM tag_tree(0, -1, true)');
   ul class => 'tagtree';
    li "This page won't make it to the final version. (At least, not in this form)\n\n";
    my $lvl = $t->[0]{lvl} + 1;
    for (@$t) {
      map ul,  1..($lvl-$_->{lvl}) if $lvl > $_->{lvl};
      map end, 1..($_->{lvl}-$lvl) if $lvl < $_->{lvl};
      $lvl = $_->{lvl};
      li;
       txt ' > ';
       a href => "/g$_->{tag}", $_->{name};
      end;
    }
    map end, 0..($t->[0]{lvl}-$lvl);
   end;
  end;
  $self->htmlFooter;
}


1;
