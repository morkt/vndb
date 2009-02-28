
package VNDB::Handler::Tags;


use strict;
use warnings;
use YAWF ':html', ':xml';
use VNDB::Func;


YAWF::register(
  qr{g([1-9]\d*)},          \&tagpage,
  qr{g([1-9]\d*)/(edit)},   \&tagedit,
  qr{g([1-9]\d*)/(add)},    \&tagedit,
  qr{g([1-9]\d*)/del(/o)?}, \&tagdel,
  qr{g/new},                \&tagedit,
  qr{v([1-9]\d*)/tagmod},   \&vntagmod,
  qr{g},                    \&tagtree,
  qr{xml/tags\.xml},        \&tagxml,
);


sub tagpage {
  my($self, $tag) = @_;

  my $t = $self->dbTagGet(id => $tag, what => 'parents(0) childs(2)')->[0];
  return 404 if !$t;

  my $title = ($t->{meta} ? 'Meta tag: ' : 'Tag: ').$t->{name};
  $self->htmlHeader(title => $title);
  $self->htmlMainTabs('g', $t);
  div class => 'mainbox';
   a class => 'addnew', href => "/g$tag/add", 'Create child tag' if $self->authCan('tagmod');
   h1 $title;
   h2 class => 'alttitle', 'a.k.a. '.join(', ', split /\n/, $t->{alias}) if $t->{alias};

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
  end;

  _childtags($self, $t) if @{$t->{childs}};

  $self->htmlFooter;
}

