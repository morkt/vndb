
package VNDB::Handler::Chars;

use strict;
use warnings;
use TUWF ':html';
use VNDB::Func;


TUWF::register(
  qr{c([1-9]\d*)(?:\.([1-9]\d*))?} => \&page,
  qr{c(?:([1-9]\d*)(?:\.([1-9]\d*))?/edit|/new)}
    => \&edit,
);


sub page {
  my($self, $id, $rev) = @_;

  my $r = $self->dbCharGet(
    id => $id,
    what => 'extended'.($rev ? ' changes' : ''),
    $rev ? ( rev => $rev ) : ()
  )->[0];
  return $self->resNotFound if !$r->{id};

  $self->htmlHeader(title => $r->{name});
  $self->htmlMainTabs(c => $r);
  return if $self->htmlHiddenMessage('c', $r);

  if($rev) {
    my $prev = $rev && $rev > 1 && $self->dbCharGet(id => $id, rev => $rev-1, what => 'changes extended')->[0];
    $self->htmlRevision('c', $prev, $r,
      [ name      => diff => 1 ],
      [ original  => diff => 1 ],
      [ alias     => diff => qr/[ ,\n\.]/ ],
      [ desc      => diff => qr/[ ,\n\.]/ ],
    );
  }

  div class => 'mainbox';
   $self->htmlItemMessage('c', $r);
   h1 $r->{name};
   h2 class => 'alttitle', $r->{original} if $r->{original};
   if($r->{desc}) {
     p class => 'description';
      lit bb2html($r->{desc});
     end;
   }
  end;
  $self->htmlFooter;
}



sub edit {
  my($self, $id, $rev) = @_;

  my $r = $id && $self->dbCharGet(id => $id, what => 'changes extended', $rev ? (rev => $rev) : ())->[0];
  return $self->resNotFound if $id && !$r->{id};
  $rev = undef if !$r || $r->{cid} == $r->{latest};

  return $self->htmlDenied if !$self->authCan('charedit')
    || $id && ($r->{locked} && !$self->authCan('lock') || $r->{hidden} && !$self->authCan('del'));

  my %b4 = !$id ? () : (
    (map { $_ => $r->{$_} } qw|name original alias desc ihid ilock|),
  );
  my $frm;

  if($self->reqMethod eq 'POST') {
    return if !$self->authCheckCode;
    $frm = $self->formValidate(
      { post => 'name',          maxlength => 200 },
      { post => 'original',      required  => 0, maxlength => 200,  default => '' },
      { post => 'alias',         required  => 0, maxlength => 500,  default => '' },
      { post => 'desc',          required  => 0, maxlength => 5000, default => '' },
      { post => 'editsum',       required  => 0, maxlength => 5000 },
      { post => 'ihid',          required  => 0 },
      { post => 'ilock',         required  => 0 },
    );
    push @{$frm->{_err}}, 'badeditsum' if !$frm->{editsum} || lc($frm->{editsum}) eq lc($frm->{desc});
    if(!$frm->{_err}) {
      $frm->{ihid}  = $frm->{ihid} ?1:0;
      $frm->{ilock} = $frm->{ilock}?1:0;

      return $self->resRedirect("/c$id", 'post')
        if $id && !grep $frm->{$_} ne $b4{$_}, keys %b4;

      my $nrev = $self->dbItemEdit(c => $id ? $r->{cid} : undef, %$frm);
      return $self->resRedirect("/c$nrev->{iid}.$nrev->{rev}", 'post');
    }
  }

  $frm->{$_} //= $b4{$_} for keys %b4;
  $frm->{editsum} //= sprintf 'Reverted to revision c%d.%d', $id, $rev if $rev;

  my $title = mt $r ? ('_chare_title_edit', $r->{name}) : '_chare_title_add';
  $self->htmlHeader(title => $title, noindex => 1);
  $self->htmlMainTabs('c', $r, 'edit') if $r;
  $self->htmlEditMessage('c', $r, $title);
  $self->htmlForm({ frm => $frm, action => $r ? "/c$id/edit" : '/c/new', editsum => 1 },
  'chare_geninfo' => [ mt('_chare_form_generalinfo'),
    [ input  => name => mt('_pedit_form_name'), short => 'name' ],
    [ input  => name => mt('_pedit_form_original'), short => 'original' ],
    [ static => content => mt('_pedit_form_original_note') ],
    [ text   => name => mt('_pedit_form_alias'), short => 'alias', rows => 3 ],
    [ static => content => mt('_pedit_form_alias_note') ],
    [ text   => name => mt('_pedit_form_desc').'<br /><b class="standout">'.mt('_inenglish').'</b>', short => 'desc', rows => 6 ],
  ]);
  $self->htmlFooter;
}


1;

