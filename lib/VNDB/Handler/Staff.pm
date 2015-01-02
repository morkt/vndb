
package VNDB::Handler::Staff;

use strict;
use warnings;
use TUWF qw(:html :xml xml_escape);
use VNDB::Func;
use List::Util qw(first);

TUWF::register(
  qr{s([1-9]\d*)(?:\.([1-9]\d*))?} => \&page,
  qr{s(?:([1-9]\d*)(?:\.([1-9]\d*))?/edit|/new)}
    => \&edit,
  qr{s/([a-z0]|all)}               => \&list,
  qr{xml/staff.xml}                => \&staffxml,
);

sub page {
  my($self, $id, $rev) = @_;

  my $s = $self->dbStaffGet(
    id => $id,
    what => 'extended aliases roles'.($rev ? ' changes' : ''),
    $rev ? ( rev => $rev ) : ()
  )->[0];
  return $self->resNotFound if !$s->{id};

  $self->htmlHeader(title => $s->{name}, noindex => $rev);
  $self->htmlMainTabs('s', $s) if $id;
  return if $self->htmlHiddenMessage('s', $s);

  if($rev) {
    my $prev = $rev && $rev > 1 && $self->dbStaffGet(id => $id, rev => $rev-1, what => 'changes extended aliases')->[0];
    $self->htmlRevision('s', $prev, $s,
      [ name      => diff => 1 ],
      [ original  => diff => 1 ],
      [ gender    => serialize => sub { mt "_gender_$_[0]" } ],
      [ lang      => serialize => sub { "$_[0] (".mt("_lang_$_[0]").')' } ],
      [ l_wp      => htmlize => sub {
        $_[0] ? sprintf '<a href="http://en.wikipedia.org/wiki/%s">%1$s</a>', xml_escape $_[0] : mt '_revision_nolink'
      }],
      [ desc      => diff => qr/[ ,\n\.]/ ],
#      [ image     => htmlize => sub {
#        return $_[0] ? sprintf '<img src="%s" />', imgurl(ch => $_[0]) : mt '_stdiff_image_none';
#      }],
      [ aliases   => join => '<br />', split => sub {
        map xml_escape(sprintf('%s%s', $_->{name}, $_->{original} ? ' ('.$_->{original}.')' : '')), @{$_[0]};
      }],
    );
  }

  div class => 'mainbox staffpage';
   $self->htmlItemMessage('s', $s);
   div class => 'staffinfo';
    h1 $s->{name};
    h2 class => 'alttitle';
     span style => 'margin-right: 10px', $s->{original} if $s->{original};
     cssicon "gen $s->{gender}", mt "_gender_$s->{gender}" if $s->{gender} ne 'unknown';
    end;

    # info table
    table class => 'stripe';

     Tr;
      td class => 'key', mt '_staff_language';
      td mt "_lang_$s->{lang}";
     end;
     if (@{$s->{aliases}}) {
       Tr;
        td class => 'key', mt '_staff_aliases';
        td;
         p;
          foreach my $alias (@{$s->{aliases}}) {
            txt $alias->{name};
            txt ' ('.$alias->{original}.')' if $alias->{original};
            br;
          }
         end;
        end;
       end;
     }
     if ($s->{l_wp}) {
       Tr;
        td colspan => 2;
         a href => "http://en.wikipedia.org/wiki/$s->{l_wp}", mt '_staff_l_wp';
        end;
       end;
     }
    end 'table';
   end;

   # description
   div class => 'staffdesc';
   if($s->{desc}) {
      h2 mt '_staff_bio';
      p;
       lit bb2html $s->{desc}, 0, 1;
      end;
      br;
   }

    if (@{$s->{roles}}) {
      h2 mt '_staff_credits';
      my $has_notes = first { $_->{note} || $_->{name} ne $s->{name} } @{$s->{roles}};
      table class => 'stripe staffroles';
       thead;
        Tr;
         td class => 'tc2', mt '_staff_col_title';
         td class => 'tc3', mt '_staff_col_released';
         td class => 'tc1', mt '_staff_col_role';
         td class => 'tc4', mt '_staff_col_note' if $has_notes;
        end;
       end;
       tbody;
        my ($last_vid, $row_count);
        for my $i (0..$#{$s->{roles}}) {
          my $r = $s->{roles}->[$i];
          if($r->{vid} != $last_vid) {
            $row_count = 1;
            for my $j (1+$i..$#{$s->{roles}}) {
              last if $r->{vid} != $s->{roles}->[$j]->{vid};
              ++$row_count;
            }
          }
          Tr;
           if($last_vid != $r->{vid}) {
             td class => 'tc2', $row_count > 1 ? (rowspan => $row_count) : ();
               a href => "/v$r->{vid}", title => $r->{t_original}||$r->{title}, shorten $r->{title}, 100;
             end;
             td class => 'tc3', $row_count > 1 ? (rowspan => $row_count) : ();
               lit $self->{l10n}->datestr($r->{c_released});
             end;
           }
           td class => 'tc1', mt '_credit_'.$r->{role};
           if($has_notes) {
             td class => 'tc4';
              txt '('.mt('_staff_as', $r->{name}).') ' if $r->{name} ne $s->{name};
              txt $r->{note};
             end;
           }
          end;
          $last_vid = $r->{vid};
        }
       end;
      end;
      br;
    }
    if (@{$s->{cast}}) {
      h2 mt '_staff_voiced';
      my $has_notes = first { $_->{note} || $_->{name} ne $s->{name} } @{$s->{cast}};
      table class => 'stripe staffroles';
       thead;
        Tr;
         td class => 'tc2', mt '_staff_col_title';
         td class => 'tc3', mt '_staff_col_released';
         td class => 'tc1', mt '_staff_col_cast';
         td class => 'tc4', mt '_staff_col_note' if $has_notes;
        end;
       end;
       tbody;
        foreach my $r (@{$s->{cast}}) {
          Tr;
           td class => 'tc2';
            a href => "/v$r->{vid}", title => $r->{t_original}||$r->{title}, shorten $r->{title}, 100;
           end;
           td class => 'tc3'; lit $self->{l10n}->datestr($r->{c_released}); end;
           td class => 'tc1'; a href => "/c$r->{cid}", title => $r->{c_original}, $r->{c_name}; end;
           if($has_notes) {
             td class => 'tc4';
              txt '('.mt('_staff_as', $r->{name}).') ' if $r->{name} ne $s->{name};
              txt $r->{note};
             end;
           }
          end;
        }
       end;
      end;
    }
   end;
   clearfloat;
  end;

  $self->htmlFooter;
}


