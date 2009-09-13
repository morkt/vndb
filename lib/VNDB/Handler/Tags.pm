
package VNDB::Handler::Tags;


use strict;
use warnings;
use YAWF ':html', ':xml';
use VNDB::Func;


YAWF::register(
  qr{g([1-9]\d*)},          \&tagpage,
  qr{g([1-9]\d*)/(edit)},   \&tagedit,
  qr{g([1-9]\d*)/(add)},    \&tagedit,
  qr{g/new},                \&tagedit,
  qr{g/list},               \&taglist,
  qr{v([1-9]\d*)/tagmod},   \&vntagmod,
  qr{u([1-9]\d*)/tags},     \&usertags,
  qr{g},                    \&tagindex,
  qr{xml/tags\.xml},        \&tagxml,
  qr{g/debug},              \&tagtree,
);


sub tagpage {
  my($self, $tag) = @_;

  my $t = $self->dbTagGet(id => $tag, what => 'parents(0) childs(2) aliases')->[0];
  return 404 if !$t;

  my $f = $self->formValidate(
    { name => 's', required => 0, default => 'score', enum => [ qw|score title rel pop| ] },
    { name => 'o', required => 0, default => 'd', enum => [ 'a','d' ] },
    { name => 'p', required => 0, default => 1, template => 'int' },
    { name => 'm', required => 0, default => -1, enum => [qw|0 1 2|] },
  );
  return 404 if $f->{_err};
  my $tagspoil = $self->reqCookie('tagspoil');
  $f->{m} = $tagspoil =~ /^[0-2]$/ ? $tagspoil : 1 if $f->{m} == -1;

  my($list, $np) = $t->{meta} || $t->{state} != 2 ? ([],0) : $self->dbTagVNs(
    tag => $tag,
    order => {score=>'tb.rating',title=>'vr.title',rel=>'v.c_released',pop=>'v.c_popularity'}->{$f->{s}}.($f->{o}eq'a'?' ASC':' DESC'),
    page => $f->{p},
    results => 50,
    maxspoil => $f->{m},
  );

  my $title = mt '_tagp_title', $t->{meta}?0:1, $t->{name};
  $self->htmlHeader(title => $title, noindex => $t->{state} != 2);
  $self->htmlMainTabs('g', $t);

  if($t->{state} != 2) {
    div class => 'mainbox';
     h1 $title;
     if($t->{state} == 1) {
       div class => 'warning';
        h2 mt '_tagp_del_title';
        p;
         lit mt '_tagp_del_msg';
        end;
       end;
     } else {
       div class => 'notice';
        h2 mt '_tagp_pending_title';
        p mt '_tagp_pending_msg';
       end;
     }
    end;
  }

  div class => 'mainbox';
   a class => 'addnew', href => "/g$tag/add", mt '_tagp_addchild' if $self->authCan('tag') && $t->{state} != 1;
   h1 $title;

   p;
    my @p = @{$t->{parents}};
    my @r;
    for (0..$#p) {
      if($_ && $p[$_-1]{lvl} < $p[$_]{lvl}) {
        pop @r for (1..($p[$_]{lvl}-$p[$_-1]{lvl}));
      }
      if($_ < $#p && $p[$_+1]{lvl} < $p[$_]{lvl}) {
        push @r, $p[$_];
      } elsif($#p == $_ || $p[$_+1]{lvl} >= $p[$_]{lvl}) {
        a href => '/g', mt '_tagp_indexlink';
        for ($p[$_], reverse @r) {
          txt ' > ';
          a href => "/g$_->{tag}", $_->{name};
        }
        txt " > $t->{name}\n";
      }
    }
    if(!@p) {
      a href => '/g', mt '_tagp_indexlink';
      txt " > $t->{name}\n";
    }
   end;

   if($t->{description}) {
     p class => 'description';
      lit bb2html $t->{description};
     end;
   }
   if(@{$t->{aliases}}) {
     p class => 'center';
      b mt('_tagp_aliases')."\n";
      txt "$_\n" for (@{$t->{aliases}});
     end;
   }
  end;

  _childtags($self, $t) if @{$t->{childs}};
  _vnlist($self, $t, $f, $list, $np) if !$t->{meta} && $t->{state} == 2;

  $self->htmlFooter;
}

