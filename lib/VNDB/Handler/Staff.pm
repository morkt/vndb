
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

  my $method = $rev ? 'dbStaffGetRev' : 'dbStaffGet';
  my $s = $self->$method(
    id => $id,
    what => 'extended aliases roles',
    $rev ? ( rev => $rev ) : ()
  )->[0];
  return $self->resNotFound if !$s->{id};

  $self->htmlHeader(title => $s->{name}, noindex => $rev);
  $self->htmlMainTabs('s', $s) if $id;
  return if $self->htmlHiddenMessage('s', $s);

  if($rev) {
    my $prev = $rev && $rev > 1 && $self->dbStaffGetRev(id => $id, rev => $rev-1, what => 'extended aliases')->[0];
    $self->htmlRevision('s', $prev, $s,
      [ name      => 'Name (romaji)',    diff => 1 ],
      [ original  => 'Original name',    diff => 1 ],
      [ gender    => 'Gender',           serialize => sub { $self->{genders}{$_[0]} } ],
      [ lang      => 'Language',         serialize => sub { "$_[0] ($self->{languages}{$_[0]})" } ],
      [ l_site    => 'Official page',    diff => 1 ],
      [ l_wp      => 'Wikipedia link',   htmlize => sub {
        $_[0] ? sprintf '<a href="http://en.wikipedia.org/wiki/%s">%1$s</a>', xml_escape $_[0] : '[empty]'
      }],
      [ l_twitter => 'Twitter account',  diff => 1 ],
      [ l_anidb   => 'AniDB creator ID', serialize => sub { $_[0] // '' } ],
      [ desc      => 'Description',      diff => qr/[ ,\n\.]/ ],
      [ aliases   => 'Aliases',          join => '<br />', split => sub {
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
       cssicon "gen $s->{gender}", $self->{genders}{$s->{gender}} if $s->{gender} ne 'unknown';
      end;
     end;
    end;
    Tr;
     td class => 'key', 'Language';
     td $self->{languages}{$s->{lang}};
    end;
    if(@{$s->{aliases}}) {
      Tr;
       td class => 'key', @{$s->{aliases}} == 1 ? 'Alias' : 'Aliases';
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
      $s->{l_site} ?    [ 'Official page', $s->{l_site} ] : (),
      $s->{l_wp} ?      [ 'Wikipedia',    "http://en.wikipedia.org/wiki/$s->{l_wp}" ] : (),
      $s->{l_twitter} ? [ 'Twitter',      "https://twitter.com/$s->{l_twitter}" ] : (),
      $s->{l_anidb} ?   [ 'AniDB',        "http://anidb.net/cr$s->{l_anidb}" ] : (),
    );
    if(@links) {
      Tr;
       td class => 'key', 'Links';
       td;
        for(@links) {
          a href => $_->[1], $_->[0];
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

  h1 class => 'boxtitle', 'Credits';
  $self->htmlBrowse(
    items    => $s->{roles},
    class    => 'staffroles',
    header   => [
      [ 'Title' ],
      [ 'Released' ],
      [ 'Role' ],
      [ 'As' ],
      [ 'Note' ],
    ],
    row     => sub {
      my($r, $n, $l) = @_;
      Tr;
       td class => 'tc1'; a href => "/v$l->{vid}", title => $l->{t_original}||$l->{title}, shorten $l->{title}, 60; end;
       td class => 'tc2'; lit fmtdatestr $l->{c_released}; end;
       td class => 'tc3', $self->{staff_roles}{$l->{role}};
       td class => 'tc4', title => $l->{original}||$l->{name}, $l->{name};
       td class => 'tc5', $l->{note};
      end;
    },
  );
}


sub _cast {
  my($self, $s) = @_;
  return if !@{$s->{cast}};

  h1 class => 'boxtitle', sprintf 'Voiced characters (%d)', scalar @{$s->{cast}};
  $self->htmlBrowse(
    items    => $s->{cast},
    class    => 'staffroles',
    header   => [
      [ 'Title' ],
      [ 'Released' ],
      [ 'Cast' ],
      [ 'As' ],
      [ 'Note' ],
    ],
    row     => sub {
      my($r, $n, $l) = @_;
      Tr;
       td class => 'tc1'; a href => "/v$l->{vid}", title => $l->{t_original}||$l->{title}, shorten $l->{title}, 60; end;
       td class => 'tc2'; lit fmtdatestr $l->{c_released}; end;
       td class => 'tc3'; a href => "/c$l->{cid}", title => $l->{c_original}, $l->{c_name}; end;
       td class => 'tc4', title => $l->{original}||$l->{name}, $l->{name};
       td class => 'tc5', $l->{note};
      end;
    },
  );
}


sub edit {
  my($self, $sid, $rev) = @_;

  my $s = $sid && $self->dbStaffGetRev(id => $sid, what => 'extended aliases roles', $rev ? (rev => $rev) : ())->[0];
  return $self->resNotFound if $sid && !$s->{id};
  $rev = undef if !$s || $s->{lastrev};

  return $self->htmlDenied if !$self->authCan('edit')
    || $sid && (($s->{locked} || $s->{hidden}) && !$self->authCan('dbmod'));

  my %b4 = !$sid ? () : (
    (map { $_ => $s->{$_} } qw|name original gender lang desc l_wp l_site l_twitter l_anidb ihid ilock|),
    primary => $s->{aid},
    aliases => [
      map +{ aid => $_->{aid}, name => $_->{name}, orig => $_->{original} },
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
      { post => 'lang',          enum      => [ keys %{$self->{languages}} ] },
      { post => 'l_wp',          required  => 0, maxlength => 150,  default => '' },
      { post => 'l_site',        required => 0, template => 'weburl', maxlength => 250, default => '' },
      { post => 'l_twitter',     required => 0, maxlength => 16, default => '', regex => [ qr/^\S+$/, 'Invalid twitter username' ] },
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
      my %old_aliases = $sid ? ( map +($_->{aid} => 1), @{$self->dbStaffAliasIds($sid)} ) : ();
      $frm->{primary} = 0 unless exists $old_aliases{$frm->{primary}};

      # reset aid to zero for newly added aliases.
      $_->{aid} *= $old_aliases{$_->{aid}} ? 1 : 0 for(@{$frm->{aliases}});

      # Make sure no aliases that have been linked to a VN are removed.
      my %new_aliases = map +($_, 1), grep $_, $frm->{primary}, map $_->{aid}, @{$frm->{aliases}};
      $frm->{_err} = [ "Can't remove an alias that is still linked to a VN." ]
        if grep !$new_aliases{$_->{aid}}, @{$s->{roles}}, @{$self->{cast}};
    }

    if(!$frm->{_err}) {
      $frm->{ihid}   = $frm->{ihid} ?1:0;
      $frm->{ilock}  = $frm->{ilock}?1:0;
      $frm->{aid}    = $frm->{primary} if $sid;
      $frm->{desc}   = $self->bbSubstLinks($frm->{desc});
      return $self->resRedirect("/s$sid", 'post') if $sid && !form_compare(\%b4, $frm);

      my $nrev = $self->dbItemEdit(s => $sid ? ($s->{id}, $s->{rev}) : (undef, undef), %$frm);
      return $self->resRedirect("/s$nrev->{itemid}.$nrev->{rev}", 'post');
    }
  }

  $frm->{$_} //= $b4{$_} for keys %b4;
  $frm->{editsum} //= sprintf 'Reverted to revision s%d.%d', $sid, $rev if $rev;
  $frm->{lang} = 'ja' if !$sid && !defined $frm->{lang};

  my $title = $s ? "Edit $s->{name}" : 'Add staff member';
  $self->htmlHeader(title => $title, noindex => 1);
  $self->htmlMainTabs('s', $s, 'edit') if $s;
  $self->htmlEditMessage('s', $s, $title);
  $self->htmlForm({ frm => $frm, action => $s ? "/s$sid/edit" : '/s/new', editsum => 1 },
  staffe_geninfo => [ 'General info',
    [ hidden => short => 'name' ],
    [ hidden => short => 'original' ],
    [ hidden => short => 'primary' ],
    [ json   => short => 'aliases' ],
    $sid && @{$s->{aliases}} ?
      [ static => content => 'You may choose a different primary name.' ] : (),
    [ static => label => 'Names', content => sub {
      table id => 'names';
       thead; Tr;
        td class => 'tc_id'; end;
        td class => 'tc_name', 'Name (romaji)';
        td class => 'tc_original', 'Original'; td; end;
       end; end;
       tbody id => 'alias_tbl';
        # filled with javascript
       end;
      end;
    }],
    [ static => content => '<br />' ],
    [ text   => name => 'Staff note<br /><b class="standout">English please!</b>', short => 'desc', rows => 4 ],
    [ select => name => 'Gender',short => 'gender', options => [
       map [ $_, $self->{genders}{$_} ], qw(unknown m f) ] ],
    [ select => name => 'Primary language', short => 'lang',
      options => [ map [ $_, "$_ ($self->{languages}{$_})" ], keys %{$self->{languages}} ] ],
    [ input  => name => 'Official page', short => 'l_site' ],
    [ input  => name => 'Wikipedia link', short => 'l_wp', pre => 'http://en.wikipedia.org/wiki/' ],
    [ input  => name => 'Twitter username', short => 'l_twitter' ],
    [ input  => name => 'AniDB creator ID', short => 'l_anidb' ],
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

  $self->htmlHeader(title => 'Browse staff');

  form action => '/s/all', 'accept-charset' => 'UTF-8', method => 'get';
   div class => 'mainbox';
    h1 'Browse staff';
    $self->htmlSearchBox('s', $f->{q});
    p class => 'browseopts';
    for ('all', 'a'..'z', 0) {
      a href => "/s/$_$quri", $_ eq $char ? (class => 'optselected') : (), $_ eq 'all' ? 'ALL' : $_ ? uc $_ : '#';
    }
    end;

    p class => 'filselect';
     a id => 'filselect', href => '#s';
      lit '<i>&#9656;</i> Filters<i></i>';
     end;
    end;
    input type => 'hidden', class => 'hidden', name => 'fil', id => 'fil', value => $f->{fil};
   end;
  end 'form';

  $self->htmlBrowseNavigate($pageurl, $f->{p}, $np, 't');
  div class => 'mainbox staffbrowse';
    h1 $f->{q} ? 'Search results' : 'Staff list';
    if(!@$list) {
      p 'No results found';
    } else {
      # spread the results over 3 equivalent-sized lists
      my $perlist = @$list/3 < 1 ? 1 : @$list/3;
      for my $c (0..(@$list < 3 ? $#$list : 2)) {
        ul;
        for ($perlist*$c..($perlist*($c+1))-1) {
          li;
            my $gender = $list->[$_]{gender};
            cssicon 'lang '.$list->[$_]{lang}, $self->{languages}{$list->[$_]{lang}};
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