sub edit {
  my($self, $sid, $rev) = @_;

  my $s = $sid && $self->dbStaffGet(id => $sid, what => 'changes extended aliases', $rev ? (rev => $rev) : ())->[0];
  return $self->resNotFound if $sid && !$s->{id};
  $rev = undef if !$s || $s->{cid} == $s->{latest};

  return $self->htmlDenied if !$self->authCan('edit')
    || $sid && (($s->{locked} || $s->{hidden}) && !$self->authCan('dbmod'));

  my %b4 = !$sid ? () : (
    (map { $_ => $s->{$_} } qw|aid name original gender lang desc l_wp ihid ilock|),
    aliases => jsonEncode [
      map +{ aid => $_->{id}, name => $_->{name}, orig => $_->{original} },
      sort { $a->{name} <=> $b->{name} } @{$s->{aliases}}
    ],
  );
  my $frm;

  if ($self->reqMethod eq 'POST') {
    return if !$self->authCheckCode;
    $frm = $self->formValidate (
      { post => 'aid',           required  => 0, template => 'int' },
      { post => 'name',          maxlength => 200 },
      { post => 'original',      required  => 0, maxlength => 200,  default => '' },
      { post => 'desc',          required  => 0, maxlength => 5000, default => '' },
      { post => 'gender',        required  => 0, default => 'unknown', enum => [qw|unknown m f|] },
      { post => 'lang',          enum      => $self->{languages} },
      { post => 'l_wp',          required  => 0, maxlength => 150,  default => '' },
      { post => 'image',         required  => 0, default => 0, template => 'int' },
      { post => 'aliases',       required  => 0, maxlength => 5000, default => '' },
      { post => 'editsum',       required  => 0, maxlength => 5000 },
      { post => 'ihid',          required  => 0 },
      { post => 'ilock',         required  => 0 },
    );
    push @{$frm->{_err}}, 'badeditsum' if !$frm->{editsum} || lc($frm->{editsum}) eq lc($frm->{desc});

    my $aliases = eval { jsonDecode $frm->{aliases} };
    push @{$frm->{_err}}, [ 'aliases', 'template', 'json' ] if $@;
    if(!$frm->{_err}) {
      for my $a (@$aliases) {
        # check for empty aliases
        if($a->{name} =~ /^\s*$/) {
          push @{$frm->{_err}}, ['alias_name', 'required'];
          last;
        }
      }
    }
    if(!$frm->{_err}) {
      # parse and normalize
      $frm->{aliases} = jsonEncode $aliases;
      $frm->{ihid}   = $frm->{ihid} ?1:0;
      $frm->{ilock}  = $frm->{ilock}?1:0;

      return $self->resRedirect("/s$sid", 'post')
        if $sid && !first { $frm->{$_} ne $b4{$_} } keys %b4;
    }
    if(!$frm->{_err}) {
      $frm->{aliases} = [ map [ @{$_}{qw|aid name orig|} ], @$aliases ];
      my $nrev = $self->dbItemEdit ('s' => $sid ? $s->{cid} : undef, %$frm);
      return $self->resRedirect("/s$nrev->{iid}.$nrev->{rev}", 'post');
    }
  }

  $frm->{$_} //= $b4{$_} for keys %b4;
  $frm->{editsum} //= sprintf 'Reverted to revision s%d.%d', $sid, $rev if $rev;
  $frm->{lang} = 'ja' if !$sid && !defined $frm->{lang};

  my $title = mt $s ? ('_staffe_title_edit', $s->{name}) : '_staffe_title_add';
  $self->htmlHeader(title => $title, noindex => 1);
  $self->htmlMainTabs('s', $s, 'edit') if $s;
  $self->htmlEditMessage('s', $s, $title);
  $self->htmlForm({ frm => $frm, action => $s ? "/s$sid/edit" : '/s/new', editsum => 1 },
  staffe_geninfo => [ mt('_staffe_form_generalinfo'),
    [ hidden => short => 'aid' ],
    [ input  => name => mt('_staffe_form_name'), short => 'name' ],
    [ input  => name => mt('_staffe_form_original'), short => 'original' ],
    [ static => content => mt('_staffe_form_original_note') ],
    [ text   => name => mt('_staffe_form_note').'<br /><b class="standout">'.mt('_inenglish').'</b>', short => 'desc', rows => 4 ],
    [ select => name => mt('_staffe_form_gender'),short => 'gender', options => [
       map [ $_, mt("_gender_$_") ], qw(unknown m f) ] ],
    [ select => name => mt('_staffe_form_lang'), short => 'lang',
      options => [ map [ $_, "$_ (".mt("_lang_$_").')' ], sort @{$self->{languages}} ] ],
    [ input  => name => mt('_staffe_form_wikipedia'), short => 'l_wp', pre => 'http://en.wikipedia.org/wiki/' ],
    [ static => content => '<br />' ],
  ],

  staffe_aliases => [ mt('_staffe_aliases'),
    [ hidden => short => 'aliases' ],
    [ static => nolabel => 1, content => sub {
      table;
       thead; Tr;
        td class => 'tc_name', mt '_staffe_form_alias';
        td class => 'tc_original', mt '_staffe_form_original_alias'; td; end;
       end; end;
       tbody id => 'alias_tbl';
        # filled with javascript
       end;
      end;
      h2 mt '_staffe_aliases_add';
      table; Tr id => 'alias_new';
       td class => 'tc_name';
        input id => 'alias_name', type => 'text', class => 'text'; end;
       td class => 'tc_original';
        input id => 'alias_original', type => 'text', class => 'text'; end;
       td class => 'tc_add';
        a href => '#', mt '_js_add'; end;
      end; end;
    }],
  ]);

  $self->htmlFooter;
}