sub _childtags {
  my($self, $t) = @_;

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
   h1 'Child tags';
   ul class => 'tagtree';
    for my $p (sort { @{$b->{childs}} <=> @{$a->{childs}} } @tags) {
      li;
       a href => "/g$p->{tag}", $p->{name};
       b class => 'grayedout', ' ('.(int(rand()*100)).')';
       end, next if !@{$p->{childs}};
       ul;
        for (0..$#{$p->{childs}}) {
          last if $_ >= 5 && @{$p->{childs}} > 6;
          li;
           txt '> ';
           a href => "/g$p->{childs}[$_]{tag}", $p->{childs}[$_]{name};
           b class => 'grayedout', ' ('.(int(rand()*50)).')';
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


sub tagedit {
  my($self, $tag, $act) = @_;

  return $self->htmlDenied if !$self->authCan('tagmod');

  my($frm, $par);
  if($act && $act eq 'add') {
    $par = $self->dbTagGet(id => $tag)->[0];
    return 404 if !$par;
    $frm->{parents} = $tag;
    $tag = undef;
  }

  my $t = $tag && $self->dbTagGet(id => $tag, what => 'parents(1)')->[0];
  return 404 if $tag && !$t;

  if($self->reqMethod eq 'POST') {
    $frm = $self->formValidate(
      { name => 'name',        required => 1, maxlength => 250 },
      { name => 'meta',        required => 0, default => 0 },
      { name => 'alias',       required => 0, maxlength => 1024, default => '' },
      { name => 'description', required => 0, maxlength => 1024, default => '' },
      { name => 'parents',     required => 0, regex => [ qr/^(\d+)(\s\d+)*$/, 'Parents must be a list of tag IDs' ], default => '' }
    );
    if(!$frm->{_err}) {
      my $c = $self->dbTagGet(name => $frm->{name});
      $frm->{_err} = [ 'tagexists' ] if !$t && @$c || $t && (@$c > 1 || @$c && $c->[0]{id} != $tag);
    }
    if(!$frm->{_err}) {
      $frm->{meta} = $frm->{meta} ? 1 : 0;
      $frm->{parents} = [ split / /, $frm->{parents} ];
      $self->dbTagEdit($tag, %$frm) if $tag;
      $tag = $self->dbTagAdd(%$frm) if !$tag;
      $self->resRedirect("/g$tag", 'post');
    }
  }

  if($tag) {
    $frm->{$_} ||= $t->{$_} for (qw|name meta alias description|);
    $frm->{parents} ||= join ' ', map $_->{tag}, @{$t->{parents}};
  }

  my $title = $par ? "Add child tag to $par->{name}" : $tag ? "Edit tag: $t->{name}" : 'Add new tag';
  $self->htmlHeader(title => $title, noindex => 1);
  $self->htmlMainTabs('g', $par || $t, 'edit') if $t || $par;
  $self->htmlForm({ frm => $frm, action => $par ? "/g$par->{id}/add" : $tag ? "/g$tag/edit" : '/g/new' }, $title => [
    [ input    => short => 'name',     name => 'Primary name' ],
    [ checkbox => short => 'meta',     name => 'This is a meta-tag (only to be used as parent for other tags, not for linking to VN entries)' ],
    $tag ?
      [ static => content => 'WARNING: Checking this option will permanently delete all existing VN relations!' ] : (),
    [ textarea => short => 'alias',    name => "Aliases\n(separated by newlines)", cols => 30, rows => 4 ],
    [ textarea => short => 'description', name => 'Description' ],
    [ static   => content => 'What should the tag be used for? Having a good description helps users choose which tags to link to a VN.' ],
    [ input    => short => 'parents',  name => 'Parent tags' ],
    [ static   => content => "Space separated list of tag IDs to be used as parent for this tag. A proper user interface will come in the future...<br /><br />...probably." ],
  ]);
  $self->htmlFooter;
}


sub tagdel {
  my($self, $tag, $act) = @_;
  return $self->htmlDenied if !$self->authCan('tagmod');

  # confirm
  if(!$act || $act ne '/o') {
    my $t = $self->dbTagGet(id => $tag)->[0];
    return 404 if !$t->{id};
    $self->htmlHeader(title => 'Delete tag', noindex => 1);
    $self->htmlMainTabs('g', $t, 'del');
    div class => 'mainbox';
     div class => 'warning';
      h2 'Delete tag';
      p;
       lit qq|Are you sure you want to delete the <a href="/g$tag">$t->{name}</a> tag? |
          .qq|All VN relations will be permanently deleted as well!<br /><br />|
          .qq|<a href="/g$tag/del/o">Yes, I'm not kidding!</a>|;
      end;
     end;
    end;
    $self->htmlFooter;
  }
  # delete
  else {
    $self->dbTagDel($tag);
    $self->resRedirect('/g', 'post');
  }
}


sub vntagmod {
  my($self, $vid) = @_;

  my $v = $self->dbVNGet(id => $vid)->[0];
  return 404 if !$v;

  return $self->htmlDenied if !$self->authCan('tag');

  my $my = $self->dbTagLinks(vid => $vid, uid => $self->authInfo->{id});
  my $tags = $self->dbVNTags($vid);

  my $frm;

  $self->htmlHeader(title => "Add/remove tags for $v->{title}", noindex => 1, js => 'forms');
  $self->htmlMainTabs('v', $v, 'tagmod');
  div class => 'mainbox';
   h1 "Add/remove tags for $v->{title}";
   div class => 'warning';
    h2 'Tagging';
    ul;
     li "Don't forget to hit the submit button on the bottom of the page after changing anything here!";
     li 'Tag guidelines?';
     li '!IMPORTANT! The current user interface is just for testing, and likely doesn\'t reflect the final form!';
    end;
   end;
  end;
  $self->htmlForm({ frm => $frm, action => "/v$vid/tagmod" }, 'Tags' => [
    [ hidden => short => 'taglinks', value => '' ],
    [ static => nolabel => 1, content => sub {
      table id => 'tagtable';
       thead; Tr;
        td $_ for('Tag', 'Users', 'Rating', 'Spoiler', 'Your vote', 'Your spoiler');
       end; end;
       tfoot; Tr;
        td colspan => 6;
         input type => 'text', class => 'text', name => 'addtag', value => '';
         input type => 'button', class => 'submit', value => 'Add tag';
        end;
       end; end;
       tbody;
        for my $t (sort { $a->{name} cmp $b->{name} } @$tags) {
          my $m = (grep $_->{tag} == $t->{id}, @$my)[0] || {};
          Tr;
           td;
            a href => "/g$t->{id}", $t->{name};
           end;
           td $t->{users} - ($m ? 1 : 0);
           td sprintf '%.2f', $m ? ($t->{rating}/$t->{users} - $m->{vote}) * ($t->{users}-1) : $t->{rating};
           td $t->{spoiler};
           td $m->{vote}||0;
           td $m->{spoiler}||'-';
          end;
        }
       end;
      end;
    } ],
  ]);
  $self->htmlFooter;
}


sub tagtree {
  my $self = shift;

  $self->htmlHeader(title => '[DEBUG] The complete tag tree');
  div class => 'mainbox';
   h1 '[DEBUG] The complete tag tree';
   p "This page won't make it to the final version. (At least, not in this form)\n\n";

   div style => 'margin-left: 10px';
    my $t = $self->dbAll('SELECT * FROM tag_tree(0, -1, true)');
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
     tag 'item', id => $_->{id}, meta => $_->{meta} ? 'yes' : 'no', $_->{name};
   }
  end;
}

1;
