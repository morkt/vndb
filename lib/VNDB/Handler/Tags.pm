
package VNDB::Handler::Tags;


use strict;
use warnings;
use TUWF ':html', ':xml', 'xml_escape';
use VNDB::Func;


TUWF::register(
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
  return $self->resNotFound if !$t;

  my $f = $self->formValidate(
    { get => 's', required => 0, default => 'tagscore', enum => [ qw|title rel pop tagscore rating| ] },
    { get => 'o', required => 0, default => 'd', enum => [ 'a','d' ] },
    { get => 'p', required => 0, default => 1, template => 'page' },
    { get => 'm', required => 0, default => $self->authPref('spoilers') || 0, enum => [qw|0 1 2|] },
    { get => 'fil', required => 0 },
  );
  return $self->resNotFound if $f->{_err};
  $f->{fil} //= $self->authPref('filter_vn');

  my($list, $np) = $t->{meta} || $t->{state} != 2 ? ([],0) : $self->filFetchDB(vn => $f->{fil}, undef, {
    what => 'rating',
    results => 50,
    page => $f->{p},
    sort => $f->{s}, reverse => $f->{o} eq 'd',
    tagspoil => $f->{m},
    tag_inc => $tag,
    tag_exc => undef,
  });

  my $title = ($t->{meta} ? 'Meta tag: ' : 'Tag: ').$t->{name};
  $self->htmlHeader(title => $title, noindex => $t->{state} != 2);
  $self->htmlMainTabs('g', $t);

  if($t->{state} != 2) {
    div class => 'mainbox';
     h1 $title;
     if($t->{state} == 1) {
       div class => 'warning';
        h2 'Tag deleted';
        p;
         txt 'This tag has been removed from the database, and cannot be used or re-added.';
         br;
         txt 'File a request on the ';
         a href => '/t/db', 'discussion board';
         txt ' if you disagree with this.';
        end;
       end;
     } else {
       div class => 'notice';
        h2 'Waiting for approval';
        p 'This tag is waiting for a moderator to approve it. You can still use it to tag VNs as you would with a normal tag.';
       end;
     }
    end 'div';
  }

  div class => 'mainbox';
   a class => 'addnew', href => "/g$tag/add", 'Create child tag' if $self->authCan('tag') && $t->{state} != 1;
   h1 $title;

   parenttags($t, 'Tags', 'g');

   if($t->{description}) {
     p class => 'description';
      lit bb2html $t->{description};
     end;
   }
   p class => 'center';
    b 'Category';
    br;
    txt $self->{tag_categories}{$t->{cat}};
   end;
   if(@{$t->{aliases}}) {
     p class => 'center';
      b 'Aliases';
      br;
      lit xml_escape($_).'<br />' for (@{$t->{aliases}});
     end;
   }
  end 'div';

  childtags($self, 'Child tags', 'g', $t) if @{$t->{childs}};

  if(!$t->{meta} && $t->{state} == 2) {
    form action => "/g$t->{id}", 'accept-charset' => 'UTF-8', method => 'get';
    div class => 'mainbox';
     a class => 'addnew', href => "/g/links?t=$tag", 'Recently tagged';
     h1 'Visual novels';

     p class => 'browseopts';
      a href => "/g$t->{id}?fil=$f->{fil};m=0", $f->{m} == 0 ? (class => 'optselected') : (), 'Hide spoilers';
      a href => "/g$t->{id}?fil=$f->{fil};m=1", $f->{m} == 1 ? (class => 'optselected') : (), 'Show minor spoilers';
      a href => "/g$t->{id}?fil=$f->{fil};m=2", $f->{m} == 2 ? (class => 'optselected') : (), 'Spoil me!';
     end;

     p class => 'filselect';
      a id => 'filselect', href => '#v';
       lit '<i>&#9656;</i> Filters<i></i>';
      end;
     end;
     input type => 'hidden', class => 'hidden', name => 'fil', id => 'fil', value => $f->{fil};

     if(!@$list) {
       p; br; br; txt 'This tag has not been linked to any visual novels yet, or they were hidden because of your spoiler settings or default filters.'; end;
     }
     p; br; txt 'The list below also includes all visual novels linked to child tags. This list is cached, it can take up to 24 hours after a visual novel has been tagged for it to show up on this page.'; end;
    end 'div';
    end 'form';
    $self->htmlBrowseVN($list, $f, $np, "/g$t->{id}?fil=$f->{fil};m=$f->{m}", 1) if @$list;
  }

  $self->htmlFooter(pref_code => 1);
}


