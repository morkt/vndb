
package VNDB::Handler::Producers;

use strict;
use warnings;
use YAWF ':html', ':xml', 'xml_escape';
use VNDB::Func;


YAWF::register(
  qr{p([1-9]\d*)/rg}               => \&rg,
  qr{p([1-9]\d*)(?:\.([1-9]\d*))?} => \&page,
  qr{p(?:([1-9]\d*)(?:\.([1-9]\d*))?/edit|/new)}
    => \&edit,
  qr{p/([a-z0]|all)}               => \&list,
  qr{xml/producers\.xml}           => \&pxml,
);


sub rg {
  my($self, $pid) = @_;

  my $p = $self->dbProducerGet(id => $pid, what => 'relgraph')->[0];
  return 404 if !$p->{id} || !$p->{rgraph};

  my $title = mt '_prodrg_title', $p->{name};
  return if $self->htmlRGHeader($title, 'p', $p);

  $p->{svg} =~ s/\$___(_prodrel_[a-z]+)____\$/mt $1/eg;
  $p->{svg} =~ s/\$(_lang_[a-z]+)_\$/mt $1/eg;
  $p->{svg} =~ s/\$(_ptype_[a-z]+)_\$/mt $1/eg;

  div class => 'mainbox';
   h1 $title;
   p class => 'center';
    lit $p->{svg};
   end;
  end;
  $self->htmlFooter;
}

