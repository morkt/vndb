
package VNDB::Handler::Producers;

use strict;
use warnings;
use YAWF ':html';
use VNDB::Func;


YAWF::register(
  qr{p([1-9]\d*)(?:\.([1-9]\d*))?} => \&page,
  qr{p(?:([1-9]\d*)/edit|/new)}    => \&edit,
  qr{p([1-9]\d*)/(lock|hide)}      => \&mod,
  qr{p/([a-z0]|all)}               => \&list,
);


sub page {
  my($self, $pid, $rev) = @_;

  my $p = $self->dbProducerGet(id => $pid, what => 'vn')->[0];
  return 404 if !$p->{id};

  $self->htmlHeader(title => $p->{name});
  $self->htmlMainTabs(p => $p);

  if($p->{hidden}) {
    div class => 'mainbox';
     h1 $p->{name};
     div class => 'warning';
      h2 'Item deleted';
      p;
       lit qq|This item has been deleted from the database, File a request on the|
          .qq| <a href="/t/p$pid">discussion board</a> to undelete this page.|;
      end;
     end;
    end;
    return $self->htmlFooter if !$self->authCan('del');
  }

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


# pid as argument = edit producer
# no arguments = add new producer
sub edit {
  my($self, $pid) = @_;

  my $p = $pid && $self->dbProducerGet(id => $pid)->[0];
  return 404 if $pid && !$p->{id};

  return $self->htmlDenied if !$self->authCan('edit')
    || $pid && ($p->{locked} && !$self->authCan('lock') || $p->{hidden} && !$self->authCan('del'));

  my %b4 = !$pid ? () : map { $_ => $p->{$_} } qw|type name original lang website desc|;
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
        if $pid && !grep $frm->{$_} ne $b4{$_}, keys %b4;

      my $rev = 1;
      if($pid) {
        ($rev) = $self->dbProducerEdit($pid, %$frm);
      } else {
        ($pid) = $self->dbProducerAdd(%$frm);
      }

      $self->multiCmd("ircnotify p$pid.$rev");

      return $self->resRedirect("/p$pid.$rev", 'post');
    }
  }

  !defined $frm->{$_} && ($frm->{$_} = $b4{$_}) for keys %b4;
  $frm->{lang} = 'ja' if !$pid && !defined $frm->{lang};

  $self->htmlHeader(title => $pid ? 'Edit '.$p->{name} : 'Add new producer');
  $self->htmlMainTabs('p', $p, 'edit') if $pid;
  div class => 'mainbox';
   h1 $pid ? 'Edit '.$p->{name} : 'Add new producer';
   div class => 'notice';
    h2 'Before editing:';
    ul;
     li; lit 'Read the <a href="/d4">guidelines</a>!'; end;
     if($pid) {
       li; lit qq|Check for any existing discussions on the <a href="/t/p$pid">discussion board</a>|; end;
       li; lit qq|Browse the <a href="/p$pid/hist">edit history</a> for any recent changes related to what you want to change.|; end;
     } else {
       li; lit qq|<a href="/p/all">Search the database</a> to see if we already have information about this producer|; end;
     }
    end;
   end;
  end;
  $self->htmlForm({ frm => $frm, action => $pid ? "/p$pid/edit" : '/p/new', editsum => 1 }, "General info" => [
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


sub list {
  my($self, $char) = @_;

  my $f = $self->formValidate(
    { name => 'p', required => 0, default => 1, template => 'int' },
    { name => 'q', required => 0, default => '' },
  );
  return 404 if $f->{_err};

  my($list, $np) = $self->dbProducerGet(
    $char ne 'all' ? ( char => $char ) : (),
    $f->{q} ? ( search => $f->{q} ) : (),
    results => 150,
    page => $f->{p}
  );

  $self->htmlHeader(title => 'Browse producers');

  div class => 'mainbox';
   h1 'Browse producers';
   form class => 'search', action => '/p/all', 'accept-charset' => 'UTF-8', method => 'get';
    fieldset;
     input type => 'text', name => 'q', id => 'q', class => 'text', value => $f->{q};
     input type => 'submit', class => 'submit', value => 'Search!';
    end;
   end;
   p class => 'browseopts';
    for ('all', 'a'..'z', 0) {
      a href => "/p/$_", $_ eq $char ? (class => 'optselected') : (), $_ ? uc $_ : '#';
    }
   end;
  end;
  
  my $pageurl = "/p/$char" . ($f->{q} ? "?q=$f->{q}" : '');
  $self->htmlBrowseNavigate($pageurl, $f->{p}, $np, 't');
  div class => 'mainbox producerbrowse';
   h1 $f->{q} ? 'Search results' : 'Producer list';
   if(!@$list) {
     p 'No results found';
   } else {
     # spread the results over 3 equivalent-sized lists
     my $perlist = @$list/3 < 1 ? 1 : @$list/3;
     for my $c (0..(@$list < 3 ? $#$list : 2)) {
       ul;
       for ($perlist*$c..($perlist*($c+1))-1) {
         li;
          acronym class => 'icons lang '.$list->[$_]{lang}, title => $self->{languages}{$list->[$_]{lang}}, ' ';
          a href => "/p$list->[$_]{id}", $list->[$_]{name};
         end;
       }
       end;
     }
   }
   br style => 'clear: left';
  end;
  $self->htmlBrowseNavigate($pageurl, $f->{p}, $np, 'b');
  $self->htmlFooter;
}


1;

