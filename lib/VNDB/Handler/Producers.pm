
package VNDB::Handler::Producers;

use strict;
use warnings;
use YAWF ':html';
use VNDB::Func;


YAWF::register(
  qr{p([1-9]\d*)(?:\.([1-9]\d*))} => \&page,
  qr{p([1-9]\d*)/edit}            => \&edit,
  qr{p([1-9]\d*)/(lock|hide)}     => \&mod,
);


sub page {
  my($self, $pid, $rev) = @_;

  my $p = $self->dbProducerGet(id => $pid, what => 'vn')->[0];
  return 404 if !$p->{id};

  $self->htmlHeader(title => $p->{name});
  $self->htmlMainTabs(p => $p);
  div class => 'mainbox producerpage';
   p class => 'locked', 'Locked for editing' if $p->{locked};
   h1 $p->{name};
   h2 class => 'alttitle', $p->{original} if $p->{original};
   p class => 'center';
    txt "$self->{languages}{$p->{lang}} \L$self->{producer_types}{$p->{type}}";
    if($p->{website}) {
      txt "\n";
      a href => $p->{website}, $p->{website};
    }
   end;

   if($p->{desc}) {
     p class => 'description';
      lit bb2html $p->{desc};
     end;
   }

  end;
  div class => 'mainbox producerpage';
   h1 'Visual Novel Relations';
   if(!@{$p->{vn}}) {
     p 'We have currently no visual novels related to this producer.';
   } else {
     ul;
      for (@{$p->{vn}}) {
        li;
         i;
          lit datestr $_->{date};
         end;
         a href => "/v$_->{id}", title => $_->{original}, $_->{title};
        end;
      }
     end;
   }
  end;
  $self->htmlFooter;
}


sub edit {
  my($self, $pid) = @_;

  my $p = $self->dbProducerGet(id => $pid)->[0];
  return 404 if !$p->{id};

  return $self->htmlDenied if !$self->authCan('edit') || $p->{locked} && !$self->authCan('lock') || $p->{hidden} && !$self->authCan('del'); 

  my %b4 = map { $_ => $p->{$_} } qw|type name original lang website desc|;
  my $frm;

  if($self->reqMethod eq 'POST') {
    $frm = $self->formValidate(
      { name => 'type', enum => [ keys %{$self->{producer_types}} ] },
      { name => 'name', maxlength => 200 },
      { name => 'original', required => 0, maxlength => 200, default => '' },
      { name => 'lang', enum => [ keys %{$self->{languages}} ] },
      { name => 'website', required => 0, template => 'url', default => '' },
      { name => 'desc', required => 0, maxlength => 5000, default => '' },
      { name => 'editsum', maxlength => 5000 },
    );
    if(!$frm->{_err}) {
      return $self->resRedirect("/p$pid", 'post')
        if !grep $frm->{$_} ne $b4{$_}, keys %b4;

      my($rev) = $self->dbProducerEdit($pid, %$frm);

      # TODO: message Multi with an ircnotify

      return $self->resRedirect("/p$pid.$rev", 'post');
    }
  }

  !defined $frm->{$_} && ($frm->{$_} = $b4{$_}) for keys %b4;

  $self->htmlHeader(title => 'Edit '.$p->{name});
  $self->htmlMainTabs('p', $p, 'edit');
  div class => 'mainbox';
   h1 'Edit '.$p->{name};
   div class => 'notice';
    h2 'Before editing:';
    ul;
     li; lit 'Read the <a href="/d4">guidelines</a>!'; end;
     li; lit qq|Check for any existing discussions on the <a href="/t/p$pid">discussion board</a>|; end;
     li; lit qq|Browse the <a href="/p$pid/hist">edit history</a> for any recent changes related to what you want to change.|; end;
    end;
   end;
  end;
  $self->htmlForm({ frm => $frm, action => "/p$pid/edit", editsum => 1 }, "General info" => [
    [ select => name => 'Type', short => 'type',
      options => [ map [ $_, $self->{producer_types}{$_} ], sort keys %{$self->{producer_types}} ] ],
    [ input  => name => 'Name (romaji)', short => 'name' ],
    [ input  => name => 'Original name', short => 'original' ],
    [ static => content => q|The original name of the producer, leave blank if it is already in the Latin alphabet.| ],
    [ select => name => 'Primary language', short => 'lang',
      options => [ map [ $_, "$_ ($self->{languages}{$_})" ], sort keys %{$self->{languages}} ] ],
    [ input  => name => 'Website', short => 'website' ],
    [ text   => name => 'Description', short => 'desc', rows => 6 ],
  ]);
  $self->htmlFooter;
}


# /hide and /lock
sub mod {
  my($self, $pid, $act) = @_;
  return $self->htmlDenied if !$self->authCan($act eq 'hide' ? 'del' : 'lock');
  my $p = $self->dbProducerGet(id => $pid)->[0];
  return 404 if !$p->{id};
  $self->dbProducerMod($pid, $act eq 'hide' ? (hidden => !$p->{hidden}) : (locked => !$p->{locked}));
  $self->resRedirect("/p$pid", 'temp');
}


1;