sub page {
  my($self, $pid, $rev) = @_;

  my $p = $self->dbProducerGet(
    id => $pid,
    what => 'vn extended relations'.($rev ? ' changes' : ''),
    $rev ? ( rev => $rev ) : ()
  )->[0];
  return 404 if !$p->{id};

  $self->htmlHeader(title => $p->{name}, noindex => $rev);
  $self->htmlMainTabs(p => $p);
  return if $self->htmlHiddenMessage('p', $p);

  if($rev) {
    my $prev = $rev && $rev > 1 && $self->dbProducerGet(id => $pid, rev => $rev-1, what => 'changes extended relations')->[0];
    $self->htmlRevision('p', $prev, $p,
      [ type      => serialize => sub { mt "_ptype_$_[0]" } ],
      [ name      => diff => 1 ],
      [ original  => diff => 1 ],
      [ alias     => diff => 1 ],
      [ lang      => serialize => sub { "$_[0] (".mt("_lang_$_[0]").')' } ],
      [ website   => diff => 1 ],
      [ l_wp      => htmlize => sub {
        $_[0] ? sprintf '<a href="http://en.wikipedia.org/wiki/%s">%1$s</a>', xml_escape $_[0] : mt '_vndiff_nolink' # _vn? hmm...
      }],
      [ desc      => diff => 1 ],
      [ relations   => join => '<br />', split => sub {
        my @r = map sprintf('%s: <a href="/p%d" title="%s">%s</a>',
          mt("_prodrel_$_->{relation}"), $_->{id}, xml_escape($_->{original}||$_->{name}), xml_escape shorten $_->{name}, 40
        ), sort { $a->{id} <=> $b->{id} } @{$_[0]};
        return @r ? @r : (mt '_proddiff_none');
      }],
    );
  }

  div class => 'mainbox producerpage';
   $self->htmlItemMessage('p', $p);
   h1 $p->{name};
   h2 class => 'alttitle', $p->{original} if $p->{original};
   p class => 'center';
    txt mt '_prodpage_langtype', mt("_lang_$p->{lang}"), mt "_ptype_$p->{type}";
    txt "\n".mt '_prodpage_aliases', $p->{alias} if $p->{alias};

    my @links = (
      $p->{website} ? [ 'homepage',  $p->{website} ] : (),
      $p->{l_wp}    ? [ 'wikipedia', "http://en.wikipedia.org/wiki/$p->{l_wp}" ] : (),
    );
    txt "\n" if @links;
    for(@links) {
      a href => $_->[1], mt "_prodpage_$_->[0]";
      txt ' - ' if $_ ne $links[$#links];
    }
   end;

   if(@{$p->{relations}}) {
     my %rel;
     push @{$rel{$_->{relation}}}, $_
       for (sort { $a->{name} cmp $b->{name} } @{$p->{relations}});
     p class => 'center';
      txt "\n";
      for my $r (sort keys %rel) {
        txt mt("_prodrel_$r").': ';
        for (@{$rel{$r}}) {
          a href => "/p$_->{id}", title => $_->{original}||$_->{name}, shorten $_->{name}, 40;
          txt ', ' if $_ ne $rel{$r}[$#{$rel{$r}}];
        }
        txt "\n";
      }
     end;
   }

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
         b class => 'grayedout', ' ('.join(', ',
          $_->{developer} ? mt '_prodpage_dev' : (), $_->{publisher} ? mt '_prodpage_pub' : ()).')';
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

  my $p = $pid && $self->dbProducerGet(id => $pid, what => 'changes extended relations', $rev ? (rev => $rev) : ())->[0];
  return 404 if $pid && !$p->{id};
  $rev = undef if !$p || $p->{cid} == $p->{latest};

  return $self->htmlDenied if !$self->authCan('edit')
    || $pid && ($p->{locked} && !$self->authCan('lock') || $p->{hidden} && !$self->authCan('del'));

  my %b4 = !$pid ? () : (
    (map { $_ => $p->{$_} } qw|type name original lang website desc alias|),
    l_wp => $p->{l_wp} || '',
    prodrelations => join('|||', map $_->{relation}.','.$_->{id}.','.$_->{name}, sort { $a->{id} <=> $b->{id} } @{$p->{relations}}),
  );
  my $frm;

  if($self->reqMethod eq 'POST') {
    $frm = $self->formValidate(
      { name => 'type',          enum      => $self->{producer_types} },
      { name => 'name',          maxlength => 200 },
      { name => 'original',      required  => 0, maxlength => 200,  default => '' },
      { name => 'alias',         required  => 0, maxlength => 500,  default => '' },
      { name => 'lang',          enum      => $self->{languages} },
      { name => 'website',       required  => 0, template => 'url', default => '' },
      { name => 'l_wp',          required  => 0, maxlength => 150,  default => '' },
      { name => 'desc',          required  => 0, maxlength => 5000, default => '' },
      { name => 'prodrelations', required  => 0, maxlength => 5000, default => '' },
      { name => 'editsum',       maxlength => 5000 },
    );
    if(!$frm->{_err}) {
      # parse
      my $relations = [ map { /^([a-z]+),([0-9]+),(.+)$/ && (!$pid || $2 != $pid) ? [ $1, $2, $3 ] : () } split /\|\|\|/, $frm->{prodrelations} ];

      # normalize
      $frm->{prodrelations} = join '|||', map $_->[0].','.$_->[1].','.$_->[2], sort { $a->[1] <=> $b->[1]} @{$relations};

      return $self->resRedirect("/p$pid", 'post')
        if $pid && !grep $frm->{$_} ne $b4{$_}, keys %b4;

      $frm->{relations} = $relations;
      $frm->{l_wp} = undef if !$frm->{l_wp};
      $rev = 1;
      my $npid = $pid;
      my $cid;
      ($rev, $cid) = $self->dbProducerEdit($pid, %$frm) if $pid;
      ($npid, $cid) = $self->dbProducerAdd(%$frm) if !$pid;

      # update reverse relations
      if(!$pid && $#$relations >= 0 || $pid && $frm->{prodrelations} ne $b4{prodrelations}) {
        my %old = $pid ? (map { $_->{id} => $_->{relation} } @{$p->{relations}}) : ();
        my %new = map { $_->[1] => $_->[0] } @$relations;
        _updreverse($self, \%old, \%new, $npid, $cid, $rev);
      }

      return $self->resRedirect("/p$npid.$rev", 'post');
    }
  }

  !defined $frm->{$_} && ($frm->{$_} = $b4{$_}) for keys %b4;
  $frm->{lang} = 'ja' if !$pid && !defined $frm->{lang};
  $frm->{editsum} = sprintf 'Reverted to revision p%d.%d', $pid, $rev if $rev && !defined $frm->{editsum};

  my $title = mt $pid ? ('_pedit_title_edit', $p->{name}) : '_pedit_title_add';
  $self->htmlHeader(title => $title, noindex => 1);
  $self->htmlMainTabs('p', $p, 'edit') if $pid;
  $self->htmlEditMessage('p', $p, $title);
  $self->htmlForm({ frm => $frm, action => $pid ? "/p$pid/edit" : '/p/new', editsum => 1 },
  'pedit_geninfo' => [ mt('_pedit_form_generalinfo'),
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
    [ input  => name => mt('_pedit_form_wikipedia'), short => 'l_wp', pre => 'http://en.wikipedia.org/wiki/' ],
    [ text   => name => mt('_pedit_form_desc').'<br /><b class="standout">'.mt('_inenglish').'</b>', short => 'desc', rows => 6 ],
  ], 'pedit_rel' => [ mt('_pedit_form_rel'),
    [ hidden   => short => 'prodrelations' ],
    [ static   => nolabel => 1, content => sub {
      h2 mt '_pedit_rel_sel';
      table;
       tbody id => 'relation_tbl';
        # to be filled using javascript
       end;
      end;

      h2 mt '_pedit_rel_add';
      table;
       Tr id => 'relation_new';
        td class => 'tc_prod';
         input type => 'text', class => 'text';
        end;
        td class => 'tc_rel';
         Select;
          option value => $_, mt "_prodrel_$_"
            for (sort { $self->{prod_relations}{$a}[0] <=> $self->{prod_relations}{$b}[0] } keys %{$self->{prod_relations}});
         end;
        end;
        td class => 'tc_add';
         a href => '#', mt '_pedit_rel_addbut';
        end;
       end;
      end;
    }],
  ]);
  $self->htmlFooter;
}

# !IMPORTANT!: Don't forget to update this function when
#   adding/removing fields to/from producer entries!
sub _updreverse {
  my($self, $old, $new, $pid, $cid, $rev) = @_;
  my %upd;

  # compare %old and %new
  for (keys %$old, keys %$new) {
    if(exists $$old{$_} and !exists $$new{$_}) {
      $upd{$_} = undef;
    } elsif((!exists $$old{$_} and exists $$new{$_}) || ($$old{$_} ne $$new{$_})) {
      $upd{$_} = $self->{prod_relations}{$$new{$_}}[1];
    }
  }

  return if !keys %upd;

  # edit all related producers
  for my $i (keys %upd) {
    my $r = $self->dbProducerGet(id => $i, what => 'extended relations')->[0];
    my @newrel = map $_->{id} != $pid ? [ $_->{relation}, $_->{id} ] : (), @{$r->{relations}};
    push @newrel, [ $upd{$i}, $pid ] if $upd{$i};
    $self->dbProducerEdit($i,
      relations => \@newrel,
      editsum => "Reverse relation update caused by revision p$pid.$rev",
      causedby => $cid,
      uid => 1,         # Multi - hardcoded
      ( map { $_ => $r->{$_} } qw|type name original lang website desc alias| )
    );
  }
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
      a href => "/p/$_", $_ eq $char ? (class => 'optselected') : (), $_ eq 'all' ? mt('_char_all') : $_ ? uc $_ : '#';
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

