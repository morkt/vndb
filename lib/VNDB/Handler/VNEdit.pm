
package VNDB::Handler::VNEdit;

use strict;
use warnings;
use YAWF ':html';


YAWF::register(
  qr{v([1-9]\d*)/edit},   \&edit,
);


sub edit {
  my($self, $vid) = @_;

  my $v = $self->dbVNGet(id => $vid, what => 'extended screenshots relations anime categories changes')->[0];
  return 404 if !$v->{id};

  return $self->htmlDenied if !$self->authCan('edit')
    || ($v->{locked} && !$self->authCan('lock') || $v->{hidden} && !$self->authCan('del'));

  my $frm;

  $self->htmlHeader(title => 'Edit '.$v->{title});
  $self->htmlMainTabs('v', $v, 'edit');
  $self->htmlEditMessage('v', $v);
  $self->htmlForm({ frm => $frm, action => "/v$vid/edit", editsum => 1 }, 'General info' => [
  ], 'Categories' => [
  ], 'Image' => [
  ], 'Relations' => [
  ], 'Screenshots' => [
  ]);
  $self->htmlFooter;
}


1;

