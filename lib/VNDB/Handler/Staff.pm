
package VNDB::Handler::Staff;

use strict;
use warnings;
use TUWF qw(:html :xml uri_escape xml_escape);
use VNDB::Func;
use List::Util qw(first);

TUWF::register(
  qr{s([1-9]\d*)(?:\.([1-9]\d*))?} => \&page,
  qr{s(?:([1-9]\d*)(?:\.([1-9]\d*))?/edit|/new)}
    => \&edit,
  qr{s/([a-z0]|all)}               => \&list,
  qr{xml/staff\.xml}               => \&staffxml,
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
      [ l_site    => diff => 1 ],
      [ l_wp      => htmlize => sub {
        $_[0] ? sprintf '<a href="http://en.wikipedia.org/wiki/%s">%1$s</a>', xml_escape $_[0] : mt '_revision_nolink'
      }],
      [ l_twitter => diff => 1 ],
      [ l_anidb   => serialize => sub { $_[0] // '' } ],
      [ desc      => diff => qr/[ ,\n\.]/ ],
      [ aliases   => join => '<br />', split => sub {
        map xml_escape(sprintf('%s%s', $_->{name}, $_->{original} ? ' ('.$_->{original}.')' : '')), @{$_[0]};
      }],
    );
  }

  div class => 'mainbox staffpage';
   $self->htmlItemMessage('s', $s);
   h1 $s->{name};
   h2 class => 'alttitle', $s->{original} if $s->{original};

   # info table
   table class => 'stripe';
    thead;
     Tr;
      td colspan => 2;
       b style => 'margin-right: 10px', $s->{name};
       b class => 'grayedout', style => 'margin-right: 10px', $s->{original} if $s->{original};
       cssicon "gen $s->{gender}", mt "_gender_$s->{gender}" if $s->{gender} ne 'unknown';
      end;
     end;
    end;
    Tr;
     td class => 'key', mt '_staff_language';
     td mt "_lang_$s->{lang}";
    end;
    if(@{$s->{aliases}}) {
      Tr;
       td class => 'key', mt('_staff_aliases', scalar @{$s->{aliases}});
       td;
        table class => 'aliases';
         for my $alias (@{$s->{aliases}}) {
           Tr class => 'nostripe';
            td $alias->{original} ? () : (colspan => 2), class => 'key';
             txt $alias->{name};
            end;
            td $alias->{original} if $alias->{original};
           end;
         }
        end;
       end;
      end;
    }
    my @links = (
      $s->{l_site} ?    [ 'site',    $s->{l_site} ] : (),
      $s->{l_wp} ?      [ 'wp',      "http://en.wikipedia.org/wiki/$s->{l_wp}" ] : (),
      $s->{l_twitter} ? [ 'twitter', "https://twitter.com/$s->{l_twitter}" ] : (),
      $s->{l_anidb} ?   [ 'anidb',   "http://anidb.net/cr$s->{l_anidb}" ] : (),
    );
    if(@links) {
      Tr;
       td class => 'key', mt '_staff_links';
       td;
        for(@links) {
          a href => $_->[1], mt "_staff_l_$_->[0]";
          br if $_ != $links[$#links];
        }
       end;
      end;
    }
   end 'table';

   # description
   p class => 'description';
    lit bb2html $s->{desc}, 0, 1;
   end;
  end;

  _roles($self, $s);
  _cast($self, $s);
  $self->htmlFooter;
}


sub _roles {
  my($self, $s) = @_;
  return if !@{$s->{roles}};

  h1 class => 'boxtitle', mt '_staff_credits';
  $self->htmlBrowse(
    items    => $s->{roles},
    class    => 'staffroles',
    header   => [
      [ mt '_staff_col_title' ],
      [ mt '_staff_col_released' ],
      [ mt '_staff_col_role' ],
      [ mt '_staff_col_as' ],
      [ mt '_staff_col_note' ],
    ],
    row     => sub {
      my($r, $n, $l) = @_;
      Tr;
       td class => 'tc1'; a href => "/v$l->{vid}", title => $l->{t_original}||$l->{title}, shorten $l->{title}, 60; end;
       td class => 'tc2'; lit $self->{l10n}->datestr($l->{c_released}); end;
       td class => 'tc3', mt '_credit_'.$l->{role};
       td class => 'tc4', title => $l->{original}||$l->{name}, $l->{name};
       td class => 'tc5', $l->{note};
      end;
    },
  );
}


sub _cast {
  my($self, $s) = @_;
  return if !@{$s->{cast}};

  h1 class => 'boxtitle', mt '_staff_voiced', scalar @{$s->{cast}};
  $self->htmlBrowse(
    items    => $s->{cast},
    class    => 'staffroles',
    header   => [
      [ mt '_staff_col_title' ],
      [ mt '_staff_col_released' ],
      [ mt '_staff_col_cast' ],
      [ mt '_staff_col_as' ],
      [ mt '_staff_col_note' ],
    ],
    row     => sub {
      my($r, $n, $l) = @_;
      Tr;
       td class => 'tc1'; a href => "/v$l->{vid}", title => $l->{t_original}||$l->{title}, shorten $l->{title}, 60; end;
       td class => 'tc2'; lit $self->{l10n}->datestr($l->{c_released}); end;
       td class => 'tc3'; a href => "/c$l->{cid}", title => $l->{c_original}, $l->{c_name}; end;
       td class => 'tc4', title => $l->{original}||$l->{name}, $l->{name};
       td class => 'tc5', $l->{note};
      end;
    },
  );
}


sub edit {
  my($self, $sid, $rev) = @_;

  my $s = $sid && $self->dbStaffGet(id => $sid, what => 'changes extended aliases', $rev ? (rev => $rev) : ())->[0];
  return $self->resNotFound if $sid && !$s->{id};
  $rev = undef if !$s || $s->{cid} == $s->{latest};

  return $self->htmlDenied if !$self->authCan('staffedit')
    || $sid && (($s->{locked} || $s->{hidden}) && !$self->authCan('dbmod'));

  my %b4 = !$sid ? () : (
    (map { $_ => $s->{$_} } qw|name original gender lang desc l_wp l_site l_twitter l_anidb ihid ilock|),
    primary => $s->{aid},
    aliases => [
      map +{ aid => $_->{id}, name => $_->{name}, orig => $_->{original} },
      sort { $a->{name} cmp $b->{name} || $a->{original} cmp $b->{original} } @{$s->{aliases}}
    ],
  );
  my $frm;

  if ($self->reqMethod eq 'POST') {
    return if !$self->authCheckCode;
    $frm = $self->formValidate (
      { post => 'name',          maxlength => 200 },
      { post => 'original',      required  => 0, maxlength => 200,  default => '' },
      { post => 'primary',       required  => 0, template => 'id', default => 0 },
      { post => 'desc',          required  => 0, maxlength => 5000, default => '' },
      { post => 'gender',        required  => 0, default => 'unknown', enum => [qw|unknown m f|] },
      { post => 'lang',          enum      => $self->{languages} },
      { post => 'l_wp',          required  => 0, maxlength => 150,  default => '' },
      { post => 'l_site',        required => 0, template => 'weburl', maxlength => 250, default => '' },
      { post => 'l_twitter',     required => 0, maxlength => 16, default => '', regex => [ qr/^\S+$/, mt('_staffe_form_tw_err') ] },
      { post => 'l_anidb',       required => 0, template => 'id', default => undef },
      { post => 'aliases',       template => 'json', json_sort => ['name','orig'], json_fields => [
        { field => 'name', required => 1, maxlength => 200 },
        { field => 'orig', required => 0, maxlength => 200, default => '' },
        { field => 'aid',  required => 0, template => 'id', default => 0 },
      ]},
      { post => 'editsum',       template => 'editsum' },
      { post => 'ihid',          required  => 0 },
      { post => 'ilock',         required  => 0 },
    );

    if(!$frm->{_err}) {
      my %old_aliases = $sid ? ( map +($_->{id} => 1), @{$self->dbStaffAliasIds($sid)} ) : ();
      $frm->{primary} = 0 unless exists $old_aliases{$frm->{primary}};

      # reset aid to zero for newly added aliases.
      $_->{aid} *= $old_aliases{$_->{aid}} ? 1 : 0 for(@{$frm->{aliases}});

      $frm->{ihid}   = $frm->{ihid} ?1:0;
      $frm->{ilock}  = $frm->{ilock}?1:0;
      $frm->{aid}    = $frm->{primary} if $sid;
      $frm->{desc}   = $self->bbSubstLinks($frm->{desc});
      return $self->resRedirect("/s$sid", 'post') if $sid && !form_compare(\%b4, $frm);

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
    [ hidden => short => 'name' ],
    [ hidden => short => 'original' ],
    [ hidden => short => 'primary' ],
    [ json   => short => 'aliases' ],
    $sid && @{$s->{aliases}} ?
      [ static => content => mt('_staffe_form_different') ] : (),
    [ static => label => mt('_staffe_form_names'), content => sub {
      table id => 'names';
       thead; Tr;
        td class => 'tc_id'; end;
        td class => 'tc_name', mt '_staffe_form_name';
        td class => 'tc_original', mt '_staffe_form_original'; td; end;
       end; end;
       tbody id => 'alias_tbl';
        # filled with javascript
       end;
      end;
    }],
    [ static => content => '<br />' ],
    [ text   => name => mt('_staffe_form_note').'<br /><b class="standout">'.mt('_inenglish').'</b>', short => 'desc', rows => 4 ],
    [ select => name => mt('_staffe_form_gender'),short => 'gender', options => [
       map [ $_, mt("_gender_$_") ], qw(unknown m f) ] ],
    [ select => name => mt('_staffe_form_lang'), short => 'lang',
      options => [ map [ $_, "$_ (".mt("_lang_$_").')' ], sort @{$self->{languages}} ] ],
    [ input  => name => mt('_staffe_form_site'), short => 'l_site' ],
    [ input  => name => mt('_staffe_form_wikipedia'), short => 'l_wp', pre => 'http://en.wikipedia.org/wiki/' ],
    [ input  => name => mt('_staffe_form_twitter'), short => 'l_twitter' ],
    [ input  => name => mt('_staffe_form_anidb'), short => 'l_anidb' ],
    [ static => content => '<br />' ],
  ]);

  $self->htmlFooter;
}


sub list {
  my ($self, $char) = @_;

  my $f = $self->formValidate(
    { get => 'p', required => 0, default => 1, template => 'page' },
    { get => 'q', required => 0, default => '' },
    { get => 'fil', required => 0, default => '' },
  );
  return $self->resNotFound if $f->{_err};

  my ($list, $np) = $self->filFetchDB(staff => $f->{fil}, {}, {
    $char ne 'all' ? ( char => $char ) : (),
    $f->{q} ? ( search => $f->{q} ) : (),
    results => 150,
    page => $f->{p}
  });

  return $self->resRedirect('/s'.$list->[0]{id}, 'temp')
    if $f->{q} && @$list && (!first { $_->{id} != $list->[0]{id} } @$list) && $f->{p} == 1 && !$f->{fil};
    # redirect to the staff page if all results refer to the same entry

  my $quri = join(';', $f->{q} ? 'q='.uri_escape($f->{q}) : (), $f->{fil} ? "fil=$f->{fil}" : ());
  $quri = '?'.$quri if $quri;
  my $pageurl = "/s/$char$quri";

  $self->htmlHeader(title => mt '_sbrowse_title');

  form action => '/s/all', 'accept-charset' => 'UTF-8', method => 'get';
   div class => 'mainbox';
    h1 mt '_sbrowse_title';
    $self->htmlSearchBox('s', $f->{q});
    p class => 'browseopts';
    for ('all', 'a'..'z', 0) {
      a href => "/s/$_$quri", $_ eq $char ? (class => 'optselected') : (), $_ eq 'all' ? mt('_char_all') : $_ ? uc $_ : '#';
    }
    end;

    a id => 'filselect', href => '#s';
     lit '<i>&#9656;</i> '.mt('_js_fil_filters').'<i></i>';
    end;
    input type => 'hidden', class => 'hidden', name => 'fil', id => 'fil', value => $f->{fil};
   end;
  end 'form';

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
    { get => 'a', required => 0, multi => 1, template => 'id' },
    { get => 's', required => 0, multi => 1, template => 'id' },
    { get => 'q', required => 0, maxlength => 500 },
  );
  return $self->resNotFound if $q->{_err} || !(@{$q->{s}} || @{$q->{a}} || $q->{q});

  my($list, $np) = $self->dbStaffGet(
    @{$q->{s}} ? (id => $q->{s}) :
    @{$q->{a}} ? (aid => $q->{a}) :
    $q->{q} =~ /^=(.+)/ ? (exact => $1) :
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