sub list {
  my ($self, $char) = @_;

  my $f = $self->formValidate(
    { get => 'p', required => 0, default => 1, template => 'int' },
    { get => 'q', required => 0, default => '' },
  );
  return $self->resNotFound if $f->{_err};

  my ($list, $np) = $self->dbStaffGet(
    $char ne 'all' ? ( char => $char ) : (),
    $f->{q} ? ( search => $f->{q} ) : (),
    results => 150,
    page => $f->{p}
  );

  return $self->resRedirect('/s'.$list->[0]{id}, 'temp')
    if $f->{q} && @$list == 1 && $f->{p} == 1;

  $self->htmlHeader(title => mt '_sbrowse_title');

  div class => 'mainbox';
    h1 mt '_sbrowse_title';
    form action => '/s/all', 'accept-charset' => 'UTF-8', method => 'get';
      $self->htmlSearchBox('s', $f->{q});
    end;
    p class => 'browseopts';
    for ('all', 'a'..'z', 0) {
      a href => "/s/$_", $_ eq $char ? (class => 'optselected') : (), $_ eq 'all' ? mt('_char_all') : $_ ? uc $_ : '#';
    }
    end;
  end;

  my $pageurl = "/s/$char" . ($f->{q} ? "?q=$f->{q}" : '');
  $self->htmlBrowseNavigate($pageurl, $f->{p}, $np, 't');
  div class => 'mainbox staffbrowse';
    h1 mt $f->{q} ? '_sbrowse_searchres' : '_sbrowse_list';
    if(!@$list) {
      p mt '_sbrowse_noresults';
    } else {
      # spread the results over 3 equivalent-sized lists
      my $perlist = @$list/3 < 1 ? 1 : @$list/3;
      for my $c (0..(@$list < 3 ? $#$list : 2)) {
        ul;
        for ($perlist*$c..($perlist*($c+1))-1) {
          li;
            my $gender = $list->[$_]{gender};
#            cssicon "gen $gender", mt "_gender_$gender" if $gender ne 'unknown';
            cssicon 'lang '.$list->[$_]{lang}, mt "_lang_$list->[$_]{lang}";
            a href => "/s$list->[$_]{id}",
              title => $list->[$_]{original}, $list->[$_]{name};
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


sub staffxml {
  my $self = shift;

  my $q = $self->formValidate(
    { get => 'a', required => 0, multi => 1, template => 'int' },
    { get => 's', required => 0, multi => 1, template => 'int' },
    { get => 'q', required => 0, maxlength => 500 },
  );
  return $self->resNotFound if $q->{_err} || !(@{$q->{s}} || @{$q->{a}} || $q->{q});

  my($list, $np) = $self->dbStaffGet(
    @{$q->{s}} ? (id => $q->{s}) :
    @{$q->{a}} ? (aid => $q->{a}) :
    $q->{q} =~ /^s([1-9]\d*)/ ? (id => $1) :
    (search => $q->{q}),
    results => 10,
    page => 1,
  );

  $self->resHeader('Content-type' => 'text/xml; charset=UTF-8');
  xml;
  tag 'staff', more => $np ? 'yes' : 'no';
   for(@$list) {
     tag 'item', id => $_->{id}, aid => $_->{aid}, $_->{name};
   }
  end;
}

1;
__END__
