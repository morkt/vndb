
package VNDB::Handler::Traits;

use strict;
use warnings;
use TUWF ':html';
use VNDB::Func;


TUWF::register(
  qr{i([1-9]\d*)},          \&traitpage,
  qr{i([1-9]\d*)/(edit)},   \&traitedit,
  qr{i([1-9]\d*)/(add)},    \&traitedit,
  qr{i/new},                \&traitedit,
);


sub traitpage {
  my($self, $trait) = @_;

  my $t = $self->dbTraitGet(id => $trait, what => 'parents(0) childs(2) aliases')->[0];
  return $self->resNotFound if !$t;

  my $title = mt '_traitp_title', $t->{meta}?0:1, $t->{name};
  $self->htmlHeader(title => $title, noindex => $t->{state} != 2);
  $self->htmlMainTabs('i', $t);

  if($t->{state} != 2) {
    div class => 'mainbox';
     h1 $title;
     if($t->{state} == 1) {
       div class => 'warning';
        h2 mt '_traitp_del_title';
        p;
         lit mt '_traitp_del_msg';
        end;
       end;
     } else {
       div class => 'notice';
        h2 mt '_traitp_pending_title';
        p mt '_traitp_pending_msg';
       end;
     }
    end 'div';
  }

  div class => 'mainbox';
   a class => 'addnew', href => "/i$trait/add", mt '_traitp_addchild' if $self->authCan('charedit') && $t->{state} != 1;
   h1 $title;

   parenttags($t, mt('_traitp_indexlink'), 'i');

   if($t->{description}) {
     p class => 'description';
      lit bb2html $t->{description};
     end;
   }
   if(@{$t->{aliases}}) {
     p class => 'center';
      b mt('_traitp_aliases');
      br;
      lit xml_escape($_).'<br />' for (@{$t->{aliases}});
     end;
   }
  end 'div';

  childtags($self, mt('_traitp_childs'), 'i', $t) if @{$t->{childs}};

  # TODO: list of characters
  
  $self->htmlFooter;
}


sub traitedit {
  my($self, $trait, $act) = @_;

  my($frm, $par);
  if($act && $act eq 'add') {
    $par = $self->dbTraitGet(id => $trait)->[0];
    return $self->resNotFound if !$par;
    $frm->{parents} = $par->{name};
    $trait = undef;
  }

  return $self->htmlDenied if !$self->authCan('charedit') || $trait && !$self->authCan('tagmod');

  my $t = $trait && $self->dbTraitGet(id => $trait, what => 'parents(1) aliases addedby')->[0];
  return $self->resNotFound if $trait && !$t;

  if($self->reqMethod eq 'POST') {
    return if !$self->authCheckCode;
    $frm = $self->formValidate(
      { post => 'name',        required => 1, maxlength => 250, regex => [ qr/^[^,]+$/, 'A comma is not allowed in trait names' ] },
      { post => 'state',       required => 0, default => 0,  enum => [ 0..2 ] },
      { post => 'meta',        required => 0, default => 0 },
      { post => 'alias',       required => 0, maxlength => 1024, default => '', regex => [ qr/^[^,]+$/s, 'No comma allowed in aliases' ]  },
      { post => 'description', required => 0, maxlength => 10240, default => '' },
      { post => 'parents',     required => !$self->authCan('tagmod'), default => '' },
    );
    my @aliases = split /[\t\s]*\n[\t\s]*/, $frm->{alias};
    my @parents = split /[\t\s]*,[\t\s]*/, $frm->{parents};
    if(!$frm->{_err}) {
      my $c = $self->dbTraitGet(name => $frm->{name}, noid => $trait);
      push @{$frm->{_err}}, [ 'name', 'tagexists', $c->[0] ] if @$c; # should be traitexists... but meh
      for (@aliases) {
        $c = $self->dbTraitGet(name => $_, noid => $trait);
        push @{$frm->{_err}}, [ 'alias', 'tagexists', $c->[0] ] if @$c;
      }
      for(@parents) {
        $c = $self->dbTraitGet(name => $_, noid => $trait);
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
      if(!$trait) {
        $trait = $self->dbTraitAdd(%opts);
      } else {
        $self->dbTraitEdit($trait, %opts, upddate => $frm->{state} == 2 && $t->{state} != 2) if $trait;
      }
      $self->resRedirect("/i$trait", 'post');
      return;
    }
  }

  if($t) {
    $frm->{$_} ||= $t->{$_} for (qw|name meta description state|);
    $frm->{alias} ||= join "\n", @{$t->{aliases}};
    $frm->{parents} ||= join ', ', map $_->{name}, @{$t->{parents}};
  }

  my $title = $par ? mt('_traite_title_add', $par->{name}) : $t ? mt('_traite_title_edit', $t->{name}) : mt '_traite_title_new';
  $self->htmlHeader(title => $title, noindex => 1);
  $self->htmlMainTabs('i', $par || $t, 'edit') if $t || $par;

  if(!$self->authCan('tagmod')) {
    div class => 'mainbox';
     h1 mt '_traite_req_title';
     div class => 'notice';
      h2 mt '_traite_req_subtitle';
      p;
       lit mt '_traite_req_msg';
      end;
     end;
    end;
  }

  $self->htmlForm({ frm => $frm, action => $par ? "/i$par->{id}/add" : $t ? "/i$trait/edit" : '/i/new' }, 'traitedit' => [ $title,
    [ input    => short => 'name',     name => mt '_traite_frm_name' ],
    $self->authCan('tagmod') ? (
      $t ?
        [ static   => label => mt('_traite_frm_by'), content => $self->{l10n}->userstr($t->{addedby}, $t->{username}) ] : (),
      [ select   => short => 'state',    name => mt('_traite_frm_state'), options => [
        map [$_, mt '_traite_frm_state'.$_], 0..2 ] ],
      [ checkbox => short => 'meta',     name => mt '_traite_frm_meta' ]
    ) : (),
    [ textarea => short => 'alias',    name => mt('_traite_frm_alias'), cols => 30, rows => 4 ],
    [ textarea => short => 'description', name => mt '_traite_frm_desc' ],
    [ input    => short => 'parents',  name => mt '_traite_frm_parents' ],
    [ static   => content => mt '_traite_frm_parents_msg' ],
  ]);

  $self->htmlFooter;
}


1;