sub tagedit {
  my($self, $tag, $act) = @_;

  my($frm, $par);
  if($act && $act eq 'add') {
    $par = $self->dbTagGet(id => $tag)->[0];
    return $self->resNotFound if !$par;
    $frm->{parents} = $par->{name};
    $frm->{cat} = $par->{cat};
    $tag = undef;
  }

  return $self->htmlDenied if !$self->authCan('tag') || $tag && !$self->authCan('tagmod');

  my $t = $tag && $self->dbTagGet(id => $tag, what => 'parents(1) aliases addedby')->[0];
  return $self->resNotFound if $tag && !$t;

  if($self->reqMethod eq 'POST') {
    return if !$self->authCheckCode;
    $frm = $self->formValidate(
      { post => 'name',        required => 1, maxlength => 250, regex => [ qr/^[^,]+$/, 'A comma is not allowed in tag names' ] },
      { post => 'state',       required => 0, default => 0,  enum => [ 0..2 ] },
      { post => 'cat',         required => 1, enum => [ keys %{$self->{tag_categories}} ] },
      { post => 'catrec',      required => 0 },
      { post => 'meta',        required => 0, default => 0 },
      { post => 'alias',       required => 0, maxlength => 1024, default => '', regex => [ qr/^[^,]+$/s, 'No comma allowed in aliases' ]  },
      { post => 'description', required => 0, maxlength => 10240, default => '' },
      { post => 'parents',     required => !$self->authCan('tagmod'), default => '' },
      { post => 'merge',       required => 0, default => '' },
    );
    my @aliases = split /[\t\s]*\n[\t\s]*/, $frm->{alias};
    my @parents = split /[\t\s]*,[\t\s]*/, $frm->{parents};
    my @merge = split /[\t\s]*,[\t\s]*/, $frm->{merge};
    if(!$frm->{_err}) {
      my @dups = @{$self->dbTagGet(name => $frm->{name}, noid => $tag)};
      push @dups, @{$self->dbTagGet(name => $_, noid => $tag)} for @aliases;
      push @{$frm->{_err}}, \sprintf 'Tag <a href="/g%d">%s</a> already exists!', $_->{id}, xml_escape $_->{name} for @dups;
      for(@parents, @merge) {
        my $c = $self->dbTagGet(name => $_, noid => $tag);
        push @{$frm->{_err}}, "Tag '$_' not found" if !@$c;
        $_ = $c->[0]{id};
      }
    }

    if(!$frm->{_err}) {
      $frm->{state} = $frm->{meta} = 0 if !$self->authCan('tagmod');
      my %opts = (
        name => $frm->{name},
        state => $frm->{state},
        cat => $frm->{cat},
        description => $frm->{description},
        meta => $frm->{meta}?1:0,
        aliases => \@aliases,
        parents => \@parents,
      );
      if(!$tag) {
        $tag = $self->dbTagAdd(%opts);
      } else {
        $self->dbTagEdit($tag, %opts, upddate => $frm->{state} == 2 && $t->{state} != 2);
        _set_childs_cat($self, $tag, $frm->{cat}) if $frm->{catrec};
      }
      $self->dbTagMerge($tag, @merge) if $self->authCan('tagmod') && @merge;
      $self->resRedirect("/g$tag", 'post');
      return;
    }
  }

  if($tag) {
    $frm->{$_} ||= $t->{$_} for (qw|name meta description state cat|);
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
      p;
       txt 'Because all tags have to be approved by moderators, it can take a while before it will show up in the tag list'
          .' or on visual novel pages. You can still vote on tag even if it has not been approved yet, though.';
       br; br;
       txt 'Also, make sure you\'ve read the ';
       a href => '/d10', 'guidelines';
       txt ' so you can predict whether your tag will be accepted or not.';
      end;
     end;
    end;
  }

  $self->htmlForm({ frm => $frm, action => $par ? "/g$par->{id}/add" : $tag ? "/g$tag/edit" : '/g/new' }, 'tagedit' => [ $title,
    [ input    => short => 'name',     name => 'Primary name' ],
    $self->authCan('tagmod') ? (
      $tag ?
        [ static   => label => 'Added by', content => fmtuser($t->{addedby}, $t->{username}) ] : (),
      [ select   => short => 'state',    name => 'State', options => [
        [0, 'Awaiting moderation'], [1, 'Deleted/hidden'], [2, 'Approved']  ] ],
      [ checkbox => short => 'meta',     name => 'This is a meta-tag (only to be used as parent for other tags, not for linking to VN entries)' ],
      $tag ?
        [ static => content => 'WARNING: Checking this option or selecting "Deleted" as state will permanently delete all existing VN relations!' ] : (),
    ) : (),
    [ select   => short => 'cat', name => 'Category', options => [
      map [$_, $self->{tag_categories}{$_}], keys %{$self->{tag_categories}} ] ],
    $self->authCan('tagmod') && $tag ? (
      [ checkbox => short => 'catrec', name => 'Also edit all child tags to have this category' ],
      [ static => content => 'WARNING: This will overwrite the category field for all child tags, this action can not be reverted!' ],
    ) : (),
    [ textarea => short => 'alias',    name => "Aliases\n(separated by newlines)", cols => 30, rows => 4 ],
    [ textarea => short => 'description', name => 'Description' ],
    [ static   => content => 'What should the tag be used for? Having a good description helps users choose which tags to link to a VN.' ],
    [ input    => short => 'parents',  name => 'Parent tags' ],
    [ static   => content => 'Comma separated list of tag names to be used as parent for this tag.' ],
    $self->authCan('tagmod') ? (
      [ part   => title => 'Merge tags' ],
      [ input  => short => 'merge', name => 'Tags to merge' ],
      [ static => content =>
          'Comma separated list of tag names to merge into this one.'
         .' All votes and aliases/names will be moved over to this tag, and the old tags will be deleted.'
         .' Just leave this field empty if you don\'t intend to do a merge.'
         .'<br />WARNING: this action cannot be undone!' ],
    ) : (),
  ]);
  $self->htmlFooter;
}

