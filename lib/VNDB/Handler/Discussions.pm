
package VNDB::Handler::Discussions;

use strict;
use warnings;
use YAWF ':html', 'xml_escape';
use POSIX 'ceil';
use VNDB::Func;


YAWF::register(
  qr{t([1-9]\d*)(?:/([1-9]\d*))?}    => \&thread,
  qr{t([1-9]\d*)\.([1-9]\d*)}        => \&redirect,
  qr{t/(db|an|[vpu])([1-9]\d*)?}     => \&board,
  qr{t([1-9]\d*)/reply}              => \&edit,
  qr{t([1-9]\d*)\.([1-9]\d*)/edit}   => \&edit,
  qr{t/(db|an|[vpu])([1-9]\d*)?/new} => \&edit,
  qr{t}                              => \&index,
);


sub thread {
  my($self, $tid, $page) = @_;
  $page ||= 1;

  my $t = $self->dbThreadGet(id => $tid, what => 'boardtitles')->[0];
  return 404 if !$t->{id} || $t->{hidden} && !$self->authCan('boardmod');

  my $p = $self->dbPostGet(tid => $tid, results => 25, page => $page, what => 'user');
  return 404 if !$p->[0];

  $self->htmlHeader(title => $t->{title});

  div class => 'mainbox';
   h1 $t->{title};
   h2 'Posted in';
   ul;
    for (sort { $a->{type}.$a->{iid} cmp $b->{type}.$b->{iid} } @{$t->{boards}}) {
      li;
       a href => "/t/$_->{type}", $self->{discussion_boards}{$_->{type}};
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
      my $class = $i % 2 ? 'odd ' : '';
      $class .= 'deleted' if $_->{hidden};
      Tr class => $class;
       td class => 'tc1';
        a href => "/t$tid.$_->{num}", name => $_->{num}, "#$_->{num}";
        if(!$_->{hidden}) {
          txt ' by ';
          lit userstr $_;
          br;
          lit date $_->{date}, 'full';
        }
       end;
       td class => 'tc2';
        if($self->authCan('boardmod') || $self->authInfo->{id} && $_->{uid} == $self->authInfo->{id} && !$_->{hidden}) {
          i class => 'edit';
           txt '< ';
           a href => "/t$tid.$_->{num}/edit", 'edit';
           txt ' >';
          end;
        }
        if($_->{hidden}) {
          i class => 'deleted', 'Post deleted.';
        } else {
          lit bb2html $_->{msg};
          i class => 'lastmod', 'Last modified on '.date($_->{edited}, 'full') if $_->{edited};
        }
       end;
      end;
    }
   end;
  end;
  $self->htmlBrowseNavigate("/t$tid/", $page, $t->{count} > $page*25, 'b', 1);

  if($t->{locked}) {
    div class => 'mainbox';
     h1 'Reply';
     p class => 'center', 'This thread has been locked, you can\'t reply to it anymore.';
    end;
  } elsif($t->{count} <= $page*25 && $self->authCan('board')) {
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


# Arguments, action
#  tid          reply
#  tid, 1       edit thread
#  tid, num     edit post
#  type, (iid)  start new thread
sub edit {
  my($self, $tid, $num) = @_;
  $num ||= 0;

  # in case we start a new thread, parse boards
  my $board = '';
  if($tid !~ /^\d+$/) {
    return 404 if $tid =~ /(db|an)/ && $num || $tid =~ /[vpu]/ && !$num;
    $board = $tid.($num||'');
    $tid = 0;
    $num = 0;
  }

  # get thread and post, if any
  my $t = $tid && $self->dbThreadGet(id => $tid, what => 'boards')->[0];
  return 404 if $tid && !$t->{id};

  my $p = $num && $self->dbPostGet(tid => $tid, num => $num, what => 'user')->[0];
  return 404 if $num && !$p->{num};

  # are we allowed to perform this action?
  return $self->htmlDenied if !$self->authCan('board')
    || ($tid && ($t->{locked} || $t->{hidden}) && !$self->authCan('boardmod'))
    || ($num && $p->{uid} != $self->authInfo->{id} && !$self->authCan('boardmod'));

  # check form etc...
  my $frm;
  if($self->reqMethod eq 'POST') {
    $frm = $self->formValidate(
      !$tid || $num == 1 ? (
        { name => 'title', maxlength => 50 },
        { name => 'boards', maxlength => 50 },
      ) : (),
      $self->authCan('boardmod') ? (
        { name => 'locked', required => 0 },
        { name => 'hidden', required => 0 },
        { name => 'nolastmod', required => 0 },
      ) : (),
      { name => 'msg', maxlenght => 5000 },
    );

    # check for double-posting
    push @{$frm->{_err}}, 'doublepost' if $self->dbPostGet(
      uid => $self->authInfo->{id}, tid => $tid, mindate => time - 30, results => 1, $tid ? () : (num => 1))->[0]{num};

    # parse and validate the boards
    my @boards;
    if(!$frm->{_err} && $frm->{boards}) {
      for (split /[ ,]/, $frm->{boards}) {
        my($ty, $id) = ($1, $2) if /^([a-z]{1,2})([0-9]*)$/;
        push @boards, [ $ty, $id ];
        push @{$frm->{_err}}, [ 'boards', 'wrongboard', $_ ] if
             !$ty || !$self->{discussion_boards}{$ty}
          || $ty eq 'an' && ($id || !$self->authCan('boardmod'))
          || $ty eq 'db' && $id
          || $ty eq 'v'  && (!$id || !$self->dbVNGet(id => $id)->[0]{id})
          || $ty eq 'p'  && (!$id || !$self->dbProducerGet(id => $id)->[0]{id})
          || $ty eq 'u'  && (!$id || !$self->dbUserGet(uid => $id)->[0]{id});
      }
    }

    if(!$frm->{_err}) {
      my($ntid, $nnum) = ($tid, $num);

      # create/edit thread
      if(!$tid || $num == 1) {
        my %thread = (
          title => $frm->{title},
          boards => \@boards,
          hidden => $frm->{hidden},
          locked => $frm->{locked},
        );
        $self->dbThreadEdit($tid, %thread)  if $tid;
        $ntid = $self->dbThreadAdd(%thread) if !$tid;
      }

      # create/edit post
      my %post = (
        msg => $frm->{msg},
        hidden => $num != 1 && $frm->{hidden},
        lastmod => !$num || $frm->{nolastmod} ? 0 : time,
      );
      $self->dbPostEdit($tid, $num, %post)   if $num;
      $nnum = $self->dbPostAdd($ntid, %post) if !$num;

      return $self->resRedirect("/t$ntid".($nnum > 25 ? '/'.ceil($nnum/25) : '').'#'.$nnum, 'post');
    }
  }

  # fill out form if we have some data
  if($p) {
    $frm->{msg} ||= $p->{msg};
    $frm->{hidden} = $p->{hidden} if $num != 1 && !exists $frm->{hidden};
    if($num == 1) {
      $frm->{boards} ||= join ' ', sort map $_->[1]?$_->[0].$_->[1]:$_->[0], @{$t->{boards}};
      $frm->{title} ||= $t->{title};
      $frm->{locked}  = $t->{locked} if !exists $frm->{locked};
      $frm->{hidden}  = $t->{hidden} if !exists $frm->{hidden};
    }
  }
  $frm->{boards} ||= $board;
  $frm->{nolastmod} = 1 if $num && $self->authCan('boardmod') && !exists $frm->{nolastmod};

  # generate html
  my $title = !$tid ? 'Start new thread' :
              !$num ? 'Reply to '.$t->{title} :
                      'Edit post';
  my $url = !$tid ? "/t/$board/new" : !$num ? "/t$tid/reply" : "/t$tid.$num/edit";
  $self->htmlHeader(title => $title, noindex => 1);
  $self->htmlForm({ frm => $frm, action => $url }, $title => [
    [ static => label => 'Username', content => userstr($self->authInfo->{id}, $self->authInfo->{username}) ],
    !$tid || $num == 1 ? (
      [ input  => short => 'title', name => 'Thread title' ],
      [ input  => short => 'boards',  name => 'Board(s)' ],
      [ static => content => 'Read <a href="/d9.2">d9.2</a> for information about how to specify boards' ],
      $self->authCan('boardmod') ? (
        [ check => name => 'Locked', short => 'locked' ],
      ) : (),
    ) : (
      [ static => label => 'Topic', content => qq|<a href="/t$tid">|.xml_escape($t->{title}).'</a>' ],
    ),
    $self->authCan('boardmod') ? (
      [ check => name => 'Hidden', short => 'hidden' ],
      $num ? (
        [ check => name => 'Don\'t update last modified field', short => 'nolastmod' ],
      ) : (),
    ) : (),
    [ text   => name => 'Message', short => 'msg', rows => 10 ],
    [ static => content => 'See <a href="/d9.3">d9.3</a> for the allowed formatting codes' ],
  ]);
  $self->htmlFooter;
}


sub board {
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
                   $self->dbVNGet(id => $iid)->[0];
  return 404 if $iid && !$obj;
  my $ititle = $obj && ($obj->{title}||$obj->{name}||$obj->{username});
  my $title = !$obj ? $self->{discussion_boards}{$type} : 'Related discussions for '.$ititle;

  my($list, $np) = $self->dbThreadGet(
    type => $type,
    $iid ? (iid => $iid) : (),
    results => 50,
    page => $f->{p},
    what => 'firstpost lastpost boardtitles',
    order => $type eq 'an' ? 't.id DESC' : 'tpl.date DESC',
  );

  $self->htmlHeader(title => $title, noindex => !@$list);

  $self->htmlMainTabs($type, $obj, 'disc') if $iid;
  div class => 'mainbox';
   h1 $title;
   p;
    a href => '/t', 'Discussion board';
    txt ' > ';
    a href => "/t/$type", $self->{discussion_boards}{$type};
    if($iid) {
      txt ' > ';
      a style => 'font-weight: bold', href => "/t/$type$iid", "$type$iid";
      txt ':';
      a href => "/$type$iid", $ititle;
    }
   end;
   p class => 'center';
    if(!@$list) {
      b 'No related threads found';
      br; br;
      a href => "/t/$type$iid/new", 'Why not create one yourself?';
    } else {
      a href => '/t/'.($iid ? $type.$iid : 'db').'/new', 'Start a new thread';
    }
   end;
  end;

  _threadlist($self, $list, $f, $np, "/t/$type$iid") if @$list;

  $self->htmlFooter;
}


sub index {
  my $self = shift;

  $self->htmlHeader(title => 'Discussion board index');
  div class => 'mainbox';
   h1 'Discussion board index';
   p class => 'browseopts';
    a href => '/t/'.$_, $self->{discussion_boards}{$_}
      for (qw|an db v p u|);
   end;
  end;

  for (qw|an db v p u|) {
    my $list = $self->dbThreadGet(
      type => $_,
      results => 5,
      page => 1,
      what => 'firstpost lastpost boardtitles',
      order => 'tpl.date DESC',
    );
    h1 class => 'boxtitle';
     a href => "/t/$_", $self->{discussion_boards}{$_};
    end;
    _threadlist($self, $list, {p=>1}, 0, "/t");
  }

  $self->htmlFooter;
}


sub _threadlist {
  my($self, $list, $f, $np, $url) = @_;
  $self->htmlBrowse(
    items    => $list,
    options  => $f,
    nextpage => $np,
    pageurl  => $url,
    class    => 'discussions',
    header   => [
      [ 'Topic' ], [ 'Replies' ], [ 'Starter' ], [ 'Last post' ]
    ],
    row      => sub {
      my($self, $n, $o) = @_;
      Tr $n % 2 ? ( class => 'odd' ) : ();
       td class => 'tc1';
        a $o->{locked} ? ( class => 'locked' ) : (), href => "/t$o->{id}", shorten $o->{title}, 50;
       end;
       td class => 'tc2', $o->{count}-1;
       td class => 'tc3';
        lit userstr $o->{fuid}, $o->{fusername};
       end;
       td class => 'tc4';
        lit userstr $o->{luid}, $o->{lusername};
        lit ' @ ';
        a href => "/t$o->{id}.$o->{count}";
         lit date $o->{ldate};
        end;
       end;
      end;
      Tr $n % 2 ? ( class => 'odd' ) : ();
       td colspan => 4, class => 'boards';
        txt ' > ';
        my $i = 1;
        for(sort { $a->{type}.$a->{iid} cmp $b->{type}.$b->{iid} } @{$o->{boards}}) {
          last if $i++ > 5;
          txt ', ' if $i > 2;
          a href => "/t/$_->{type}".($_->{iid}||''),
            title => $_->{original}||$self->{discussion_boards}{$_->{type}},
            shorten $_->{title}||$self->{discussion_boards}{$_->{type}}, 30;
        }
        txt ', ...' if @{$o->{boards}} > 5;
       end;
      end;
    }
  );
}


1;