# used for on both /g and /g+
sub _childtags {
  my($self, $t, $index) = @_;

  my @l = @{$t->{childs}};
  my @tags;
  for (0..$#l) {
    if($l[$_]{lvl} == $l[0]{lvl}) {
      $l[$_]{childs} = [];
      push @tags, $l[$_];
    } else {
      push @{$tags[$#tags]{childs}}, $l[$_];
    }
  }

  div class => 'mainbox';
   h1 mt $index ? '_tagp_tree' : '_tagp_childs';
   ul class => 'tagtree';
    for my $p (sort { @{$b->{childs}} <=> @{$a->{childs}} } @tags) {
      li;
       a href => "/g$p->{tag}", $p->{name};
       b class => 'grayedout', " ($p->{c_vns})" if $p->{c_vns};
       end, next if !@{$p->{childs}};
       ul;
        for (0..$#{$p->{childs}}) {
          last if $_ >= 5 && @{$p->{childs}} > 6;
          li;
           txt '> ';
           a href => "/g$p->{childs}[$_]{tag}", $p->{childs}[$_]{name};
           b class => 'grayedout', " ($p->{childs}[$_]{c_vns})" if $p->{childs}[$_]{c_vns};
          end;
        }
        if(@{$p->{childs}} > 6) {
          li;
           txt '> ';
           a href => "/g$p->{tag}", style => 'font-style: italic', mt '_tagp_moretags', @{$p->{childs}}-5;
          end;
        }
       end;
      end;
    }
   end;
   clearfloat;
   br;
  end;
}

sub _vnlist {
  my($self, $t, $f, $list, $np) = @_;
  div class => 'mainbox';
   h1 mt '_tagp_vnlist';
   p class => 'browseopts';
    a href => "/g$t->{id}?m=0", $f->{m} == 0 ? (class => 'optselected') : (), onclick => "setCookie('tagspoil', 0);return true;", mt '_tagp_spoil0';
    a href => "/g$t->{id}?m=1", $f->{m} == 1 ? (class => 'optselected') : (), onclick => "setCookie('tagspoil', 1);return true;", mt '_tagp_spoil1';
    a href => "/g$t->{id}?m=2", $f->{m} == 2 ? (class => 'optselected') : (), onclick => "setCookie('tagspoil', 2);return true;", mt '_tagp_spoil2';
   end;
   if(!@$list) {
     p "\n\n".mt '_tagp_novn';
   }
   p "\n".mt '_tagp_cached';
  end;
  return if !@$list;
  $self->htmlBrowse(
    class    => 'tagvnlist',
    items    => $list,
    options  => $f,
    nextpage => $np,
    pageurl  => "/g$t->{id}?m=$f->{m};o=$f->{o};s=$f->{s}",
    sorturl  => "/g$t->{id}?m=$f->{m}",
    header   => [
      [ mt('_tagp_vncol_score'), 'score' ],
      [ mt('_tagp_vncol_title'), 'title' ],
      [ '',                      0       ],
      [ '',                      0       ],
      [ mt('_tagp_vncol_rel'),   'rel'   ],
      [ mt('_tagp_vncol_pop'),   'pop'   ],
    ],
    row     => sub {
      my($s, $n, $l) = @_;
      Tr $n % 2 ? (class => 'odd') : ();
       td class => 'tc1';
        tagscore $l->{rating};
        i sprintf '(%d)', $l->{users};
       end;
       td class => 'tc2';
        a href => '/v'.$l->{vid}, title => $l->{original}||$l->{title}, shorten $l->{title}, 100;
       end;
       td class => 'tc3';
        $_ ne 'oth' && cssicon $_, mt "_plat_$_"
          for (sort split /\//, $l->{c_platforms});
       end;
       td class => 'tc4';
        cssicon "lang $_", mt "_lang_$_"
          for (reverse sort split /\//, $l->{c_languages});
       end;
       td class => 'tc5';
        lit $self->{l10n}->monthstr($l->{c_released});
       end;
       td class => 'tc6', sprintf '%.2f', $l->{c_popularity}*100;
      end;
    }
  );
}


sub tagedit {
  my($self, $tag, $act) = @_;

  my($frm, $par);
  if($act && $act eq 'add') {
    $par = $self->dbTagGet(id => $tag)->[0];
    return 404 if !$par;
    $frm->{parents} = $par->{name};
    $tag = undef;
  }

  return $self->htmlDenied if !$self->authCan('tag') || $tag && !$self->authCan('tagmod');

  my $t = $tag && $self->dbTagGet(id => $tag, what => 'parents(1) aliases addedby')->[0];
  return 404 if $tag && !$t;

  if($self->reqMethod eq 'POST') {
    $frm = $self->formValidate(
      { name => 'name',        required => 1, maxlength => 250, regex => [ qr/^[^,]+$/, 'A comma is not allowed in tag names' ] },
      { name => 'state',       required => 0, default => 0,  enum => [ 0..2 ] },
      { name => 'meta',        required => 0, default => 0 },
      { name => 'alias',       required => 0, maxlength => 1024, default => '', regex => [ qr/^[^,]+$/s, 'No comma allowed in aliases' ]  },
      { name => 'description', required => 0, maxlength => 1024, default => '' },
      { name => 'parents',     required => 0, default => '' },
      { name => 'merge',       required => 0, default => '' },
    );
    my @aliases = split /[\t\s]*\n[\t\s]*/, $frm->{alias};
    my @parents = split /[\t\s]*,[\t\s]*/, $frm->{parents};
    my @merge = split /[\t\s]*,[\t\s]*/, $frm->{merge};
    if(!$frm->{_err}) {
      my $c = $self->dbTagGet(name => $frm->{name}, noid => $tag);
      push @{$frm->{_err}}, [ 'name', 'tagexists', $c->[0] ] if @$c;
      for (@aliases) {
        $c = $self->dbTagGet(name => $_, noid => $tag);
        push @{$frm->{_err}}, [ 'alias', 'tagexists', $c->[0] ] if @$c;
      }
      for(@parents, @merge) {
        my $c = $self->dbTagGet(name => $_, noid => $tag);
        push @{$frm->{_err}}, [ 'parents', 'func', [ 0, mt '_tagedit_err_notfound', $_ ]] if !@$c;
        $_ = $c->[0]{id};
      }
    }
    if(!$frm->{_err}) {
      $frm->{state} = $frm->{meta} = 0 if !$self->authCan('tagmod');
      my %opts = (
        name => $frm->{name},
        state => $frm->{state},
        description => $frm->{description},
        meta => $frm->{meta}?1:0,
        aliases => \@aliases,
        parents => \@parents,
      );
      if(!$tag) {
        $tag = $self->dbTagAdd(%opts);
      } else {
        $self->dbTagEdit($tag, %opts, upddate => $frm->{state} == 2 && $t->{state} != 2);
      }
      $self->dbTagMerge($tag, @merge) if $self->authCan('tagmod') && @merge;
      $self->resRedirect("/g$tag", 'post');
      return;
    }
  }

  if($tag) {
    $frm->{$_} ||= $t->{$_} for (qw|name meta description state|);
    $frm->{alias} ||= join "\n", @{$t->{aliases}};
    $frm->{parents} ||= join ', ', map $_->{name}, @{$t->{parents}};
  }

  my $title = $par ? mt('_tagedit_title_add', $par->{name}) : $tag ? mt('_tagedit_title_edit', $t->{name}) : mt '_tagedit_title_new';
  $self->htmlHeader(title => $title, noindex => 1);
  $self->htmlMainTabs('g', $par || $t, 'edit') if $t || $par;

  if(!$self->authCan('tagmod')) {
    div class => 'mainbox';
     h1 mt '_tagedit_req_title';
     div class => 'notice';
      h2 mt '_tagedit_req_subtitle';
      p;
       lit mt '_tagedit_req_msg';
      end;
     end;
    end;
  }

  $self->htmlForm({ frm => $frm, action => $par ? "/g$par->{id}/add" : $tag ? "/g$tag/edit" : '/g/new' }, 'tagedit' => [ $title,
    [ input    => short => 'name',     name => mt '_tagedit_frm_name' ],
    $self->authCan('tagmod') ? (
      $tag ?
        [ static   => label => mt('_tagedit_frm_by'), content => $self->{l10n}->userstr($t->{addedby}, $t->{username}) ] : (),
      [ select   => short => 'state',    name => mt('_tagedit_frm_state'), options => [
        map [$_, mt '_tagedit_frm_state'.$_], 0..2 ] ],
      [ checkbox => short => 'meta',     name => mt '_tagedit_frm_meta' ],
      $tag ?
        [ static => content => mt '_tagedit_frm_meta_warn' ] : (),
    ) : (),
    [ textarea => short => 'alias',    name => mt('_tagedit_frm_alias'), cols => 30, rows => 4 ],
    [ textarea => short => 'description', name => mt '_tagedit_frm_desc' ],
    [ static   => content => mt '_tagedit_frm_desc_msg' ],
    [ input    => short => 'parents',  name => mt '_tagedit_frm_parents' ],
    [ static   => content => mt '_tagedit_frm_parents_msg' ],
    $self->authCan('tagmod') ? (
      [ part   => title => mt '_tagedit_frm_merge' ],
      [ input  => short => 'merge', name => mt '_tagedit_frm_merge_tags' ],
      [ static => content => mt '_tagedit_frm_merge_msg' ],
    ) : (),
  ]);
  $self->htmlFooter;
}


sub taglist {
  my $self = shift;

  my $f = $self->formValidate(
    { name => 's', required => 0, default => 'name', enum => ['added', 'name'] },
    { name => 'o', required => 0, default => 'a', enum => ['a', 'd'] },
    { name => 'p', required => 0, default => 1, template => 'int' },
    { name => 't', required => 0, default => -1, enum => [ -1..2 ] },
    { name => 'q', required => 0, default => '' },
  );
  return 404 if $f->{_err};

  my($t, $np) = $self->dbTagGet(
    order => $f->{s}.($f->{o}eq'd'?' DESC':' ASC'),
    page => $f->{p},
    results => 50,
    state => $f->{t},
    search => $f->{q}
  );

  $self->htmlHeader(title => mt '_tagb_title');
  div class => 'mainbox';
   h1 mt '_tagb_title';
   form action => '/g/list', 'accept-charset' => 'UTF-8', method => 'get';
    input type => 'hidden', name => 't', value => $f->{t};
    $self->htmlSearchBox('g', $f->{q});
   end;
   p class => 'browseopts';
    a href => "/g/list?q=$f->{q};t=-1", $f->{t} == -1 ? (class => 'optselected') : (), mt '_tagb_state-1';
    a href => "/g/list?q=$f->{q};t=0", $f->{t} == 0 ? (class => 'optselected') : (), mt '_tagb_state0';
    a href => "/g/list?q=$f->{q};t=1", $f->{t} == 1 ? (class => 'optselected') : (), mt '_tagb_state1';
    a href => "/g/list?q=$f->{q};t=2", $f->{t} == 2 ? (class => 'optselected') : (), mt '_tagb_state2';
   end;
   if(!@$t) {
     p mt '_tagb_noresults';
   }
  end;
  if(@$t) {
    $self->htmlBrowse(
      class    => 'taglist',
      options  => $f,
      nextpage => $np,
      items    => $t,
      pageurl  => "/g/list?t=$f->{t};q=$f->{q};s=$f->{s};o=$f->{o}",
      sorturl  => "/g/list?t=$f->{t};q=$f->{q}",
      header   => [
        [ mt('_tagb_col_added'), 'added' ],
        [ mt('_tagb_col_name'),  'name'  ],
      ],
      row => sub {
        my($s, $n, $l) = @_;
        Tr $n % 2 ? (class => 'odd') : ();
         td class => 'tc1', $self->{l10n}->age($l->{added});
         td class => 'tc3';
          a href => "/g$l->{id}", $l->{name};
          if($f->{t} == -1) {
            b class => 'grayedout', ' '.mt '_tagb_note_awaiting' if $l->{state} == 0;
            b class => 'grayedout', ' '.mt '_tagb_note_del' if $l->{state} == 1;
          }
         end;
        end;
      }
    );
  }
  $self->htmlFooter;
}


sub vntagmod {
  my($self, $vid) = @_;

  my $v = $self->dbVNGet(id => $vid)->[0];
  return 404 if !$v || $v->{hidden};

  return $self->htmlDenied if !$self->authCan('tag');

  if($self->reqMethod eq 'POST') {
    my $frm = $self->formValidate(
      { name => 'taglinks', required => 0, default => '', maxlength => 10240, regex => [ qr/^[1-9][0-9]*,-?[1-3],-?[0-2]( [1-9][0-9]*,-?[1-3],-?[0-2])*$/, 'meh' ] }
    );
    return 404 if $frm->{_err};
    $self->dbTagLinkEdit($self->authInfo->{id}, $vid, [ map [ split /,/ ], split / /, $frm->{taglinks}]);
  }

  my $my = $self->dbTagLinks(vid => $vid, uid => $self->authInfo->{id});
  my $tags = $self->dbTagStats(vid => $vid, results => 9999);

  my $frm;

  my $title = mt '_tagv_title', $v->{title};
  $self->htmlHeader(title => $title, noindex => 1, js => 'forms');
  $self->htmlMainTabs('v', $v, 'tagmod');
  div class => 'mainbox';
   h1 $title;
   div class => 'notice';
    h2 mt '_tagv_msg_title';
    ul;
     li; lit mt '_tagv_msg_guidelines'; end;
     li mt '_tagv_msg_submit';
     li mt '_tagv_msg_cache';
    end;
   end;
  end;
  $self->htmlForm({ frm => $frm, action => "/v$vid/tagmod", nosubmit => 1 }, tagmod => [ mt('_tagv_frm_title'),
    [ hidden => short => 'taglinks', value => '' ],
    [ static => nolabel => 1, content => sub {
      table id => 'tagtable';
       thead;
        Tr;
         td '';
         td colspan => 2, class => 'tc2_1', mt '_tagv_col_you';
         td colspan => 2, class => 'tc3_1', mt '_tagv_col_others';
        end;
        Tr;
         my $i=0;
         td class => 'tc'.++$i, mt '_tagv_col_'.$_ for(qw|tag rating spoiler rating spoiler|);
        end;
       end;
       tfoot; Tr;
        td colspan => 5;
         input type => 'submit', class => 'submit', value => mt('_tagv_save'), style => 'float: right';
         input type => 'text', class => 'text', name => 'addtag', value => '';
         input type => 'button', class => 'submit', value => mt '_tagv_add';
         br;
         p;
          lit mt '_tagv_addmsg';
         end;
        end;
       end; end;
       tbody;
        for my $t (sort { $a->{name} cmp $b->{name} } @$tags) {
          my $m = (grep $_->{tag} == $t->{id}, @$my)[0] || {};
          Tr;
           td class => 'tc1';
            a href => "/g$t->{id}", $t->{name};
           end;
           td class => 'tc2', $m->{vote}||0;
           td class => 'tc3', defined $m->{spoiler} ? $m->{spoiler} : -1;
           td class => 'tc4';
            tagscore !$m->{vote} ? $t->{rating} : $t->{cnt} == 1 ? 0 : ($t->{rating}*$t->{cnt} - $m->{vote}) / ($t->{cnt}-1);
            i ' ('.($t->{cnt} - ($m->{vote} ? 1 : 0)).')';
           end;
           td class => 'tc5', sprintf '%.2f', $t->{spoiler};
          end;
        }
       end;
      end;
    } ],
  ]);
  $self->htmlFooter;
}


sub usertags {
  my($self, $uid) = @_;

  my $u = $self->dbUserGet(uid => $uid)->[0];
  return 404 if !$u;

  my $f = $self->formValidate(
    { name => 's', required => 0, default => 'cnt', enum => [ qw|cnt name| ] },
    { name => 'o', required => 0, default => 'd', enum => [ 'a','d' ] },
    { name => 'p', required => 0, default => 1, template => 'int' },
  );
  return 404 if $f->{_err};

  # TODO: might want to use AJAX to load the VN list on request
  my($list, $np) = $self->dbTagStats(
    uid => $uid,
    page => $f->{p},
    order => ($f->{s}eq'cnt'?'COUNT(*)':'name').($f->{o}eq'a'?' ASC':' DESC'),
    what => 'vns',
  );

  my $title = mt '_tagu_title', $u->{username};
  $self->htmlHeader(title => $title, noindex => 1);
  $self->htmlMainTabs('u', $u, 'tags');
  div class => 'mainbox';
   h1 $title;
   if(@$list) {
     p mt '_tagu_spoilerwarn';
   } else {
     p mt '_tagu_notags', $u->{username};
   }
  end;

  if(@$list) {
    $self->htmlBrowse(
      class    => 'tagstats',
      options  => $f,
      nextpage => $np,
      items    => $list,
      pageurl  => "/u$u->{id}/tags?s=$f->{s};o=$f->{o}",
      sorturl  => "/u$u->{id}/tags",
      header   => [
        sub {
          td class => 'tc1';
           b id => 'relhidall';
            lit '<i>&#9656;</i> '.mt('_tagu_col_num').' ';
           end;
           lit $f->{s} eq 'cnt' && $f->{o} eq 'a' ? "\x{25B4}" : qq|<a href="/u$u->{id}/tags?o=a;s=cnt">\x{25B4}</a>|;
           lit $f->{s} eq 'cnt' && $f->{o} eq 'd' ? "\x{25BE}" : qq|<a href="/u$u->{id}/tags?o=d;s=cnt">\x{25BE}</a>|;
          end;
        },
        [ mt('_tagu_col_name'),  'name' ],
        [ ' ', '' ],
      ],
      row     => sub {
        my($s, $n, $l) = @_;
        Tr $n % 2 ? (class => 'odd') : ();
         td class => 'tc1 relhid_but', id => "tag$l->{id}";
          lit "<i>&#9656;</i> $l->{cnt}";
         end;
         td class => 'tc2', colspan => 2;
          a href => "/g$l->{id}", $l->{name};
         end;
        end;
        for(@{$l->{vns}}) {
          Tr class => "relhid tag$l->{id}";
           td class => 'tc1_1';
            tagscore $_->{vote};
           end;
           td class => 'tc1_2';
            a href => "/v$_->{vid}", title => $_->{original}||$_->{title}, shorten $_->{title}, 50;
           end;
           td class => 'tc1_3', !defined $_->{spoiler} ? ' ' : mt "_tagu_spoil$_->{spoiler}";
          end;
        }
      },
    );
  }
  $self->htmlFooter;
}


sub tagindex {
  my $self = shift;

  $self->htmlHeader(title => mt '_tagidx_title');
  div class => 'mainbox';
   a class => 'addnew', href => "/g/new", mt '_tagidx_create' if $self->authCan('tag');
   h1 mt '_tagidx_search';
   form action => '/g/list', 'accept-charset' => 'UTF-8', method => 'get';
    $self->htmlSearchBox('g', '');
   end;
  end;

  my $t = $self->dbTagTree(0, 2, 1);
  _childtags($self, {childs => $t}, 1);

  table class => 'mainbox threelayout';
   Tr;

    # Recently added
    td;
     a class => 'right', href => '/g/list', mt '_tagidx_browseall';
     my $r = $self->dbTagGet(order => 'added DESC', results => 10, state => 2);
     h1 mt '_tagidx_recent';
     ul;
      for (@$r) {
        li;
         txt $self->{l10n}->age($_->{added});
         txt ' ';
         a href => "/g$_->{id}", $_->{name};
        end;
      }
     end;
    end;

    # Popular
    td;
     $r = $self->dbTagGet(order => 'c_vns DESC', meta => 0, results => 10);
     h1 mt '_tagidx_popular';
     ul;
      for (@$r) {
        li;
         a href => "/g$_->{id}", $_->{name};
         txt " ($_->{c_vns})";
        end;
      }
     end;
    end;

    # Moderation queue
    td;
     h1 mt '_tagidx_queue';
     $r = $self->dbTagGet(state => 0, order => 'added DESC', results => 10);
     ul;
      li mt '_tagidx_queue_empty' if !@$r;
      for (@$r) {
        li;
         txt $self->{l10n}->age($_->{added});
         txt ' ';
         a href => "/g$_->{id}", $_->{name};
        end;
      }
      li;
       txt "\n";
       a href => '/g/list?t=0;o=d;s=added', mt '_tagidx_queue_link';
       txt ' - ';
       a href => '/g/list?t=1;o=d;s=added', mt '_tagidx_denied';
      end;
     end;
    end;

   end; # /tr
  end; # /table
  $self->htmlFooter;
}


sub tagxml {
  my $self = shift;

  my $q = $self->formValidate({ name => 'q', maxlength => 500 });
  return 404 if $q->{_err};
  $q = $q->{q};

  my($list, $np) = $self->dbTagGet(
    $q =~ /^g([1-9]\d*)/ ? (id => $1) : $q =~ /^name:(.+)$/ ? (name => $1) : (search => $q),
    results => 10,
    page => 1,
  );

  $self->resHeader('Content-type' => 'text/xml; charset=UTF-8');
  xml;
  tag 'tags', more => $np ? 'yes' : 'no', query => $q;
   for(@$list) {
     tag 'item', id => $_->{id}, meta => $_->{meta} ? 'yes' : 'no', state => $_->{state}, $_->{name};
   }
  end;
}


sub tagtree {
  my $self = shift;

  return 404 if !$self->authCan('tagmod');

  $self->htmlHeader(title => '[DEBUG] The complete tag tree');
  div class => 'mainbox';
   h1 '[DEBUG] The complete tag tree';

   div style => 'margin-left: 10px';
    my $t = $self->dbTagTree(0, -1, 1);
    my $lvl = $t->[0]{lvl} + 1;
    for (@$t) {
      map ul(style => 'margin-left: 15px; list-style-type: none'),  1..($lvl-$_->{lvl}) if $lvl > $_->{lvl};
      map end, 1..($_->{lvl}-$lvl) if $lvl < $_->{lvl};
      $lvl = $_->{lvl};
      li;
       txt '> ';
       a href => "/g$_->{tag}", $_->{name};
      end;
    }
    map end, 0..($t->[0]{lvl}-$lvl);
   end;
  end;
  $self->htmlFooter;
}


1;
