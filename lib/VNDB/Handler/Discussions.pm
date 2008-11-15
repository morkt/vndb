
package VNDB::Handler::Discussions;

use strict;
use warnings;
use YAWF ':html';
use POSIX 'ceil';
use VNDB::Func;


YAWF::register(
  qr{t([1-9]\d*)(?:/([1-9]\d*))?} => \&thread,
  qr{t([1-9]\d*)\.([1-9]\d*)}     => \&redirect,
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


  if($t->{count} < $page*25 && $self->authCan('board')) {
    form action => "/t$tid/reply", method => 'post', 'accept-charset' => 'UTF-8';
     div class => 'mainbox';
      fieldset class => 'submit';
       h2 'Quick reply';
       textarea name => 'msg', id => 'msg', rows => 4, cols => 50, '';
       br;
       input type => 'submit', value => 'Reply', class => 'submit';
      end;
     end; 
    end;
  } elsif(!$self->authCan('board')) {
    div class => 'mainbox';
     h1 'Reply';
     p class => 'center', 'You must be logged in to reply to this thread.';
    end;
  }

  $self->htmlFooter;
}


sub redirect {
  my($self, $tid, $num) = @_;
  $self->resRedirect("/t$tid".($num > 25 ? '/'.ceil($num/25) : '').'#'.$num, 'perm');
}


1;