# recursively edit all child tags and set the category field
# Note: this can be done more efficiently by doing everything in one UPDATE
#  query, but that takes more code and this feature isn't used very often
#  anyway.
sub _set_childs_cat {
  my($self, $tag, $cat) = @_;
  my %done;

  my $e;
  $e = sub {
    my $l = shift;
    for (@$l) {
      $self->dbTagEdit($_->{id}, cat => $cat) if !$done{$_->{id}}++;
      $e->($_->{sub}) if $_->{sub};
    }
  };

  my $childs = $self->dbTTTree(tag => $tag, 25);
  $e->($childs);
}


sub taglist {
  my $self = shift;

  my $f = $self->formValidate(
    { get => 's', required => 0, default => 'name', enum => ['added', 'name'] },
    { get => 'o', required => 0, default => 'a', enum => ['a', 'd'] },
    { get => 'p', required => 0, default => 1, template => 'page' },
    { get => 't', required => 0, default => -1, enum => [ -1..2 ] },
    { get => 'q', required => 0, default => '' },
  );
  return $self->resNotFound if $f->{_err};

  my($t, $np) = $self->dbTagGet(
    sort => $f->{s}, reverse => $f->{o} eq 'd',
    page => $f->{p},
    results => 50,
    state => $f->{t},
    search => $f->{q}
  );

  $self->htmlHeader(title => 'Browse tags');
  div class => 'mainbox';
   h1 'Browse tags';
   form action => '/g/list', 'accept-charset' => 'UTF-8', method => 'get';
    input type => 'hidden', name => 't', value => $f->{t};
    $self->htmlSearchBox('g', $f->{q});
   end;
   p class => 'browseopts';
    a href => "/g/list?q=$f->{q};t=-1", $f->{t} == -1 ? (class => 'optselected') : (), 'All';
    a href => "/g/list?q=$f->{q};t=0", $f->{t} == 0 ? (class => 'optselected') : (), 'Awaiting moderation';
    a href => "/g/list?q=$f->{q};t=1", $f->{t} == 1 ? (class => 'optselected') : (), 'Deleted';
    a href => "/g/list?q=$f->{q};t=2", $f->{t} == 2 ? (class => 'optselected') : (), 'Accepted';
   end;
   if(!@$t) {
     p 'No results found';
   }
  end 'div';
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
        [ 'Tag',  'name'  ],
      ],
      row => sub {
        my($s, $n, $l) = @_;
        Tr;
         td class => 'tc1', fmtage $l->{added};
         td class => 'tc3';
          a href => "/g$l->{id}", $l->{name};
          if($f->{t} == -1) {
            b class => 'grayedout', ' awaiting moderation' if $l->{state} == 0;
            b class => 'grayedout', ' deleted' if $l->{state} == 1;
          }
         end;
        end 'tr';
      }
    );
  }
  $self->htmlFooter;
}


