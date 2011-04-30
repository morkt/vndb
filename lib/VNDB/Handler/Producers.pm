
package VNDB::Handler::Producers;

use strict;
use warnings;
use TUWF ':html', ':xml', 'xml_escape', 'html_escape';
use VNDB::Func;


TUWF::register(
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
  return $self->resNotFound if !$p->{id} || !$p->{rgraph};

  my $title = mt '_prodrg_title', $p->{name};
  return if $self->htmlRGHeader($title, 'p', $p);

  $p->{svg} =~ s/id="node_p$pid"/id="graph_current"/;
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
    what => 'extended relations'.($rev ? ' changes' : ''),
    $rev ? ( rev => $rev ) : ()
  )->[0];
  return $self->resNotFound if !$p->{id};

  $self->htmlHeader(title => $p->{name}, noindex => $rev);
  $self->htmlMainTabs(p => $p);
  return if $self->htmlHiddenMessage('p', $p);

  if($rev) {
    my $prev = $rev && $rev > 1 && $self->dbProducerGet(id => $pid, rev => $rev-1, what => 'changes extended relations')->[0];
    $self->htmlRevision('p', $prev, $p,
      [ type      => serialize => sub { mt "_ptype_$_[0]" } ],
      [ name      => diff => 1 ],
      [ original  => diff => 1 ],
      [ alias     => diff => qr/[ ,\n\.]/ ],
      [ lang      => serialize => sub { "$_[0] (".mt("_lang_$_[0]").')' } ],
      [ website   => diff => 1 ],
      [ l_wp      => htmlize => sub {
        $_[0] ? sprintf '<a href="http://en.wikipedia.org/wiki/%s">%1$s</a>', xml_escape $_[0] : mt '_revision_nolink'
      }],
      [ desc      => diff => qr/[ ,\n\.]/ ],
      [ relations   => join => '<br />', split => sub {
        my @r = map sprintf('%s: <a href="/p%d" title="%s">%s</a>',
          mt("_prodrel_$_->{relation}"), $_->{id}, xml_escape($_->{original}||$_->{name}), xml_escape shorten $_->{name}, 40
        ), sort { $a->{id} <=> $b->{id} } @{$_[0]};
        return @r ? @r : (mt '_revision_empty');
      }],
    );
  }

  div class => 'mainbox';
   $self->htmlItemMessage('p', $p);
   h1 $p->{name};
   h2 class => 'alttitle', $p->{original} if $p->{original};
   p class => 'center';
    txt mt '_prodpage_langtype', mt("_lang_$p->{lang}"), mt "_ptype_$p->{type}";
    lit '<br />'.html_escape mt '_prodpage_aliases', $p->{alias} if $p->{alias};

    my @links = (
      $p->{website} ? [ 'homepage',  $p->{website} ] : (),
      $p->{l_wp}    ? [ 'wikipedia', "http://en.wikipedia.org/wiki/$p->{l_wp}" ] : (),
    );
    br if @links;
    for(@links) {
      a href => $_->[1], mt "_prodpage_$_->[0]";
      txt ' - ' if $_ ne $links[$#links];
    }
   end 'p';

   if(@{$p->{relations}}) {
     my %rel;
     push @{$rel{$_->{relation}}}, $_
       for (sort { $a->{name} cmp $b->{name} } @{$p->{relations}});
     p class => 'center';
      br;
      for my $r (sort { $self->{prod_relations}{$a}[0] <=> $self->{prod_relations}{$b}[0] } keys %rel) {
        txt mt("_prodrel_$r").': ';
        for (@{$rel{$r}}) {
          a href => "/p$_->{id}", title => $_->{original}||$_->{name}, shorten $_->{name}, 40;
          txt ', ' if $_ ne $rel{$r}[$#{$rel{$r}}];
        }
        br;
      }
     end 'p';
   }

   if($p->{desc}) {
     p class => 'description';
      lit bb2html $p->{desc};
     end;
   }
  end 'div';

  _releases($self, $p);

  $self->htmlFooter;
}

sub _releases {
  my($self, $p) = @_;

  # prodpage_(dev|pub)
  my $r = $self->dbReleaseGet(pid => $p->{id}, results => 999, what => 'vn platforms');
  div class => 'mainbox';
   a href => '#', id => 'expandprodrel', mt '_js_collapse';
   h1 mt '_prodpage_rel';
   if(!@$r) {
     p mt '_prodpage_norel';
     end;
     return;
   }

   my %vn; # key = vid, value = [ $r1, $r2, $r3, .. ]
   my @vn; # $vn objects in order of first release
   for my $rel (@$r) {
     for my $v (@{$rel->{vn}}) {
       push @vn, $v if !$vn{$v->{vid}};
       push @{$vn{$v->{vid}}}, $rel;
     }
   }

   table id => 'prodrel';
    for my $v (@vn) {
      Tr class => 'vn';
       td colspan => 6;
        i; lit $self->{l10n}->datestr($vn{$v->{vid}}[0]{released}); end;
        a href => "/v$v->{vid}", title => $v->{original}, $v->{title};
        span '('.join(', ',
           (grep($_->{developer}, @{$vn{$v->{vid}}}) ? mt '_prodpage_dev' : ()),
           (grep($_->{publisher}, @{$vn{$v->{vid}}}) ? mt '_prodpage_pub' : ())
        ).')';
       end;
      end;
      for my $rel (@{$vn{$v->{vid}}}) {
        Tr class => 'rel';
         td class => 'tc1'; lit $self->{l10n}->datestr($rel->{released}); end;
         td class => 'tc2', $rel->{minage} < 0 ? '' : minage $rel->{minage};
         td class => 'tc3';
          for (sort @{$rel->{platforms}}) {
            next if $_ eq 'oth';
            cssicon $_, mt "_plat_$_";
          }
          cssicon "lang $_", mt "_lang_$_" for (@{$rel->{languages}});
          cssicon "rt$rel->{type}", mt "_rtype_$rel->{type}";
         end;
         td class => 'tc4';
          a href => "/r$rel->{id}", title => $rel->{original}||$rel->{title}, $rel->{title};
          b class => 'grayedout', ' '.mt '_vnpage_rel_patch' if $rel->{patch};
         end;
         td class => 'tc5', join ', ',
           ($rel->{developer} ? mt '_prodpage_dev' : ()), ($rel->{publisher} ? mt '_prodpage_pub' : ());
         td class => 'tc6';
          if($rel->{website}) {
            a href => $rel->{website}, rel => 'nofollow';
             cssicon 'ext', mt '_vnpage_rel_extlink';
            end;
          } else {
            txt ' ';
          }
         end;
        end 'tr';
      }
    }
   end 'table';
  end 'div';
}


# pid as argument = edit producer
# no arguments = add new producer
sub edit {
  my($self, $pid, $rev) = @_;

  my $p = $pid && $self->dbProducerGet(id => $pid, what => 'changes extended relations', $rev ? (rev => $rev) : ())->[0];
  return $self->resNotFound if $pid && !$p->{id};
  $rev = undef if !$p || $p->{cid} == $p->{latest};

  return $self->htmlDenied if !$self->authCan('edit')
    || $pid && (($p->{locked} || $p->{hidden}) && !$self->authCan('dbmod'));

  my %b4 = !$pid ? () : (
    (map { $_ => $p->{$_} } qw|type name original lang website desc alias ihid ilock|),
    l_wp => $p->{l_wp} || '',
    prodrelations => join('|||', map $_->{relation}.','.$_->{id}.','.$_->{name}, sort { $a->{id} <=> $b->{id} } @{$p->{relations}}),
  );
  my $frm;

  if($self->reqMethod eq 'POST') {
    return if !$self->authCheckCode;
    $frm = $self->formValidate(
      { post => 'type',          enum      => $self->{producer_types} },
      { post => 'name',          maxlength => 200 },
      { post => 'original',      required  => 0, maxlength => 200,  default => '' },
      { post => 'alias',         required  => 0, maxlength => 500,  default => '' },
      { post => 'lang',          enum      => $self->{languages} },
      { post => 'website',       required  => 0, maxlength => 250,  default => '', template => 'url' },
      { post => 'l_wp',          required  => 0, maxlength => 150,  default => '' },
      { post => 'desc',          required  => 0, maxlength => 5000, default => '' },
      { post => 'prodrelations', required  => 0, maxlength => 5000, default => '' },
      { post => 'editsum',       required  => 0, maxlength => 5000 },
      { post => 'ihid',          required  => 0 },
      { post => 'ilock',         required  => 0 },
    );
    push @{$frm->{_err}}, 'badeditsum' if !$frm->{editsum} || lc($frm->{editsum}) eq lc($frm->{desc});
    if(!$frm->{_err}) {
      # parse
      my $relations = [ map { /^([a-z]+),([0-9]+),(.+)$/ && (!$pid || $2 != $pid) ? [ $1, $2, $3 ] : () } split /\|\|\|/, $frm->{prodrelations} ];

      # normalize
      $frm->{ihid} = $frm->{ihid}?1:0;
      $frm->{ilock} = $frm->{ilock}?1:0;
      $relations = [] if $frm->{ihid};
      $frm->{prodrelations} = join '|||', map $_->[0].','.$_->[1].','.$_->[2], sort { $a->[1] <=> $b->[1]} @{$relations};

      return $self->resRedirect("/p$pid", 'post')
        if $pid && !grep $frm->{$_} ne $b4{$_}, keys %b4;

      $frm->{relations} = $relations;
      $frm->{l_wp} = undef if !$frm->{l_wp};
      my $nrev = $self->dbItemEdit(p => $pid ? $p->{cid} : undef, %$frm);

      # update reverse relations
      if(!$pid && $#$relations >= 0 || $pid && $frm->{prodrelations} ne $b4{prodrelations}) {
        my %old = $pid ? (map { $_->{id} => $_->{relation} } @{$p->{relations}}) : ();
        my %new = map { $_->[1] => $_->[0] } @$relations;
        _updreverse($self, \%old, \%new, $nrev->{iid}, $nrev->{rev});
      }

      return $self->resRedirect("/p$nrev->{iid}.$nrev->{rev}", 'post');
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
      end 'table';
    }],
  ]);
  $self->htmlFooter;
}

sub _updreverse {
  my($self, $old, $new, $pid, $rev) = @_;
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
    my $r = $self->dbProducerGet(id => $i, what => 'relations')->[0];
    my @newrel = map $_->{id} != $pid ? [ $_->{relation}, $_->{id} ] : (), @{$r->{relations}};
    push @newrel, [ $upd{$i}, $pid ] if $upd{$i};
    $self->dbItemEdit(p => $r->{cid},
      relations => \@newrel,
      editsum => "Reverse relation update caused by revision p$pid.$rev",
      uid => 1,
    );
  }
}


sub list {
  my($self, $char) = @_;

  my $f = $self->formValidate(
    { get => 'p', required => 0, default => 1, template => 'int' },
    { get => 'q', required => 0, default => '' },
  );
  return $self->resNotFound if $f->{_err};

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
  end 'div';
  $self->htmlBrowseNavigate($pageurl, $f->{p}, $np, 'b');
  $self->htmlFooter;
}


# peforms a (simple) search and returns the results in XML format
sub pxml {
  my $self = shift;

  my $q = $self->formValidate({ get => 'q', maxlength => 500 });
  return $self->resNotFound if $q->{_err};
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

