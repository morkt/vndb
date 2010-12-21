
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
  qr{g/links},              \&taglinks,
  qr{v([1-9]\d*)/tagmod},   \&vntagmod,
  qr{u([1-9]\d*)/tags},     \&usertags,
  qr{g},                    \&tagindex,
  qr{g/debug},              \&fulltree,
  qr{xml/tags\.xml},        \&tagxml,
);


sub tagpage {
  my($self, $tag) = @_;

  my $t = $self->dbTagGet(id => $tag, what => 'parents(0) childs(2) aliases')->[0];
  return 404 if !$t;

  my $f = $self->formValidate(
    { name => 's', required => 0, default => 'tagscore', enum => [ qw|title rel pop tagscore rating| ] },
    { name => 'o', required => 0, default => 'd', enum => [ 'a','d' ] },
    { name => 'p', required => 0, default => 1, template => 'int' },
    { name => 'm', required => 0, default => -1, enum => [qw|0 1 2|] },
  );
  return 404 if $f->{_err};
  my $tagspoil = $self->reqCookie($self->{cookie_prefix}.'tagspoil');
  $f->{m} = $tagspoil =~ /^[0-2]$/ ? $tagspoil : 0 if $f->{m} == -1;

  my($list, $np) = $t->{meta} || $t->{state} != 2 ? ([],0) : $self->dbVNGet(
    what => 'rating',
    results => 50,
    page => $f->{p},
    sort => $f->{s}, reverse => $f->{o} eq 'd',
    tagspoil => $f->{m},
    tag_inc => $tag,
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
    my @p = _parenttags(@{$t->{parents}});
    for my $p (@p ? @p : []) {
      a href => '/g', mt '_tagp_indexlink';
      for (reverse @$p) {
        txt ' > ';
        a href => "/g$_->{id}", $_->{name};
      }
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

  if(!$t->{meta} && $t->{state} == 2) {
    div class => 'mainbox';
     a class => 'addnew', href => "/g/links?t=$tag", mt '_tagp_rawvotes';
     h1 mt '_tagp_vnlist';
     p class => 'browseopts';
      a href => "/g$t->{id}?m=0", $f->{m} == 0 ? (class => 'optselected') : (), onclick => "setCookie('tagspoil', 0);return true;", mt '_tagp_spoil0';
      a href => "/g$t->{id}?m=1", $f->{m} == 1 ? (class => 'optselected') : (), onclick => "setCookie('tagspoil', 1);return true;", mt '_tagp_spoil1';
      a href => "/g$t->{id}?m=2", $f->{m} == 2 ? (class => 'optselected') : (), onclick => "setCookie('tagspoil', 2);return true;", mt '_tagp_spoil2';
     end;
     p "\n\n".mt '_tagp_novn' if !@$list;
     p "\n".mt '_tagp_cached';
    end;
    $self->htmlBrowseVN($list, $f, $np, "/g$t->{id}?m=$f->{m}", 1) if @$list;
  }

  $self->htmlFooter;
}


# arg: tag hashref
# returns: [ [ tag1, tag2, tag3 ], [ tag1, tag2, tag5 ] ]
sub _parenttags {
  my @r;
  for my $t (@_) {
    for (@{$t->{'sub'}}) {
      push @r, [ $t, @$_ ] for _parenttags($_);
    }
    push @r, [$t] if !@{$t->{'sub'}};
  }
  return @r;
}


# used for on both /g and /g+
sub _childtags {
  my($self, $t, $index) = @_;

  div class => 'mainbox';
   h1 mt $index ? '_tagp_tree' : '_tagp_childs';
   ul class => 'tagtree';
    for my $p (sort { @{$b->{'sub'}} <=> @{$a->{'sub'}} } @{$t->{childs}}) {
      li;
       a href => "/g$p->{id}", $p->{name};
       b class => 'grayedout', " ($p->{c_vns})" if $p->{c_vns};
       end, next if !@{$p->{'sub'}};
       ul;
        for (0..$#{$p->{'sub'}}) {
          last if $_ >= 5 && @{$p->{'sub'}} > 6;
          li;
           txt '> ';
           a href => "/g$p->{sub}[$_]{id}", $p->{'sub'}[$_]{name};
           b class => 'grayedout', " ($p->{sub}[$_]{c_vns})" if $p->{'sub'}[$_]{c_vns};
          end;
        }
        if(@{$p->{'sub'}} > 6) {
          li;
           txt '> ';
           a href => "/g$p->{id}", style => 'font-style: italic', mt '_tagp_moretags', @{$p->{'sub'}}-5;
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
    return if !$self->authCheckCode;
    $frm = $self->formValidate(
      { name => 'name',        required => 1, maxlength => 250, regex => [ qr/^[^,]+$/, 'A comma is not allowed in tag names' ] },
      { name => 'state',       required => 0, default => 0,  enum => [ 0..2 ] },
      { name => 'meta',        required => 0, default => 0 },
      { name => 'alias',       required => 0, maxlength => 1024, default => '', regex => [ qr/^[^,]+$/s, 'No comma allowed in aliases' ]  },
      { name => 'description', required => 0, maxlength => 10240, default => '' },
      { name => 'parents',     required => !$self->authCan('tagmod'), default => '' },
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
    sort => $f->{s}, reverse => $f->{o} eq 'd',
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


sub taglinks {
  my $self = shift;

  my $f = $self->formValidate(
    { name => 'p', required => 0, default => 1, template => 'int' },
    { name => 'o', required => 0, default => 'd', enum => ['a', 'd'] },
    { name => 's', required => 0, default => 'date', enum => [qw|date username title tag|] },
    { name => 'v', required => 0, default => 0, template => 'int' },
    { name => 'u', required => 0, default => 0, template => 'int' },
    { name => 't', required => 0, default => 0, template => 'int' },
  );
  return 404 if $f->{_err};

  my($list, $np) = $self->dbTagLinks(
    what => 'details',
    results => 50,
    page => $f->{p},
    sort => $f->{s},
    reverse => $f->{o} eq 'd',
    $f->{v} ? (vid => $f->{v}) : (),
    $f->{u} ? (uid => $f->{u}) : (),
    $f->{t} ? (tag => $f->{t}) : (),
  );

  my $url = sub {
    my %f = ((map +($_,$f->{$_}), qw|s o v u t|), @_);
    my $qs = join ';', map $f{$_}?"$_=$f{$_}":(), keys %f;
    return '/g/links'.($qs?"?$qs":'')
  };

  $self->htmlHeader(noindex => 1, title => mt '_taglink_title');
  div class => 'mainbox';
   h1 mt '_taglink_title';

   div class => 'warning';
    h2 mt '_taglink_spoil_title';
    p mt '_taglink_spoil_msg';
   end;
   br;

   if($f->{u} || $f->{t} || $f->{v}) {
     p mt '_taglink_fil_active';
     ul;
      if($f->{u}) {
        my $o = $self->dbUserGet(uid => $f->{u})->[0];
        li;
         txt '['; a href => $url->(u=>0), mt '_taglink_fil_remove'; txt '] ';
         txt mt '_taglink_fil_user'; txt ' ';
         a href => "/u$o->{id}", $o->{username};
        end;
      }
      if($f->{t}) {
        my $o = $self->dbTagGet(id => $f->{t})->[0];
        li;
         txt '['; a href => $url->(t=>0), mt '_taglink_fil_remove'; txt '] ';
         txt mt '_taglink_fil_tag'; txt ' ';
         a href => "/g$o->{id}", $o->{name};
        end;
      }
      if($f->{v}) {
        my $o = $self->dbVNGet(id => $f->{v})->[0];
        li;
         txt '['; a href => $url->(v=>0), mt '_taglink_fil_remove'; txt '] ';
         txt mt '_taglink_fil_vn'; txt ' ';
         a href => "/v$o->{id}", $o->{title};
        end;
      }
     end;
   }
   p mt '_taglink_fil_add' unless $f->{v} && $f->{u} && $f->{t};
  end;

  $self->htmlBrowse(
    class    => 'taglinks',
    options  => $f,
    nextpage => $np,
    items    => $list,
    pageurl  => $url->(),
    sorturl  => $url->(s=>0,o=>0),
    header   => [
      [ mt('_taglink_col_date'),   'date' ],
      [ mt('_taglink_col_user'),   'username' ],
      [ mt('_taglink_col_rating') ],
      [ mt('_taglink_col_tag'),    'tag' ],
      [ mt('_taglink_col_spoiler') ],
      [ mt('_taglink_col_vn'),     'title' ],
    ],
    row      => sub {
      my($s, $n, $l) = @_;
      Tr $n % 2 ? (class => 'odd') : ();
       td class => 'tc1';
        lit $self->{l10n}->date($l->{date});
       end;
       td class => 'tc2';
        a href => $url->(u=>$l->{uid}), class => 'setfil', '> ' if !$f->{u};
        a href => "/u$l->{uid}", $l->{username};
       end;
       td class => 'tc3';
        tagscore $l->{vote};
       end;
       td class => 'tc4';
        a href => $url->(t=>$l->{tag}), class => 'setfil', '> ' if !$f->{t};
        a href => "/g$l->{tag}", $l->{name};
       end;
       td class => 'tc5', !defined $l->{spoiler} ? ' ' : mt "_taglink_spoil$l->{spoiler}";
       td class => 'tc6';
        a href => $url->(v=>$l->{vid}), class => 'setfil', '> ' if !$f->{v};
        a href => "/v$l->{vid}", shorten $l->{title}, 50;
       end;
      end;
    },
  );
  $self->htmlFooter;
}


sub vntagmod {
  my($self, $vid) = @_;

  my $v = $self->dbVNGet(id => $vid)->[0];
  return 404 if !$v || $v->{hidden};

  return $self->htmlDenied if !$self->authCan('tag');

  if($self->reqMethod eq 'POST') {
    return if !$self->authCheckCode;
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
  $self->htmlHeader(title => $title, noindex => 1);
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
      table class => 'tgl';
       thead;
        Tr;
         td '';
         td colspan => 2, class => 'tc_you', mt '_tagv_col_you';
         td colspan => 3, class => 'tc_others', mt '_tagv_col_others';
        end;
        Tr;
         td class => 'tc_tagname',  mt '_tagv_col_tag';
         td class => 'tc_myvote',   mt '_tagv_col_rating';
         td class => 'tc_myspoil',  mt '_tagv_col_spoiler';
         td class => 'tc_allvote',  mt '_tagv_col_rating';
         td class => 'tc_allspoil', mt '_tagv_col_spoiler';
         td class => 'tc_allwho',   '';
        end;
       end;
       tfoot; Tr;
        td colspan => 6;
         input type => 'submit', class => 'submit', value => mt('_tagv_save'), style => 'float: right';
         input id => 'tagmod_tag', type => 'text', class => 'text', value => '';
         input id => 'tagmod_add', type => 'button', class => 'submit', value => mt '_tagv_add';
         br;
         p;
          lit mt '_tagv_addmsg';
         end;
        end;
       end; end;
       tbody id => 'tagtable';
        for my $t (sort { $a->{name} cmp $b->{name} } @$tags) {
          my $m = (grep $_->{tag} == $t->{id}, @$my)[0] || {};
          Tr id => "tgl_$t->{id}";
           td class => 'tc_tagname'; a href => "/g$t->{id}", $t->{name}; end;
           td class => 'tc_myvote',  $m->{vote}||0;
           td class => 'tc_myspoil', defined $m->{spoiler} ? $m->{spoiler} : -1;
           td class => 'tc_allvote';
            tagscore !$m->{vote} ? $t->{rating} : $t->{cnt} == 1 ? 0 : ($t->{rating}*$t->{cnt} - $m->{vote}) / ($t->{cnt}-1);
            i ' ('.($t->{cnt} - ($m->{vote} ? 1 : 0)).')';
           end;
           td class => 'tc_allspoil', sprintf '%.2f', $t->{spoiler};
           td class => 'tc_allwho';
            a href => "/g/links?v=$vid;t=$t->{id}", mt '_tagv_who';
           end;
          end;
        }
       end;
      end;
    } ],
  ]);
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

  my $t = $self->dbTagTree(0, 2);
  _childtags($self, {childs => $t}, 1);

  table class => 'mainbox threelayout';
   Tr;

    # Recently added
    td;
     a class => 'right', href => '/g/list', mt '_tagidx_browseall';
     my $r = $self->dbTagGet(sort => 'added', reverse => 1, results => 10, state => 2);
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
     a class => 'addnew', href => "/g/links", mt '_tagidx_rawtags';
     $r = $self->dbTagGet(sort => 'vns', reverse => 1, meta => 0, results => 10);
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
     $r = $self->dbTagGet(state => 0, sort => 'added', reverse => 1, results => 10);
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


# non-translatable debug page
sub fulltree {
  my $self = shift;
  return $self->htmlDenied if !$self->authCan('tagmod');

  my $e;
  $e = sub {
    my $lst = shift;
    ul style => 'list-style-type: none; margin-left: 15px';
     for (@$lst) {
       li;
        txt '> ';
        a href => "/g$_->{id}", $_->{name};
        b class => 'grayedout', " ($_->{c_vns})" if $_->{c_vns};
       end;
       $e->($_->{sub}) if $_->{sub};
     }
    end;
  };

  my $tags = $self->dbTagTree(0, 25);
  $self->htmlHeader(title => '[DEBUG] Tag tree', noindex => 1);
  div class => 'mainbox';
   h1 '[DEBUG] Tag tree';
   $e->($tags);
  end;
  $self->htmlFooter;
}


sub tagxml {
  my $self = shift;

  my $f = $self->formValidate(
    { name => 'q', required => 0, maxlength => 500 },
    { name => 'id', required => 0, multi => 1, template => 'int' },
  );
  return 404 if $f->{_err} || (!$f->{q} && !$f->{id} && !$f->{id}[0]);

  my($list, $np) = $self->dbTagGet(
    !$f->{q} ? () : $f->{q} =~ /^g([1-9]\d*)/ ? (id => $1) : $f->{q} =~ /^name:(.+)$/ ? (name => $1) : (search => $f->{q}),
    $f->{id} && $f->{id}[0] ? (id => $f->{id}) : (),
    results => 15,
    page => 1,
  );

  $self->resHeader('Content-type' => 'text/xml; charset=UTF-8');
  xml;
  tag 'tags', more => $np ? 'yes' : 'no', $f->{q} ? (query => $f->{q}) : ();
   for(@$list) {
     tag 'item', id => $_->{id}, meta => $_->{meta} ? 'yes' : 'no', state => $_->{state}, $_->{name};
   }
  end;
}


1;