sub taglinks {
  my $self = shift;

  my $f = $self->formValidate(
    { get => 'p', required => 0, default => 1, template => 'page' },
    { get => 'o', required => 0, default => 'd', enum => ['a', 'd'] },
    { get => 's', required => 0, default => 'date', enum => [qw|date tag|] },
    { get => 'v', required => 0, default => 0, template => 'id' },
    { get => 'u', required => 0, default => 0, template => 'id' },
    { get => 't', required => 0, default => 0, template => 'id' },
  );
  return $self->resNotFound if $f->{_err} || $f->{p} > 100;

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

  $self->htmlHeader(noindex => 1, title => 'Tag link browser');
  div class => 'mainbox';
   h1 'Tag link browser';

   div class => 'warning';
    h2 'Spoiler warning';
    p 'This list displays the tag votes of individual users. Spoilery tags are not hidden, and may not even be correctly flagged as such.';
   end;
   br;

   if($f->{u} || $f->{t} || $f->{v}) {
     p 'Active filters:';
     ul;
      if($f->{u}) {
        my $o = $self->dbUserGet(uid => $f->{u})->[0];
        li;
         txt '['; a href => $url->(u=>0), 'remove'; txt '] ';
         txt 'User:'; txt ' ';
         a href => "/u$o->{id}", $o->{username};
        end;
      }
      if($f->{t}) {
        my $o = $self->dbTagGet(id => $f->{t})->[0];
        li;
         txt '['; a href => $url->(t=>0), 'remove'; txt '] ';
         txt 'Tag:'; txt ' ';
         a href => "/g$o->{id}", $o->{name};
        end;
      }
      if($f->{v}) {
        my $o = $self->dbVNGet(id => $f->{v})->[0];
        li;
         txt '['; a href => $url->(v=>0), 'remove'; txt '] ';
         txt 'Visual novel:'; txt ' ';
         a href => "/v$o->{id}", $o->{title};
        end;
      }
     end 'ul';
   }
   p 'Click the arrow beside a user, tag or VN to add it as a filter.' unless $f->{v} && $f->{u} && $f->{t};
  end 'div';

  $self->htmlBrowse(
    class    => 'taglinks',
    options  => $f,
    nextpage => $np,
    items    => $list,
    pageurl  => $url->(),
    sorturl  => $url->(s=>0,o=>0),
    header   => [
      [ 'Date',   'date' ],
      [ 'User'    ],
      [ 'Rating'  ],
      [ 'Tag',    'tag' ],
      [ 'Spoiler' ],
      [ 'Visual novel' ],
    ],
    row      => sub {
      my($s, $n, $l) = @_;
      Tr;
       td class => 'tc1', fmtdate $l->{date};
       td class => 'tc2';
        a href => $url->(u=>$l->{uid}), class => 'setfil', '> ' if !$f->{u};
        a href => "/u$l->{uid}", $l->{username};
       end;
       td class => 'tc3'.($l->{ignore}?' ignored':'');
        tagscore $l->{vote};
       end;
       td class => 'tc4';
        a href => $url->(t=>$l->{tag}), class => 'setfil', '> ' if !$f->{t};
        a href => "/g$l->{tag}", $l->{name};
       end;
       td class => 'tc5', !defined $l->{spoiler} ? ' ' : fmtspoil $l->{spoiler};
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
  return $self->resNotFound if !$v || $v->{hidden};

  return $self->htmlDenied if !$self->authCan('tag');

  my $tags = $self->dbTagStats(vid => $vid, results => 9999);
  my $my = $self->dbTagLinks(vid => $vid, uid => $self->authInfo->{id});

  if($self->reqMethod eq 'POST') {
    return if !$self->authCheckCode;
    my $frm = $self->formValidate(
      { post => 'taglinks', required => 0, default => '', maxlength => 10240, regex => [ qr/^[1-9][0-9]*,-?[1-3],-?[0-2]( [1-9][0-9]*,-?[1-3],-?[0-2])*$/, 'meh' ] },
      { post => 'overrule', required => 0, multi => 1, template => 'id' },
    );
    return $self->resNotFound if $frm->{_err};

    # convert some data in a more convenient structure for faster lookup
    my %tags = map +($_->{id} => $_), @$tags;
    my %old = map +($_->{tag} => $_), @$my;
    my %new = map { my($tag, $vote, $spoiler) = split /,/; ($tag => [ $vote, $spoiler ]) } split / /, $frm->{taglinks};
    my %over = !$self->authCan('tagmod') || !$frm->{overrule}[0] ? () : (map $new{$_} ? ($_ => 1) : (), @{$frm->{overrule}});

    # hashes which need to be filled, indicating what should be changed to the DB
    my %delete;   # tag => 1
    my %update;   # tag => [ vote, spoiler ] (ignore flag is untouched)
    my %insert;   # tag => [ vote, spoiler, ignore ]
    my %overrule; # tag => 0/1

    for my $t (keys %old, keys %new) {
      my $prev_over = $old{$t} && !$old{$t}{ignore} && $tags{$t}{overruled};

      # overrule checkbox has changed? make sure to (de-)overrule the tag votes
      $overrule{$t} = $over{$t}?1:0 if (!$prev_over && $over{$t}) || ($prev_over && !$over{$t});

      # tag deleted?
      if($old{$t} && !$new{$t}) {
        $delete{$t} = 1;
        next;
      }

      # and insert or update the vote
      if(!$old{$t} && $new{$t}) {
        # determine whether this vote is going to be ignored or not
        my $ign = $tags{$t}{overruled} && !$prev_over && !$over{$t};
        $insert{$t} = [ $new{$t}[0], $new{$t}[1], $ign ];
      } elsif($old{$t}{vote} != $new{$t}[0] || (defined $old{$t}{spoiler} ? $old{$t}{spoiler} : -1) != $new{$t}[1]) {
        $update{$t} = [ $new{$t}[0], $new{$t}[1] ];
      }
    }
    # remove tags in the deleted state.
    delete $insert{$_->{id}} for(keys %insert ? @{$self->dbTagGet(id => [ keys %insert ], state => 1)} : ());

    $self->dbTagLinkEdit($self->authInfo->{id}, $vid, \%insert, \%update, \%delete, \%overrule);

    # need to re-fetch the tags and tag links, as these have been modified
    $tags = $self->dbTagStats(vid => $vid, results => 9999);
    $my = $self->dbTagLinks(vid => $vid, uid => $self->authInfo->{id});
  }


  my $title = "Add/remove tags for $v->{title}";
  $self->htmlHeader(title => $title, noindex => 1);
  $self->htmlMainTabs('v', $v, 'tagmod');
  div class => 'mainbox';
   h1 $title;
   div class => 'notice';
    h2 'Tagging';
    ul;
     li; txt 'Make sure you have read the '; a href => '/d10', 'guidelines'; txt '!'; end;
     li 'Don\'t forget to hit the submit button on the bottom of the page to make your changes permanent.';
     li 'Some tag information on the site is cached, it can take up to an hour for your changes to be visible everywhere.';
    end;
   end;
  end 'div';
  $self->htmlForm({ action => "/v$vid/tagmod", nosubmit => 1 }, tagmod => [ 'Tags',
    [ hidden => short => 'taglinks', value => '' ],
    [ static => nolabel => 1, content => sub {
      table class => 'tgl stripe';
       thead;
        Tr;
         td '';
         td colspan => $self->authCan('tagmod') ? 3 : 2, class => 'tc_you', 'You';
         td colspan => 3, class => 'tc_others', 'Others';
        end;
        Tr;
         td class => 'tc_tagname',  'Tag';
         td class => 'tc_myvote',   'Rating';
         td class => 'tc_myover',   'O' if $self->authCan('tagmod');
         td class => 'tc_myspoil',  'Spoiler';
         td class => 'tc_allvote',  'Rating';
         td class => 'tc_allspoil', 'Spoiler';
         td class => 'tc_allwho',   '';
        end;
       end 'thead';
       tfoot; Tr;
        td colspan => 6;
         input type => 'submit', class => 'submit', value => 'Save changes', style => 'float: right';
         input id => 'tagmod_tag', type => 'text', class => 'text', value => '';
         input id => 'tagmod_add', type => 'button', class => 'submit', value => 'Add tag';
         br;
         p;
          txt 'Check the '; a href => '/g', 'tag list'; txt ' to browse all available tags.';
          br;
          txt 'Can\'t find what you\'re looking for? '; a href => '/g/new', 'Request a new tag'; txt '.';
         end;
        end;
       end; end 'tfoot';
       tbody id => 'tagtable';
        _tagmod_list($self, $vid, $tags, $my);
       end 'tbody';
      end 'table';
    } ],
  ]);
  $self->htmlFooter;
}

sub _tagmod_list {
  my($self, $vid, $tags, $my) = @_;

  my %my = map +($_->{tag} => $_), @$my;

  for my $cat (keys %{$self->{tag_categories}}) {
    my @tags = grep $_->{cat} eq $cat, @$tags;
    next if !@tags;
    Tr class => 'tagmod_cat';
     td colspan => 7, $self->{tag_categories}{$cat};
    end;
    for my $t (@tags) {
      my $m = $my{$t->{id}};
      Tr id => "tgl_$t->{id}";
       td class => 'tc_tagname'; a href => "/g$t->{id}", $t->{name}; end;
       td class => 'tc_myvote',  $m->{vote}||0;
       if($self->authCan('tagmod')) {
         td class => 'tc_myover';
          input type => 'checkbox', name => 'overrule', value => $t->{id},
            $m->{vote} && !$m->{ignore} && $t->{overruled} ? (checked => 'checked') : ()
            if $t->{cnt} > 1;
         end;
       }
       td class => 'tc_myspoil', defined $m->{spoiler} ? $m->{spoiler} : -1;
       td class => 'tc_allvote';
        tagscore $t->{rating};
        i $t->{overruled} ? (class => 'grayedout') : (), " ($t->{cnt})";
        b class => 'standout', style => 'font-weight: bold', title => 'Tag overruled. All votes other than that of the moderator who overruled it will be ignored.', ' !' if $t->{overruled};
       end;
       td class => 'tc_allspoil', sprintf '%.2f', $t->{spoiler};
       td class => 'tc_allwho';
        a href => "/g/links?v=$vid;t=$t->{id}", 'Who?';
       end;
      end;
    }
  }
}


sub tagindex {
  my $self = shift;

  $self->htmlHeader(title => 'Tag index');
  div class => 'mainbox';
   a class => 'addnew', href => "/g/new", 'Create new tag' if $self->authCan('tag');
   h1 'Search tags';
   form action => '/g/list', 'accept-charset' => 'UTF-8', method => 'get';
    $self->htmlSearchBox('g', '');
   end;
  end;

  my $t = $self->dbTTTree(tag => 0, 2);
  childtags($self, 'Tag tree', 'g', {childs => $t});

  table class => 'mainbox threelayout';
   Tr;

    # Recently added
    td;
     a class => 'right', href => '/g/list', 'Browse all tags';
     my $r = $self->dbTagGet(sort => 'added', reverse => 1, results => 10, state => 2);
     h1 'Recently added';
     ul;
      for (@$r) {
        li;
         txt fmtage $_->{added};
         txt ' ';
         a href => "/g$_->{id}", $_->{name};
        end;
      }
     end;
    end;

    # Popular
    td;
     a class => 'addnew', href => "/g/links", 'Recently tagged';
     $r = $self->dbTagGet(sort => 'items', reverse => 1, meta => 0, results => 10);
     h1 'Popular tags';
     ul;
      for (@$r) {
        li;
         a href => "/g$_->{id}", $_->{name};
         txt " ($_->{c_items})";
        end;
      }
     end;
    end;

    # Moderation queue
    td;
     h1 'Awaiting moderation';
     $r = $self->dbTagGet(state => 0, sort => 'added', reverse => 1, results => 10);
     ul;
      li 'Moderation queue empty! yay!' if !@$r;
      for (@$r) {
        li;
         txt fmtage $_->{added};
         txt ' ';
         a href => "/g$_->{id}", $_->{name};
        end;
      }
      li;
       br;
       a href => '/g/list?t=0;o=d;s=added', 'Moderation queue';
       txt ' - ';
       a href => '/g/list?t=1;o=d;s=added', 'Denied tags';
      end;
     end;
    end;

   end 'tr';
  end 'table';
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
        b class => 'grayedout', " ($_->{c_items})" if $_->{c_items};
       end;
       $e->($_->{sub}) if $_->{sub};
     }
    end;
  };

  my $tags = $self->dbTTTree(tag => 0, 25);
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
    { get => 'q', required => 0, maxlength => 500 },
    { get => 'id', required => 0, multi => 1, template => 'id' },
  );
  return $self->resNotFound if $f->{_err} || (!$f->{q} && !$f->{id} && !$f->{id}[0]);

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
