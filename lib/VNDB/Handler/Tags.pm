
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
);


sub tagpage {
  my($self, $tag) = @_;

  my $t = $self->dbTagGet(id => $tag, what => 'parents(0) childs(2) aliases')->[0];
  return 404 if !$t;

  my $f = $self->formValidate(
    { name => 's', required => 0, default => 'score', enum => [ qw|score title rel pop| ] },
    { name => 'o', required => 0, default => 'd', enum => [ 'a','d' ] },
    { name => 'p', required => 0, default => 1, template => 'int' },
    { name => 'm', required => 0, default => 1, enum => [qw|0 1 2|] },
  );
  return 404 if $f->{_err};

  my($list, $np) = $t->{meta} || $t->{state} != 2 ? ([],0) : $self->dbTagVNs(
    tag => $tag,
    order => {score=>'tb.rating',title=>'vr.title',rel=>'v.c_released',pop=>'v.c_popularity'}->{$f->{s}}.($f->{o}eq'a'?' ASC':' DESC'),
    page => $f->{p},
    results => 50,
    maxspoil => $f->{m},
  );

  my $title = ($t->{meta} ? 'Meta tag: ' : 'Tag: ').$t->{name};
  $self->htmlHeader(title => $title);
  $self->htmlMainTabs('g', $t);

  if($t->{state} != 2) {
    div class => 'mainbox';
     h1 "Tag: $t->{name}";
     if($t->{state} == 1) {
       div class => 'warning';
        h2 'Tag deleted';
        p;
         lit qq|This tag has been removed from the database, and cannot be used or re-added.|.
             qq| File a request on the <a href="/t/db">discussion board</a> if you disagree with this.|;
        end;
       end;
     } else {
       div class => 'notice';
        h2 'Waiting for approval';
        p 'This tag is waiting for a moderator to approve it. You can still use it to tag VNs as you would with a normal tag.';
       end;
     }
    end;
    return $self->htmlFooter if $t->{state} == 1 && !$self->authCan('tagmod');
  }

  div class => 'mainbox';
   a class => 'addnew', href => "/g$tag/add", ($self->authCan('tagmod')?'Create':'Request').' child tag' if $self->authCan('tag');
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
        a href => '/g', 'Tags';
        for ($p[$_], reverse @r) {
          txt ' > ';
          a href => "/g$_->{tag}", $_->{name};
        }
        txt " > $t->{name}\n";
      }
    }
    if(!@p) {
      a href => '/g', 'Tags';
      txt " > $t->{name}\n";
    }
   end;

   if($t->{description}) {
     p class => 'center';
      lit bb2html $t->{description};
     end;
   }
   if(@{$t->{aliases}}) {
     p class => 'center';
      b "Aliases:\n";
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
   if(!$index) {
     h1 'Child tags';
   } else {
     h1 'Tag tree';
   }
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
           a href => "/g$p->{tag}", style => 'font-style: italic', sprintf '%d more tags...', @{$p->{childs}}-5;
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
   h1 'Visual novels';
   p class => 'browseopts';
    a href => "/g$t->{id}?m=0", $f->{m} == 0 ? (class => 'optselected') : (), 'Hide spoilers';
    a href => "/g$t->{id}?m=1", $f->{m} == 1 ? (class => 'optselected') : (), 'Show minor spoilers';
    a href => "/g$t->{id}?m=2", $f->{m} == 2 ? (class => 'optselected') : (), 'Show major spoilers';
   end;
   if(!@$list) {
     p "\n\nThis tag has not been linked to any visual novels yet, or they were hidden because of the spoiler settings.";
   }
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
      [ 'Score',    'score' ],
      [ 'Title',    'title' ],
      [ '',         0       ],
      [ '',         0       ],
      [ 'Released', 'rel'   ],
      [ 'Popularity', 'pop' ],
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
        $_ ne 'oth' && cssicon $_, $self->{platforms}{$_}
          for (sort split /\//, $l->{c_platforms});
       end;
       td class => 'tc4';
        cssicon "lang $_", $self->{languages}{$_}
          for (reverse sort split /\//, $l->{c_languages});
       end;
       td class => 'tc5';
        lit monthstr $l->{c_released};
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
    $frm->{parents} = $tag;
    $tag = undef;
  }

  return $self->htmlDenied if !$self->authCan('tag') || $tag && !$self->authCan('tagmod');

  my $t = $tag && $self->dbTagGet(id => $tag, what => 'parents(1) aliases')->[0];
  return 404 if $tag && !$t;

  if($self->reqMethod eq 'POST') {
    $frm = $self->formValidate(
      { name => 'name',        required => 1, maxlength => 250 },
      { name => 'state',       required => 0, default => 0,  enum => [ 0..2 ] },
      { name => 'meta',        required => 0, default => 0 },
      { name => 'alias',       required => 0, maxlength => 1024, default => '' },
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
        push @{$frm->{_err}}, [ 'parents', 'func', [ 0, "Tag '$_' not found." ]] if !@$c;
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
        $self->multiCmd("ircnotify g$tag");
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

  my $title = $par ? "Add child tag to $par->{name}" : $tag ? "Edit tag: $t->{name}" : 'Add new tag';
  $self->htmlHeader(title => $title, noindex => 1);
  $self->htmlMainTabs('g', $par || $t, 'edit') if $t || $par;

  if(!$self->authCan('tagmod')) {
    div class => 'mainbox';
     h1 'Requesting new tag';
     div class => 'notice';
      h2 'Your tag must be approved';
      p 'Because all tags have to be approved by moderators, it can take a while before it '.
        'will show up in the tag list or on visual novel pages. You can still vote on tag even if '.
        'it has not been approved yet, though.';
     end;
    end;
  }

  $self->htmlForm({ frm => $frm, action => $par ? "/g$par->{id}/add" : $tag ? "/g$tag/edit" : '/g/new' }, $title => [
    [ input    => short => 'name',     name => 'Primary name' ],
    $self->authCan('tagmod') ? (
      [ select   => short => 'state',    name => 'State', options => [
        [ 0, 'Awaiting moderation' ], [ 1, 'Deleted/hidden' ], [ 2, 'Approved' ] ] ],
      [ checkbox => short => 'meta',     name => 'This is a meta-tag (only to be used as parent for other tags, not for linking to VN entries)' ],
      $tag ?
        [ static => content => 'WARNING: Checking this option or selecting "Deleted" as state will permanently delete all existing VN relations!' ] : (),
    ) : (),
    [ textarea => short => 'alias',    name => "Aliases\n(separated by newlines)", cols => 30, rows => 4 ],
    [ textarea => short => 'description', name => 'Description' ],
    [ static   => content => 'What should the tag be used for? Having a good description helps users choose which tags to link to a VN.' ],
    [ input    => short => 'parents',  name => 'Parent tags' ],
    [ static   => content => "Comma separated list of tag names to be used as parent for this tag." ],
    $self->authCan('tagmod') ? (
      [ part   => title => 'Merge tags' ],
      [ input  => short => 'merge', name => 'Tags to merge' ],
      [ static => content => 'Comma separated list of tag names to merge into this one.'
         .' All votes and aliases/names will be moved over to this tag, and the old tags will be deleted.'
         .' Just leave this field empty if you don\'t intend to do a merge.'
         .'<br />WARNING: this action cannot be undone!' ],
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
  $f->{t} = 0 if !$self->authCan('tagmod') && $f->{t} == 1;
  return 404 if $f->{_err};

  my($t, $np) = $self->dbTagGet(
    order => $f->{s}.($f->{o}eq'd'?' DESC':' ASC'),
    page => $f->{p},
    results => 50,
    $f->{t} != -1 || $self->authCan('tagmod') ? (
      state => $f->{t} ) : (),
    search => $f->{q},
  );

  my $title = $f->{t} == -1 ? 'Browse tags' : $f->{t} == 0 ? 'Tags awaiting moderation' : $f->{t} == 1 ? 'Deleted tags' : 'All visible tags';
  $self->htmlHeader(title => $title);
  div class => 'mainbox';
   h1 $title;
   form class => 'search', action => '/g/list', 'accept-charset' => 'UTF-8', method => 'get';
    fieldset;
     input type => 'hidden', name => 't', value => $f->{t};
     input type => 'text', name => 'q', id => 'q', class => 'text', value => $f->{q};
     input type => 'submit', class => 'submit', value => 'Search!';
    end;
   end;
   p class => 'browseopts';
    a href => "/g/list?q=$f->{q};t=-1", $f->{t} == -1 ? (class => 'optselected') : (), 'All';
    a href => "/g/list?q=$f->{q};t=0", $f->{t} == 0 ? (class => 'optselected') : (), 'Awaiting moderation';
    a href => "/g/list?q=$f->{q};t=1", $f->{t} == 1 ? (class => 'optselected') : (), 'Deleted' if $self->authCan('tagmod');
    a href => "/g/list?q=$f->{q};t=2", $f->{t} == 2 ? (class => 'optselected') : (), 'Accepted';
   end;
   if(!@$t) {
     p 'No results found';
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
        [ 'Created', 'added' ],
        [ 'Tag',     'name'  ],
      ],
      row => sub {
        my($s, $n, $l) = @_;
        Tr $n % 2 ? (class => 'odd') : ();
         td class => 'tc1', age $l->{added};
         td class => 'tc3';
          a href => "/g$l->{id}", $l->{name};
          if($f->{t} == -1) {
            b class => 'grayedout', ' awaiting moderation' if $l->{state} == 0;
            b class => 'grayedout', ' deleted' if $l->{state} == 1;
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
  return 404 if !$v;

  return $self->htmlDenied if !$self->authCan('tag');

  if($self->reqMethod eq 'POST') {
    my $frm = $self->formValidate(
      { name => 'taglinks', required => 0, default => '', maxlength => 10240, regex => [ qr/^[1-9][0-9]*,-?[1-3],-?[0-2]( [1-9][0-9]*,-?[1-3],-?[0-2])*$/, 'meh' ] }
    );
    return 404 if $frm->{_err};
    $self->dbTagLinkEdit($self->authInfo->{id}, $vid, [ map [ split /,/ ], split / /, $frm->{taglinks}]);
  }

  my $my = $self->dbTagLinks(vid => $vid, uid => $self->authInfo->{id});
  my $tags = $self->dbTagStats(vid => $vid, result => 9999);

  my $frm;

  $self->htmlHeader(title => "Add/remove tags for $v->{title}", noindex => 1, js => 'forms');
  $self->htmlMainTabs('v', $v, 'tagmod');
  div class => 'mainbox';
   h1 "Add/remove tags for $v->{title}";
   div class => 'notice';
    h2 'Tagging';
    ul;
     li "Don't forget to hit the submit button on the bottom of the page after changing anything here!";
     li 'Tag guidelines?';
     li 'Some tag information on the site is cached, it can take up to an hour for your changes to be visible everywhere.';
    end;
   end;
  end;
  $self->htmlForm({ frm => $frm, action => "/v$vid/tagmod", hitsubmit => 1 }, 'Tags' => [
    [ hidden => short => 'taglinks', value => '' ],
    [ static => nolabel => 1, content => sub {
      table id => 'tagtable';
       thead;
        Tr;
         td '';
         td colspan => 2, class => 'tc2_1', 'Others';
         td colspan => 2, class => 'tc3_1', 'You';
        end;
        Tr;
         my $i=0;
         td class => 'tc'.++$i, $_ for(qw|Tag Rating Spoiler Rating Spoiler|);
        end;
       end;
       tfoot; Tr;
        td colspan => 5;
         input type => 'text', class => 'text', name => 'addtag', value => '';
         input type => 'button', class => 'submit', value => 'Add tag';
         br;
         p;
          lit 'Check the <a href="/g">tag list</a> to browse all available tags.'.
              '<br />Can\'t find what you\'re looking for? <a href="/g/new">Request a new tag</a>.';
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
           td class => 'tc2';
            tagscore !$m->{vote} ? $t->{rating} : $t->{cnt} == 1 ? 0 : ($t->{rating}*$t->{cnt} - $m->{vote}) / ($t->{cnt}-1);
            i ' ('.($t->{cnt} - ($m->{vote} ? 1 : 0)).')';
           end;
           td class => 'tc3', sprintf '%.2f', $t->{spoiler};
           td class => 'tc4', $m->{vote}||0;
           td class => 'tc5', defined $m->{spoiler} ? $m->{spoiler} : -1;
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

  $self->htmlHeader(title => "Tags by $u->{username}", noindex => 1);
  $self->htmlMainTabs('u', $u, 'tags');
  div class => 'mainbox';
   h1 "Tags by $u->{username}";
   if(@$list) {
     p 'Warning: spoilery tags are not hidden in this list!';
   } else {
     p "$u->{username} doesn't seem to have used the tagging system yet...";
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
            lit '<i>&#9656;</i> #VNs ';
           end;
           lit $f->{s} eq 'cnt' && $f->{o} eq 'a' ? "\x{25B4}" : qq|<a href="/u$u->{id}/tags?o=a;s=cnt">\x{25B4}</a>|;
           lit $f->{s} eq 'cnt' && $f->{o} eq 'd' ? "\x{25BE}" : qq|<a href="/u$u->{id}/tags?o=d;s=cnt">\x{25BE}</a>|;
          end;
        },
        [ 'Tag',  'name' ],
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
           td class => 'tc1_3', !defined $_->{spoiler} ? ' ' : ['No spoiler', 'Minor spoiler', 'Major spoiler']->[$_->{spoiler}];
          end;
        }
      },
    );
  }
  $self->htmlFooter;
}


sub tagindex {
  my $self = shift;

  $self->htmlHeader(title => 'Browse tags');
  div class => 'mainbox';
   h1 'Search tags';
   form class => 'search', action => '/g/list', 'accept-charset' => 'UTF-8', method => 'get';
    fieldset;
     input type => 'text', name => 'q', id => 'q', class => 'text';
     input type => 'submit', class => 'submit', value => 'Search!';
    end;
   end;
  end;

  my $t = $self->dbTagTree(0, 2, 1);
  _childtags($self, {childs => $t}, 1);

  # Recently added
  div class => 'mainbox threelayout';
   a class => 'right', href => '/g/list', 'Browse all tags';
   my $r = $self->dbTagGet(order => 'added DESC', results => 10);
   h1 'Recently added';
   ul;
    for (@$r) {
      li;
       txt age $_->{added};
       txt ' ';
       a href => "/g$_->{id}", $_->{name};
      end;
    }
   end;
  end;

  # Popular
  div class => 'mainbox threelayout';
   my $r = $self->dbTagGet(order => 'c_vns DESC', meta => 0, results => 10);
   h1 'Popular tags';
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
  div class => 'mainbox threelayout last';
   a class => 'right', href => '/g/list?t=0;o=d;s=added', 'Moderation queue';
   h1 'Awaiting moderation';
   my $r = $self->dbTagGet(state => 0, order => 'added DESC', results => 10);
   if(@$r) {
     ul;
      for (@$r) {
        li;
         txt age $_->{added};
         txt ' ';
         a href => "/g$_->{id}", $_->{name};
        end;
      }
     end;
   } else {
     p 'Moderation queue empty! yay!';
   }
  end;
  clearfloat;
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

1;
