
package VNDB::Handler::Discussions;

use strict;
use warnings;
use TUWF ':html', 'xml_escape', 'uri_escape';
use POSIX 'ceil';
use VNDB::Func;


TUWF::register(
  qr{t([1-9]\d*)(?:/([1-9]\d*))?}    => \&thread,
  qr{t([1-9]\d*)\.([1-9]\d*)}        => \&redirect,
  qr{t/(all|db|an|ge|[vpu])([1-9]\d*)?}  => \&board,
  qr{t([1-9]\d*)/reply}              => \&edit,
  qr{t([1-9]\d*)\.([1-9]\d*)/edit}   => \&edit,
  qr{t/(db|an|ge|[vpu])([1-9]\d*)?/new} => \&edit,
  qr{t/search}                       => \&search,
  qr{t}                              => \&index,
);


sub caneditpost {
  my($self, $post) = @_;
  return $self->authCan('boardmod') ||
    ($self->authInfo->{id} && $post->{uid} == $self->authInfo->{id} && !$post->{hidden} && time()-$post->{date} < $self->{board_edit_time})
}


sub thread {
  my($self, $tid, $page) = @_;
  $page ||= 1;

  my $t = $self->dbThreadGet(id => $tid, what => 'boardtitles')->[0];
  return $self->resNotFound if !$t->{id} || $t->{hidden} && !$self->authCan('boardmod');

  my $p = $self->dbPostGet(tid => $tid, results => 25, page => $page, what => 'user');
  return $self->resNotFound if !$p->[0];

  $self->htmlHeader(title => $t->{title}, noindex => 1);
  div class => 'mainbox';
   h1 $t->{title};
   h2 mt '_thread_postedin';
   ul;
    for (sort { $a->{type}.$a->{iid} cmp $b->{type}.$b->{iid} } @{$t->{boards}}) {
      li;
       a href => "/t/$_->{type}", mt "_dboard_$_->{type}";
       if($_->{iid}) {
         txt ' > ';
         a style => 'font-weight: bold', href => "/t/$_->{type}$_->{iid}", "$_->{type}$_->{iid}";
         txt ':';
         a href => "/$_->{type}$_->{iid}", title => $_->{original}, $_->{title};
       }
      end;
    }
   end;
  end 'div';

  $self->htmlBrowseNavigate("/t$tid/", $page, [ $t->{count}, 25 ], 't', 1);
  div class => 'mainbox thread';
   table class => 'stripe';
    for my $i (0..$#$p) {
      local $_ = $p->[$i];
      Tr $_->{deleted} ? (class => 'deleted') : ();
       td class => 'tc1';
        a href => "/t$tid.$_->{num}", name => $_->{num}, "#$_->{num}";
        if(!$_->{hidden}) {
          lit ' '.mt "_thread_byuser", $_;
          br;
          lit $self->{l10n}->date($_->{date}, 'full');
        }
       end;
       td class => 'tc2';
        if(caneditpost($self, $_)) {
          i class => 'edit';
           txt '< ';
           a href => "/t$tid.$_->{num}/edit", mt '_thread_editpost';
           txt ' >';
          end;
        }
        if($_->{hidden}) {
          i class => 'deleted', mt '_thread_deletedpost';
        } else {
          lit bb2html $_->{msg};
          i class => 'lastmod', mt '_thread_lastmodified', $_->{edited} if $_->{edited};
        }
       end;
      end;
    }
   end;
  end 'div';
  $self->htmlBrowseNavigate("/t$tid/", $page, [ $t->{count}, 25 ], 'b', 1);

  if($t->{locked}) {
    div class => 'mainbox';
     h1 mt '_thread_noreply_title';
     p class => 'center', mt '_thread_noreply_locked';
    end;
  } elsif($t->{count} <= $page*25 && $self->authCan('board')) {
    form action => "/t$tid/reply", method => 'post', 'accept-charset' => 'UTF-8';
     div class => 'mainbox';
      fieldset class => 'submit';
       input type => 'hidden', class => 'hidden', name => 'formcode', value => $self->authGetCode("/t$tid/reply");
       h2;
        txt mt '_thread_quickreply_title';
        b class => 'standout', ' ('.mt('_inenglish').')';
       end;
       textarea name => 'msg', id => 'msg', rows => 4, cols => 50, '';
       br;
       input type => 'submit', value => mt('_thread_quickreply_submit'), class => 'submit';
       input type => 'submit', value => mt('_thread_quickreply_full'), class => 'submit', name => 'fullreply';
      end;
     end;
    end 'form';
  } elsif(!$self->authCan('board')) {
    div class => 'mainbox';
     h1 mt '_thread_noreply_title';
     p class => 'center', mt '_thread_noreply_login';
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
    return $self->resNotFound if $tid =~ /(db|an|ge)/ && $num || $tid =~ /[vpu]/ && !$num;
    $board = $tid.($num||'');
    $tid = 0;
    $num = 0;
  }

  # get thread and post, if any
  my $t = $tid && $self->dbThreadGet(id => $tid, what => 'boards')->[0];
  return $self->resNotFound if $tid && !$t->{id};

  my $p = $num && $self->dbPostGet(tid => $tid, num => $num, what => 'user')->[0];
  return $self->resNotFound if $num && !$p->{num};

  # are we allowed to perform this action?
  return $self->htmlDenied if !$self->authCan('board')
    || ($tid && ($t->{locked} || $t->{hidden}) && !$self->authCan('boardmod'))
    || ($num && !caneditpost($self, $p));

  # check form etc...
  my $frm;
  if($self->reqMethod eq 'POST') {
    return if !$self->authCheckCode;
    $frm = $self->formValidate(
      !$tid || $num == 1 ? (
        { post => 'title', maxlength => 50 },
        { post => 'boards', maxlength => 50 },
      ) : (),
      $self->authCan('boardmod') ? (
        { post => 'locked', required => 0 },
        { post => 'hidden', required => 0 },
        { post => 'nolastmod', required => 0 },
      ) : (),
      { post => 'msg', maxlength => 32768 },
      { post => 'fullreply', required => 0 },
    );

    $frm->{_err} = 1 if $frm->{fullreply};

    # check for double-posting
    push @{$frm->{_err}}, 'doublepost' if !$num && !$frm->{_err} && $self->dbPostGet(
      uid => $self->authInfo->{id}, tid => $tid, mindate => time - 30, results => 1, $tid ? () : (num => 1))->[0]{num};

    # Don't allow regular users to create more than 10 threads a day
    push @{$frm->{_err}}, 'threadthrottle' if
      !$tid && !$self->authCan('boardmod') &&
      @{$self->dbPostGet(uid => $self->authInfo->{id}, mindate => time - 24*3600, num => 1)} >= 5;

    # parse and validate the boards
    my @boards;
    if(!$frm->{_err} && $frm->{boards}) {
      for (split /[ ,]/, $frm->{boards}) {
        my($ty, $id) = ($1, $2) if /^([a-z]{1,2})([0-9]*)$/;
        push @boards, [ $ty, $id ];
        push @{$frm->{_err}}, [ 'boards', 'wrongboard', $_ ] if
             !$ty || !grep($_ eq $ty, @{$self->{discussion_boards}})
          || $ty eq 'an' && ($id || !$self->authCan('boardmod'))
          || $ty eq 'db' && $id
          || $ty eq 'ge' && $id
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
        msg => $self->bbSubstLinks($frm->{msg}),
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
  delete $frm->{_err} unless ref $frm->{_err};
  $frm->{boards} ||= $board;

  # generate html
  my $url = !$tid ? "/t/$board/new" : !$num ? "/t$tid/reply" : "/t$tid.$num/edit";
  my $title = mt !$tid ? '_postedit_newthread' :
                 !$num ? ('_postedit_replyto', $t->{title}) :
                         '_postedit_edit';
  $self->htmlHeader(title => $title, noindex => 1);
  $self->htmlForm({ frm => $frm, action => $url }, 'postedit' => [$title,
    [ static => label => mt('_postedit_form_username'), content => $self->{l10n}->userstr($self->authInfo->{id}, $self->authInfo->{username}) ],
    !$tid || $num == 1 ? (
      [ input  => short => 'title', name => mt('_postedit_form_title') ],
      [ input  => short => 'boards',  name => mt('_postedit_form_boards') ],
      [ static => content => mt('_postedit_form_boards_info') ],
      $self->authCan('boardmod') ? (
        [ check => name => mt('_postedit_form_locked'), short => 'locked' ],
      ) : (),
    ) : (
      [ static => label => mt('_postedit_form_topic'), content => qq|<a href="/t$tid">|.xml_escape($t->{title}).'</a>' ],
    ),
    $self->authCan('boardmod') ? (
      [ check => name => mt('_postedit_form_hidden'), short => 'hidden' ],
      $num ? (
        [ check => name => mt('_postedit_form_nolastmod'), short => 'nolastmod' ],
      ) : (),
    ) : (),
    [ text   => name => mt('_postedit_form_msg').'<br /><b class="standout">'.mt('_inenglish').'</b>', short => 'msg', rows => 25, cols => 75 ],
    [ static => content => mt('_postedit_form_msg_format') ],
  ]);
  $self->htmlFooter;
}


sub board {
  my($self, $type, $iid) = @_;
  $iid ||= '';
  return $self->resNotFound if $type =~ /(db|an|ge|all)/ && $iid;

  my $f = $self->formValidate(
    { get => 'p', required => 0, default => 1, template => 'int' },
  );
  return $self->resNotFound if $f->{_err};

  my $obj = !$iid ? undef :
    $type eq 'u' ? $self->dbUserGet(uid => $iid, what => 'hide_list')->[0] :
    $type eq 'p' ? $self->dbProducerGet(id => $iid)->[0] :
                   $self->dbVNGet(id => $iid)->[0];
  return $self->resNotFound if $iid && !$obj;
  my $ititle = $obj && ($obj->{title}||$obj->{name}||$obj->{username});
  my $title = !$obj ? mt($type eq 'all' ? '_disboard_item_all' : "_dboard_$type") : mt '_disboard_item_title', $ititle;

  my($list, $np) = $self->dbThreadGet(
    $type ne 'all' ? (type => $type) : (),
    $iid ? (iid => $iid) : (),
    results => 50,
    page => $f->{p},
    what => 'firstpost lastpost boardtitles',
    sort => $type eq 'an' ? 'id' : 'lastpost', reverse => 1,
  );

  $self->htmlHeader(title => $title, noindex => 1, feeds => [ $type eq 'an' ? 'announcements' : 'posts' ]);

  $self->htmlMainTabs($type, $obj, 'disc') if $iid;
  div class => 'mainbox';
   h1 $title;
   p;
    a href => '/t', mt '_disboard_rootlink';
    txt ' > ';
    a href => "/t/$type", mt $type eq 'all' ? '_disboard_item_all' : "_dboard_$type";
    if($iid) {
      txt ' > ';
      a style => 'font-weight: bold', href => "/t/$type$iid", "$type$iid";
      txt ':';
      a href => "/$type$iid", $ititle;
    }
   end;
   p class => 'center';
    if(!@$list) {
      b mt '_disboard_nothreads';
      br; br;
      a href => "/t/$type$iid/new", mt '_disboard_createyourown';
    } else {
      a href => '/t/'.($iid ? $type.$iid : $type ne 'ge' ? 'db' : $type).'/new', mt '_disboard_startnew' if $type ne 'all';
    }
   end;
  end 'div';

  _threadlist($self, $list, $f, $np, "/t/$type$iid", $type.$iid) if @$list;

  $self->htmlFooter;
}


sub index {
  my $self = shift;

  $self->htmlHeader(title => mt('_disindex_title'), noindex => 1, feeds => [ 'posts', 'announcements' ]);
  form action => '/t/search', method => 'get';
   div class => 'mainbox';
    h1 mt '_disindex_title';
    fieldset class => 'search';
     input type => 'text', name => 'bq', id => 'bq', class => 'text';
     input type => 'submit', class => 'submit', value => mt '_searchbox_submit';
    end 'fieldset';
    p class => 'browseopts';
     a href => '/t/all', mt '_disboard_item_all';
     a href => '/t/'.$_, mt "_dboard_$_"
       for (@{$self->{discussion_boards}});
    end;
   end;
  end;

  for (@{$self->{discussion_boards}}) {
    my $list = $self->dbThreadGet(
      type => $_,
      results => /^(db|v|ge)$/ ? 10 : 5,
      page => 1,
      what => 'firstpost lastpost boardtitles',
      sort => 'lastpost', reverse => 1,
    );
    h1 class => 'boxtitle';
     a href => "/t/$_", mt "_dboard_$_";
    end;
    _threadlist($self, $list, {p=>1}, 0, "/t", $_);
  }

  $self->htmlFooter;
}


sub search {
  my $self = shift;

  my $frm = $self->formValidate(
    { get => 'bq', required => 0, maxlength => 100 },
    { get => 'b',  required => 0, multi => 1, enum => $self->{discussion_boards} },
    { get => 't',  required => 0 },
    { get => 'p',  required => 0, default => 1, template => 'int' },
  );
  return $self->resNotFound if $frm->{_err};

  $self->htmlHeader(title => mt('_dissearch_title'), noindex => 1);
  $self->htmlForm({ frm => $frm, action => '/t/search', method => 'get', nosubmit => 1 }, 'boardsearch' => [mt('_dissearch_title'),
    [ input  => short => 'bq', name => mt('_dissearch_query') ],
    [ check  => short => 't',  name => mt('_dissearch_titleonly') ],
    [ select => short => 'b',  name => mt('_dissearch_boards'), multi => 1, size => scalar @{$self->{discussion_boards}},
      options => [ map [$_,mt("_dboard_$_")], @{$self->{discussion_boards}} ] ],
    [ static => content => sub {
      input type => 'submit', class => 'submit', tabindex => 10, value => mt '_searchbox_submit';
    } ],
  ]);
  return $self->htmlFooter if !$frm->{bq};

  my %boards = map +($_,1), @{$frm->{b}};
  %boards = () if keys %boards == @{$self->{discussion_boards}};

  my($l, $np);
  if($frm->{t}) {
    ($l, $np) = $self->dbThreadGet(
      keys %boards ? ( type => [keys %boards] ) : (),
      search => $frm->{bq},
      results => 50,
      page => $frm->{p},
      what => 'firstpost lastpost boardtitles',
      sort => 'lastpost', reverse => 1,
    );
  } else {
    # TODO: Allow or-matching too. But what syntax?
    (my $ts = $frm->{bq}) =~ y{+|&:*()="';!?$%^\\[]{}<>~` }{ }s;
    $ts =~ s/ / & /g;
    $ts =~ y/-/!/;
    ($l, $np) = $self->dbPostGet(
      keys %boards ? ( type => [keys %boards] ) : (),
      search => $ts,
      results => 20,
      page => $frm->{p},
      hide => 1,
      what => 'thread user',
      sort => 'date', reverse => 1,
    );
  }

  my $url = '/t/search?'.join ';', 'bq='.uri_escape($frm->{bq}), $frm->{t} ? 't=1' : (), map "b=$_", keys %boards;
  if(!@$l) {
    div class => 'mainbox';
     h1 mt '_dissearch_noresults_title';
     p mt '_dissearch_noresults_msg';
    end;
  } elsif($frm->{t}) {
    _threadlist($self, $l, $frm, $np, $url, 'all');
  } else {
    $self->htmlBrowse(
      items    => $l,
      options  => $frm,
      nextpage => $np,
      pageurl  => $url,
      class    => 'postsearch',
      header   => [
        sub { td class => 'tc1_1', ''; td class => 'tc1_2', ''; },
        [ mt '_dissearch_col_date' ],
        [ mt '_dissearch_col_user' ],
        [ mt '_dissearch_col_msg' ],
      ],
      row     => sub {
        my($s, $n, $l) = @_;
        my $link = "/t$l->{tid}.$l->{num}";
        Tr;
         td class => 'tc1_1'; a href => $link, 't'.$l->{tid}; end;
         td class => 'tc1_2'; a href => $link, '.'.$l->{num}; end;
         td class => 'tc2', $self->{l10n}->date($l->{date});
         td class => 'tc3'; lit $self->{l10n}->userstr($l->{uid}, $l->{username}); end;
         td class => 'tc4';
          div class => 'title';
           a href => $link, $l->{title};
          end;
          # TODO: ts_headline() or something like it.
          div class => 'thread';
           lit bb2html($l->{msg}, 300);
          end;
         end;
        end;
      }
    );
  }
  $self->htmlFooter;
}


sub _threadlist {
  my($self, $list, $f, $np, $url, $board) = @_;
  $self->htmlBrowse(
    items    => $list,
    options  => $f,
    nextpage => $np,
    pageurl  => $url,
    class    => 'discussions',
    header   => [
      [ mt '_threadlist_col_topic'    ],
      [ mt '_threadlist_col_replies'  ],
      [ mt '_threadlist_col_starter'  ],
      [ mt '_threadlist_col_lastpost' ],
    ],
    row      => sub {
      my($self, $n, $o) = @_;
      Tr;
       td class => 'tc1';
        a $o->{locked} ? ( class => 'locked' ) : (), href => "/t$o->{id}", shorten $o->{title}, 50;
        b class => 'boards';
         my $i = 1;
         my @boards = sort { $a->{type}.$a->{iid} cmp $b->{type}.$b->{iid} } grep $_->{type}.($_->{iid}||'') ne $board, @{$o->{boards}};
         for(@boards) {
           last if $i++ > 4;
           txt ', ' if $i > 2;
           a href => "/t/$_->{type}".($_->{iid}||''),
             title => $_->{original}||mt("_dboard_$_->{type}"),
             shorten $_->{title}||mt("_dboard_$_->{type}"), 30;
         }
         txt ', ...' if @boards > 4;
        end;
       end;
       td class => 'tc2', $o->{count}-1;
       td class => 'tc3';
        lit $self->{l10n}->userstr($o->{fuid}, $o->{fusername});
       end;
       td class => 'tc4';
        lit $self->{l10n}->userstr($o->{luid}, $o->{lusername});
        lit ' @ ';
        a href => "/t$o->{id}.$o->{count}";
         lit $self->{l10n}->date($o->{ldate});
        end;
       end;
      end 'tr';
    }
  );
}


1;

