
package VNDB::Handler::Discussions;

use strict;
use warnings;
use YAWF ':html';
use VNDB::Func;


YAWF::register(
  qr{t([1-9]\d*)(?:/([1-9]\d*))?} => \&thread,
);


sub thread {
  my($self, $tid, $page) = @_;
  $page ||= 1;

  my $t = $self->dbThreadGet(id => $tid)->[0];
  return 404 if !$t->{id} || $t->{hidden} && !$self->authCan('boardmod');

  my $p = $self->dbPostGet(tid => $tid, results => 25, page => $page);
  return 404 if !$p->[0];

  $self->htmlHeader(title => $t->{title});

  div class => 'mainbox';
   h1 $t->{title};
   p '[selected tags here]';
  end;

  $self->htmlBrowseNavigate("/t$tid/", $page, $t->{count} > $page*25, 't', 1);
  div class => 'mainbox thread';
   table;
    for my $i (0..$#$p) {
      local $_ = $p->[$i];
      Tr $i % 2 == 0 ? (class => 'odd') : ();
       td class => 'tc1';
        a href => "/t$tid.$_->{num}", name => $_->{num}, "#$_->{num}";
        txt ' by ';
        lit userstr $_;
        br;
        lit date $_->{date}, 'full';
       end;
       td class => 'tc2';
        lit bb2html $_->{msg};
       end;
      end;
    }
   end;
  end;
  $self->htmlBrowseNavigate("/t$tid/", $page, $t->{count} > $page*25, 'b', 1);

  $self->htmlFooter;
}


1;

