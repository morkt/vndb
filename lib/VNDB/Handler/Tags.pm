
package VNDB::Handler::Tags;


use strict;
use warnings;
use YAWF ':html';
use VNDB::Func;


YAWF::register(
  qr{g([1-9]\d*)},      \&tagpage,
  qr{g([1-9]\d*)/edit}, \&tagedit,
  qr{g/new},            \&tagedit,
  qr{g},                \&tagtree,
);


sub tagpage {
  my($self, $tag) = @_;

  my $t = $self->dbTagGet(id => $tag, what => 'parents(0) childs(2)')->[0];
  return 404 if !$t;

  my $title = ($t->{meta} ? 'Meta tag: ' : 'Tag: ').$t->{name};
  $self->htmlHeader(title => $title);
  $self->htmlMainTabs('g', $t);
  div class => 'mainbox';
   h1 $title;
   h2 class => 'alttitle', 'a.k.a. '.join(', ', split /\n/, $t->{aliases}) if $t->{aliases};

   # TODO: handle multiple parents here
   p;
    a href => '/g', 'Tags';
    for (sort { $a->{lvl} <=> $b->{lvl} } @{$t->{parents}}) {
      txt ' > ';
      a href => "/g$_->{tag}", $_->{name};
    }
    txt ' > '.$t->{name};
   end;

   if($t->{description}) {
     p;
      lit bb2html $t->{description};
     end;
   }

   if(@{$t->{childs}}) {
     ul class => 'tagtree';
      li 'Child tags';
      my $lvl = $t->{childs}[0]{lvl} + 1;
      for (@{$t->{childs}}) {
        map ul,  1..($lvl-$_->{lvl}) if $lvl > $_->{lvl};
        map end, 1..($_->{lvl}-$lvl) if $lvl < $_->{lvl};
        $lvl = $_->{lvl};
        li;
         txt ' > ';
         a href => "/g$_->{tag}", $_->{name};
        end;
      }
      map end, 0..($t->{childs}[0]{lvl}-$lvl);
     end;
   }

  end;
  $self->htmlFooter;
}


sub tagedit {
  my($self, $tag) = @_;

  return $self->htmlDenied if !$self->authCan('tagmod');

  my $t = $tag && $self->dbTagGet(id => $tag, what => 'parents(1)')->[0];
  return 404 if $tag && !$t;

  my $frm;
  if($self->reqMethod eq 'POST') {
    $frm = $self->formValidate(
      { name => 'name',        required => 1, maxlength => 250 },
      { name => 'meta',        required => 0, default => 0 },
      { name => 'aliases',     required => 0, maxlength => 1024, default => '' },
      { name => 'description', required => 0, maxlength => 1024, default => '' },
      { name => 'parents',     required => 0, regex => [ qr/^(\d+)(\s\d+)*$/, 'Parents must be a list of tag IDs' ], default => '' }
    );
    if(!$frm->{_err}) {
      $frm->{meta} = $frm->{meta} ? 1 : 0;
      $frm->{parents} = [ split / /, $frm->{parents} ];
      $self->dbTagEdit($tag, %$frm) if $tag;
      $tag = $self->dbTagAdd(%$frm) if !$tag;
      $self->resRedirect("/g$tag", 'post');
    }
  }

  if($tag) {
    $frm->{$_} ||= $t->{$_} for (qw|name meta aliases description|);
    $frm->{parents} ||= join ' ', map $_->{tag}, @{$t->{parents}};
  }

  $self->htmlHeader(title => $tag ? "Editing tag: $t->{name}" : 'Adding new tag');
  $self->htmlMainTabs('g', $t, 'edit') if $t;
  $self->htmlForm({ frm => $frm, action => $tag ? "/g$tag/edit" : '/g/new' }, 'General info' => [
    [ input    => short => 'name',     name => 'Primary name' ],
    [ checkbox => short => 'meta',     name => 'This is a meta-tag (only to be used as parent for other tags, not for linking to VN entries)' ],
    $tag ?
      [ static => content => 'WARNING: Checking this option will permanently delete all existing VN relations!' ] : (),
    [ textarea => short => 'aliases',  name => "Aliases\n(separated by newlines)", cols => 30, rows => 4 ],
    [ textarea => short => 'description', name => 'Description' ],
    [ static   => content => 'What should the tag be used for? Having a good description helps users choose which tags to link to a VN.' ],
    [ input    => short => 'parents',  name => 'Parent tags' ],
    [ static   => content => "Space separated list of tag IDs to be used as parent for this tag. A proper user interface will come in the future...<br /><br />...probably." ],
  ]);
  $self->htmlFooter;
}


sub tagtree {
  my $self = shift;

  $self->htmlHeader(title => '[DEBUG] The complete tag tree');
  div class => 'mainbox';
   h1 '[DEBUG] The complete tag tree';

   my $t = $self->dbAll('SELECT * FROM tag_tree(0, -1, true)');
   ul class => 'tagtree';
    li "This page won't make it to the final version. (At least, not in this form)\n\n";
    my $lvl = $t->[0]{lvl} + 1;
    for (@$t) {
      map ul,  1..($lvl-$_->{lvl}) if $lvl > $_->{lvl};
      map end, 1..($_->{lvl}-$lvl) if $lvl < $_->{lvl};
      $lvl = $_->{lvl};
      li;
       txt ' > ';
       a href => "/g$_->{tag}", $_->{name};
      end;
    }
    map end, 0..($t->[0]{lvl}-$lvl);
   end;
  end;
  $self->htmlFooter;
}


1;
