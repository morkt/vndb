
package VNDB::Handler::Discussions;

use strict;
use warnings;
use YAWF ':html';
use POSIX 'ceil';
use VNDB::Func;


YAWF::register(
  qr{t([1-9]\d*)(?:/([1-9]\d*))?}       => \&thread,
  qr{t([1-9]\d*)\.([1-9]\d*)}           => \&redirect,
  qr{t/(db|an|[vpu])([1-9]\d*)?}  => \&tagbrowse,
);


sub thread {
  my($self, $tid, $page) = @_;
  $page ||= 1;

  my $t = $self->dbThreadGet(id => $tid, what => 'tagtitles')->[0];
  return 404 if !$t->{id} || $t->{hidden} && !$self->authCan('boardmod');

  my $p = $self->dbPostGet(tid => $tid, results => 25, page => $page);
  return 404 if !$p->[0];

  $self->htmlHeader(title => $t->{title});

  div class => 'mainbox';
   h1 $t->{title};
   h2 'Posted in';
   ul;
    for (sort { $a->{type}.$a->{iid} cmp $b->{type}.$b->{iid} } @{$t->{tags}}) {
      li;
       a href => "/t/$_->{type}", $self->{discussion_tags}{$_->{type}};
       if($_->{iid}) {
         txt ' > ';
         a style => 'font-weight: bold', href => "/t/$_->{type}$_->{iid}", "$_->{type}$_->{iid}";
         txt ':';
         a href => "/$_->{type}$_->{iid}", title => $_->{original}, $_->{title};
       }
      end;
    }
   end;
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
        i class => 'lastmod', 'Last modified on '.date($_->{edited}, 'full') if $_->{edited};
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


sub tagbrowse {
  my($self, $type, $iid) = @_;
  $iid ||= '';
  return 404 if $type =~ /(db|an)/ && $iid;

  my $f = $self->formValidate(
    { name => 'p', required => 0, default => 1, template => 'int' },
  );
  return 404 if $f->{_err};

  my $obj = !$iid ? undef :
    $type eq 'u' ? $self->dbUserGet(uid => $iid)->[0] :
    $type eq 'p' ? $self->dbProducerGet(id => $iid)->[0] :
                   undef; # get VN obj here
  return 404 if $iid && !$obj;
  my $ititle = $obj && ($obj->{title}||$obj->{name}||$obj->{username});
  my $title = !$obj ? $self->{discussion_tags}{$type} : 'Related discussions for '.$ititle;

  my($list, $np) = $self->dbThreadGet(
    type => $type,
    $iid ? (iid => $iid) : (),
    results => 50,
    page => $f->{p},
    what => 'firstpost lastpost tagtitles',
    order => $type eq 'an' ? 't.id DESC' : 'tpl.date DESC',
  );

  $self->htmlHeader(title => $title);

  $self->htmlMainTabs($type, $obj, 'disc') if $iid && $type ne 'u';
  div class => 'mainbox';
   h1 $title;
   p;
    a href => '/t', 'Discussion board';
    txt ' > ';
    a href => "/t/$type", $self->{discussion_tags}{$type};
    if($iid) {
      txt ' > ';
      a style => 'font-weight: bold', href => "/t/$type$iid", "$type$iid";
      txt ':';
      a href => "/$type$iid", $ititle;
    }
    if(!@$list) {
      h2 'No related threads found';
    }
   end;
  end;

  $self->htmlBrowse(
    items    => $list,
    options  => $f,
    nextpage => $np,
    pageurl  => "/t/$type$iid",
    class    => 'discussions',
    header   => [
      [ 'Topic' ], [ 'Replies' ], [ 'Starter' ], [ 'Last post' ]
    ],
    row      => sub {
      my($self, $n, $o) = @_;
      Tr $n % 2 ? ( class => 'odd' ) : ();
       td class => 'tc1';
        a href => "/t$o->{id}", shorten $o->{title}, 50;
       end;
       td class => 'tc2', $o->{count}-1;
       td class => 'tc3';
        lit userstr $o->{fuid}, $o->{fusername};
       end;
       td class => 'tc4', rowspan => 2;
        lit userstr $o->{luid}, $o->{lusername};
        lit '<br />@ ';
        a href => "/t$o->{id}.$o->{count}";
         lit date $o->{ldate};
        end;
       end;
      end;
      Tr $n % 2 ? ( class => 'odd' ) : ();
       td colspan => 3, class => 'tags';
        txt ' > ';
        for(@{$o->{tags}}) {
          a href => "/t/$_->{type}".($_->{iid}||''),
            title => $_->{original}||$self->{discussion_tags}{$_->{type}},
            shorten $_->{title}||$self->{discussion_tags}{$_->{type}}, 30;
          txt ', ' if $_ != $o->{tags}[$#{$o->{tags}}];
        }
       end;
      end;
    }
  ) if @$list;

  $self->htmlFooter;
}


1;

