
package VNDB::Handler::Producers;

use strict;
use warnings;
use YAWF ':html', ':xml';
use VNDB::Func;


YAWF::register(
  qr{p([1-9]\d*)(?:\.([1-9]\d*))?} => \&page,
  qr{p(?:([1-9]\d*)(?:\.([1-9]\d*))?/edit|/new)}
    => \&edit,
  qr{p/([a-z0]|all)}               => \&list,
  qr{xml/producers\.xml}           => \&pxml,
);


sub page {
  my($self, $pid, $rev) = @_;

  my $p = $self->dbProducerGet(
    id => $pid,
    what => 'vn extended'.($rev ? ' changes' : ''),
    $rev ? ( rev => $rev ) : ()
  )->[0];
  return 404 if !$p->{id};

  $self->htmlHeader(title => $p->{name}, noindex => $rev);
  $self->htmlMainTabs(p => $p);
  return if $self->htmlHiddenMessage('p', $p);

  if($rev) {
    my $prev = $rev && $rev > 1 && $self->dbProducerGet(id => $pid, rev => $rev-1, what => 'changes extended')->[0];
    $self->htmlRevision('p', $prev, $p,
      [ type      => 'Type',          serialize => sub { mt "_ptype_$_[0]" } ],
      [ name      => 'Name (romaji)', diff => 1 ],
      [ original  => 'Original name', diff => 1 ],
      [ alias     => 'Aliases',       diff => 1 ],
      [ lang      => 'Language',      serialize => sub { "$_[0] (".mt("_lang_$_[0]").')' } ],
      [ website   => 'Website',       diff => 1 ],
      [ desc      => 'Description',   diff => 1 ],
    );
  }

  div class => 'mainbox producerpage';
   $self->htmlItemMessage('p', $p);
   h1 $p->{name};
   h2 class => 'alttitle', $p->{original} if $p->{original};
   p class => 'center';
    txt mt '_prodpage_langtype', mt("_lang_$p->{lang}"), mt "_ptype_$p->{type}";
    txt "\n".mt '_progpage_aliases', $p->{alias} if $p->{alias};
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
   h1 mt '_prodpage_vnrel';
   if(!@{$p->{vn}}) {
     p mt '_prodpage_norel';
   } else {
     ul;
      for (@{$p->{vn}}) {
        li;
         i;
          lit $self->{l10n}->datestr($_->{date});
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
  my($self, $pid, $rev) = @_;

  my $p = $pid && $self->dbProducerGet(id => $pid, what => 'changes extended', $rev ? (rev => $rev) : ())->[0];
  return 404 if $pid && !$p->{id};
  $rev = undef if !$p || $p->{cid} == $p->{latest};

  return $self->htmlDenied if !$self->authCan('edit')
    || $pid && ($p->{locked} && !$self->authCan('lock') || $p->{hidden} && !$self->authCan('del'));

  my %b4 = !$pid ? () : map { $_ => $p->{$_} } qw|type name original lang website desc alias|;
  my $frm;

  if($self->reqMethod eq 'POST') {
    $frm = $self->formValidate(
      { name => 'type', enum => $self->{producer_types} },
      { name => 'name', maxlength => 200 },
      { name => 'original', required => 0, maxlength => 200, default => '' },
      { name => 'alias', required => 0, maxlength => 500, default => '' },
      { name => 'lang', enum => $self->{languages} },
      { name => 'website', required => 0, template => 'url', default => '' },
      { name => 'desc', required => 0, maxlength => 5000, default => '' },
      { name => 'editsum', maxlength => 5000 },
    );
    if(!$frm->{_err}) {
      return $self->resRedirect("/p$pid", 'post')
        if $pid && !grep $frm->{$_} ne $b4{$_}, keys %b4;

      $rev = 1;
      if($pid) {
        ($rev) = $self->dbProducerEdit($pid, %$frm);
      } else {
        ($pid) = $self->dbProducerAdd(%$frm);
      }

      return $self->resRedirect("/p$pid.$rev", 'post');
    }
  }

  !defined $frm->{$_} && ($frm->{$_} = $b4{$_}) for keys %b4;
  $frm->{lang} = 'ja' if !$pid && !defined $frm->{lang};
  $frm->{editsum} = sprintf 'Reverted to revision p%d.%d', $pid, $rev if $rev && !defined $frm->{editsum};

  my $title = mt $pid ? ('_pedit_title_edit', $p->{name}) : '_pedit_title_add';
  $self->htmlHeader(title => $title, noindex => 1);
  $self->htmlMainTabs('p', $p, 'edit') if $pid;
  $self->htmlEditMessage('p', $p, $title);
  $self->htmlForm({ frm => $frm, action => $pid ? "/p$pid/edit" : '/p/new', editsum => 1 }, 'pedit_geninfo' => [mt('_pedit_form_generalinfo'),
    [ select => name => mt('_pedit_form_type'), short => 'type',
      options => [ map [ $_, mt "_ptype_$_" ], sort @{$self->{producer_types}} ] ],
    [ input  => name => mt('_pedit_form_name'), short => 'name' ],
    [ input  => name => mt('_pedit_form_original'), short => 'original' ],
    [ static => content => mt('_pedit_form_original_note') ],
    [ input  => name => mt('_pedit_form_alias'), short => 'alias', width => 400 ],
    [ static => content => mt('_pedit_form_alias_note') ],
    [ select => name => mt('_pedit_form_lang'), short => 'lang',
      options => [ map [ $_, "$_ (".mt("_lang_$_").')' ], sort @{$self->{languages}} ] ],
    [ input  => name => mt('_pedit_form_website'), short => 'website' ],
    [ text   => name => mt('_pedit_form_desc'), short => 'desc', rows => 6 ],
  ]);
  $self->htmlFooter;
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

  $self->htmlHeader(title => mt '_pbrowse_title');

  div class => 'mainbox';
   h1 mt '_pbrowse_title';
   form action => '/p/all', 'accept-charset' => 'UTF-8', method => 'get';
    $self->htmlSearchBox('p', $f->{q});
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
   h1 mt $f->{q} ? '_pbrowse_searchres' : '_pbrowse_list';
   if(!@$list) {
     p mt '_pbrowse_noresults';
   } else {
     # spread the results over 3 equivalent-sized lists
     my $perlist = @$list/3 < 1 ? 1 : @$list/3;
     for my $c (0..(@$list < 3 ? $#$list : 2)) {
       ul;
       for ($perlist*$c..($perlist*($c+1))-1) {
         li;
          cssicon 'lang '.$list->[$_]{lang}, mt "_lang_$list->[$_]{lang}";
          a href => "/p$list->[$_]{id}", title => $list->[$_]{original}, $list->[$_]{name};
         end;
       }
       end;
     }
   }
   clearfloat;
  end;
  $self->htmlBrowseNavigate($pageurl, $f->{p}, $np, 'b');
  $self->htmlFooter;
}


# peforms a (simple) search and returns the results in XML format
sub pxml {
  my $self = shift;

  my $q = $self->formValidate({ name => 'q', maxlength => 500 });
  return 404 if $q->{_err};
  $q = $q->{q};

  my($list, $np) = $self->dbProducerGet(
    $q =~ /^p([1-9]\d*)/ ? (id => $1) : (search => $q),
    results => 10,
    page => 1,
  );

  $self->resHeader('Content-type' => 'text/xml; charset=UTF-8');
  xml;
  tag 'producers', more => $np ? 'yes' : 'no', query => $q;
   for(@$list) {
     tag 'item', id => $_->{id}, $_->{name};
   }
  end;
}


1;

