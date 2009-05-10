
package VNDB::Handler::Releases;

use strict;
use warnings;
use YAWF ':html';
use VNDB::Func;


YAWF::register(
  qr{r([1-9]\d*)(?:\.([1-9]\d*))?} => \&page,
  qr{(v)([1-9]\d*)/add}            => \&edit,
  qr{r}                            => \&browse,
  qr{r(?:([1-9]\d*)(?:\.([1-9]\d*))?/edit)}
    => \&edit,
);


sub page {
  my($self, $rid, $rev) = @_;

  my $r = $self->dbReleaseGet(
    id => $rid,
    what => 'vn extended producers platforms media'.($rev ? ' changes' : ''),
    $rev ? (rev => $rev) : (),
  )->[0];
  return 404 if !$r->{id};

  $self->htmlHeader(title => $r->{title}, noindex => $rev);
  $self->htmlMainTabs('r', $r);
  return if $self->htmlHiddenMessage('r', $r);

  if($rev) {
    my $prev = $rev && $rev > 1 && $self->dbReleaseGet(
      id => $rid, rev => $rev-1,
      what => 'vn extended producers platforms media changes'
    )->[0];
    $self->htmlRevision('r', $prev, $r,
      [ vn        => 'Relations',      join => '<br />', split => sub {
        map sprintf('<a href="/v%d" title="%s">%s</a>', $_->{vid}, $_->{original}||$_->{title}, shorten $_->{title}, 50), @{$_[0]};
      } ],
      [ type      => 'Type',           serialize => sub { $self->{release_types}[$_[0]] } ],
      [ patch     => 'Patch',          serialize => sub { $_[0] ? 'Patch' : 'Not a patch' } ],
      [ title     => 'Title (romaji)', diff => 1 ],
      [ original  => 'Original title', diff => 1 ],
      [ gtin      => 'JAN/UPC/EAN',    serialize => sub { $_[0]||'[none]' } ],
      [ catalog   => 'Catalog number', serialize => sub { $_[0]||'[none]' } ],
      [ language  => 'Language',       serialize => sub { $self->{languages}{$_[0]} } ],
      [ website   => 'Website',        ],
      [ released  => 'Release date',   htmlize   => sub { datestr $_[0] } ],
      [ minage    => 'Age rating',     serialize => sub { $self->{age_ratings}{$_[0]} } ],
      [ notes     => 'Notes',          diff => 1 ],
      [ platforms => 'Platforms',      join => ', ', split => sub { map $self->{platforms}{$_}, @{$_[0]} } ],
      [ media     => 'Media',          join => ', ', split => sub {
        map {
          my $med = $self->{media}{$_->{medium}};
          $med->[1] ? sprintf('%d %s%s', $_->{qty}, $med->[0], $_->{qty}>1?'s':'') : $med->[0]
        } @{$_[0]};
      } ],
      [ producers => 'Producers',      join => '<br />', split => sub {
        map sprintf('<a href="/p%d" title="%s">%s</a>', $_->{id}, $_->{original}||$_->{name}, shorten $_->{name}, 50), @{$_[0]};
      } ],
    );
  }

  div class => 'mainbox release';
   $self->htmlItemMessage('r', $r);
   h1 $r->{title};
   h2 class => 'alttitle', $r->{original} if $r->{original};

   _infotable($self, $r);

   if($r->{notes}) {
     p class => 'description';
      lit bb2html $r->{notes};
     end;
   }

  end;
  $self->htmlFooter;
}


sub _infotable {
  my($self, $r) = @_;
  table;
   my $i = 0;

   Tr ++$i % 2 ? (class => 'odd') : ();
    td class => 'key', 'Relation';
    td;
     for (@{$r->{vn}}) {
       a href => "/v$_->{vid}", title => $_->{original}||$_->{title}, shorten $_->{title}, 60;
       br if $_ != $r->{vn}[$#{$r->{vn}}];
     }
    end;
   end;

   Tr ++$i % 2 ? (class => 'odd') : ();
    td 'Title';
    td $r->{title};
   end;

   if($r->{original}) {
     Tr ++$i % 2 ? (class => 'odd') : ();
      td 'Original title';
      td $r->{original};
     end;
   }

   Tr ++$i % 2 ? (class => 'odd') : ();
    td 'Type';
    td;
     my $type = $self->{release_types}[$r->{type}];
     cssicon lc(substr $type, 0, 3), $type;
     txt ' '.$type;
     txt ' patch' if $r->{patch};
    end;
   end;

   Tr ++$i % 2 ? (class => 'odd') : ();
    td 'Language';
    td;
     cssicon "lang $r->{language}", $self->{languages}{$r->{language}};
     txt ' '.$self->{languages}{$r->{language}};
    end;
   end;

   if(@{$r->{platforms}}) {
     Tr ++$i % 2 ? (class => 'odd') : ();
      td 'Platform'.($#{$r->{platforms}} ? 's' : '');
      td;
       for(@{$r->{platforms}}) {
         cssicon $_, $self->{platforms}{$_};
         txt ' '.$self->{platforms}{$_};
         br if $_ ne $r->{platforms}[$#{$r->{platforms}}];
       }
      end;
     end;
   }

   if(@{$r->{media}}) {
     Tr ++$i % 2 ? (class => 'odd') : ();
      td 'Medi'.($#{$r->{media}} ? 'a' : 'um');
      td join ', ', map {
        my $med = $self->{media}{$_->{medium}};
        $med->[1] ? sprintf('%d %s%s', $_->{qty}, $med->[0], $_->{qty}>1?'s':'') : $med->[0]
      } @{$r->{media}};
     end;
   }

   Tr ++$i % 2 ? (class => 'odd') : ();
    td 'Released';
    td;
     lit datestr $r->{released};
    end;
   end;

   if($r->{minage} >= 0) {
     Tr ++$i % 2 ? (class => 'odd') : ();
      td 'Age rating';
      td $self->{age_ratings}{$r->{minage}};
     end;
   }

   if(@{$r->{producers}}) {
     Tr ++$i % 2 ? (class => 'odd') : ();
      td 'Producer'.($#{$r->{producers}} ? 's' : '');
      td;
       for (@{$r->{producers}}) {
         a href => "/p$_->{id}", title => $_->{original}||$_->{name}, shorten $_->{name}, 60;
         br if $_ != $r->{producers}[$#{$r->{producers}}];
       }
      end;
     end;
   }

   if($r->{gtin}) {
     Tr ++$i % 2 ? (class => 'odd') : ();
      td gtintype $r->{gtin};
      td $r->{gtin};
     end;
   }

   if($r->{catalog}) {
     Tr ++$i % 2 ? (class => 'odd') : ();
      td 'Catalog no.';
      td $r->{catalog};
     end;
   }

   if($r->{website}) {
     Tr ++$i % 2 ? (class => 'odd') : ();
      td 'Links';
      td;
       a href => $r->{website}, rel => 'nofollow', 'Official website';
      end;
     end;
   }

   if($self->authInfo->{id}) {
     my $rl = $self->dbVNListGet(uid => $self->authInfo->{id}, rid => $r->{id})->[0];
     Tr ++$i % 2 ? (class => 'odd') : ();
      td 'User options';
      td;
       Select id => 'listsel', name => 'listsel';
        option !$rl ? 'not in your list' : "Status: $self->{vn_rstat}[$rl->{rstat}] / $self->{vn_vstat}[$rl->{vstat}]";
        optgroup label => 'Set release status';
         option value => "r$_", $self->{vn_rstat}[$_]
           for (0..$#{$self->{vn_rstat}});
        end;
        optgroup label => 'Set play status';
         option value => "v$_", $self->{vn_vstat}[$_]
           for (0..$#{$self->{vn_vstat}});
        end;
        option value => 'del', 'remove from list' if $rl;
       end;
      end;
     end;
   }

  end;
}


# rid = \d   -> edit release
# rid = 'v'  -> add release to VN with id $rev
sub edit {
  my($self, $rid, $rev) = @_;

  my $vid = 0;
  if($rid eq 'v') {
    $vid = $rev;
    $rev = undef;
    $rid = 0;
  }

  my $r = $rid && $self->dbReleaseGet(id => $rid, what => 'vn extended producers platforms media changes', $rev ? (rev => $rev) : ())->[0];
  return 404 if $rid && !$r->{id};
  $rev = undef if !$r || $r->{cid} == $r->{latest};

  my $v = $vid && $self->dbVNGet(id => $vid)->[0];
  return 404 if $vid && !$v->{id};

  return $self->htmlDenied if !$self->authCan('edit')
    || $rid && ($r->{locked} && !$self->authCan('lock') || $r->{hidden} && !$self->authCan('del'));

  my $vn = $rid ? $r->{vn} : [{ vid => $vid, title => $v->{title} }];
  my %b4 = !$rid ? () : (
    (map { $_ => $r->{$_} } qw|type title original gtin catalog language website notes minage platforms patch|),
    released  => $r->{released} =~ /^([0-9]{4})([0-9]{2})([0-9]{2})$/ ? [ $1, $2, $3 ] : [ 0, 0, 0 ],
    media     => join(',',   sort map "$_->{medium} $_->{qty}", @{$r->{media}}),
    producers => join('|||', map "$_->{id},$_->{name}", sort { $a->{id} <=> $b->{id} } @{$r->{producers}}),
  );
  $b4{vn} = join('|||', map "$_->{vid},$_->{title}", @$vn);
  my $frm;

  if($self->reqMethod eq 'POST') {
    $frm = $self->formValidate(
      { name => 'type',      enum => [ 0..$#{$self->{release_types}} ] },
      { name => 'patch',     required => 0, default => 0 },
      { name => 'title',     maxlength => 250 },
      { name => 'original',  required => 0, default => '', maxlength => 250 },
      { name => 'gtin',      required => 0, default => '0',
        func => [ \&gtintype, 'Not a valid JAN/UPC/EAN code' ] },
      { name => 'catalog',   required => 0, default => '', maxlength => 50 },
      { name => 'language',  enum => [ keys %{$self->{languages}} ] },
      { name => 'website',   required => 0, default => '', template => 'url' },
      { name => 'released',  required => 0, default => 0, multi => 1, template => 'int' },
      { name => 'minage' ,   required => 0, default => -1, enum => [ keys %{$self->{age_ratings}} ] },
      { name => 'notes',     required => 0, default => '', maxlength => 10240 },
      { name => 'platforms', required => 0, default => '', multi => 1, enum => [ keys %{$self->{platforms}} ] },
      { name => 'media',     required => 0, default => '' },
      { name => 'producers', required => 0, default => '' },
      { name => 'vn',        maxlength => 5000 },
      { name => 'editsum',   maxlength => 5000 },
    );
    if(!$frm->{_err}) {
      # de-serialize
      my $released  = !$frm->{released}[0] ? 0 : $frm->{released}[0] == 9999 ? 99999999 :
        sprintf '%04d%02d%02d',  $frm->{released}[0], $frm->{released}[1]||99, $frm->{released}[2]||99;
      my $media     = [ map [ split / / ], split /,/, $frm->{media} ];
      my $producers = [ map { /^([0-9]+)/ ? $1 : () } split /\|\|\|/, $frm->{producers} ];
      my $new_vn    = [ map { /^([0-9]+)/ ? $1 : () } split /\|\|\|/, $frm->{vn} ];
      $frm->{platforms} = [ grep $_, @{$frm->{platforms}} ];
      $frm->{patch} = $frm->{patch} ? 1 : 0;

      return $self->resRedirect("/r$rid", 'post')
        if $rid && $released == $r->{released} &&
          (join(',', sort @{$b4{platforms}}) eq join(',', sort @{$frm->{platforms}})) &&
          (join(',', sort @$producers) eq join(',', sort map $_->{id}, @{$r->{producers}})) &&
          (join(',', sort @$new_vn) eq join(',', sort map $_->{vid}, @$vn)) &&
          !grep !/^(released|platforms|producers|vn)$/ && $frm->{$_} ne $b4{$_}, keys %b4;

      my %opts = (
        (map { $_ => $frm->{$_} } qw| type title original gtin catalog language website notes minage platforms editsum patch|),
        vn        => $new_vn,
        producers => $producers,
        media     => $media,
        released  => $released,
      );

      $rev = 1;
      ($rev) = $self->dbReleaseEdit($rid, %opts) if $rid;
      ($rid) = $self->dbReleaseAdd(%opts) if !$rid;

      $self->multiCmd("ircnotify r$rid.$rev");
      $self->vnCacheUpdate(@$new_vn, map $_->{vid}, @$vn);

      return $self->resRedirect("/r$rid.$rev", 'post');
    }
  }

  !defined $frm->{$_} && ($frm->{$_} = $b4{$_}) for keys %b4;
  $frm->{language} = 'ja' if !$rid && !defined $frm->{lang};
  $frm->{editsum} = sprintf 'Reverted to revision r%d.%d', $rid, $rev if $rev && !defined $frm->{editsum};

  $self->htmlHeader(js => 'forms', title => $rid ? 'Edit '.$r->{title} : 'Add release to '.$v->{title}, noindex => 1);
  $self->htmlMainTabs('r', $r, 'edit') if $rid;
  $self->htmlMainTabs('v', $v, 'edit') if $vid;
  $self->htmlEditMessage('r', $r);
  _form($self, $r, $v, $frm);
  $self->htmlFooter;
}


sub _form {
  my($self, $r, $v, $frm) = @_;

  $self->htmlForm({ frm => $frm, action => $r ? "/r$r->{id}/edit" : "/v$v->{id}/add", editsum => 1 },
  "General info" => [
    [ select => short => 'type',      name => 'Type',
      options => [ map [ $_, $self->{release_types}[$_] ], 0..$#{$self->{release_types}} ] ],
    [ check  => short => 'patch',     name => 'This release is a patch to another release.' ],
    [ input  => short => 'title',     name => 'Title (romaji)', width => 300 ],
    [ input  => short => 'original',  name => 'Original title', width => 300 ],
    [ static => content => 'The original title of this release, leave blank if it already is in the Latin alphabet.' ],
    [ select => short => 'language',  name => 'Language',
      options => [ map [ $_, "$_ ($self->{languages}{$_})" ], sort keys %{$self->{languages}} ] ],
    [ input  => short => 'gtin',      name => 'JAN/UPC/EAN' ],
    [ input  => short => 'catalog',   name => 'Catalog number' ],
    [ input  => short => 'website',   name => 'Official website' ],
    [ date   => short => 'released',  name => 'Release date' ],
    [ static => content => 'Leave month or day blank if they are unknown' ],
    [ select => short => 'minage', name => 'Age rating',
      options => [ map [ $_, $self->{age_ratings}{$_} ], sort { $a <=> $b } keys %{$self->{age_ratings}} ] ],
    [ textarea => short => 'notes', name => 'Notes' ],
    [ static => content => 'Miscellaneous notes/comments, information that does not fit in the above fields. '
       .'E.g.: Censored/uncensored or for which releases this patch applies. Max. 250 characters.' ],
  ],

  'Platforms & Media' => [
    [ hidden => short => 'media' ],
    [ static => nolabel => 1, content => sub {
      h2 'Platforms';
      div class => 'platforms';
       for my $p (sort keys %{$self->{platforms}}) {
         span;
          input type => 'checkbox', name => 'platforms', value => $p, id => $p,
            $frm->{platforms} && grep($_ eq $p, @{$frm->{platforms}}) ? (checked => 'checked') : ();
          label for => $p;
           cssicon $p, $self->{platforms}{$p};
           txt ' '.$self->{platforms}{$p};
          end;
         end;
       }
      end;

      h2 'Media';
      div id => 'media_div';
       Select;
        option value => $_, class => $self->{media}{$_}[1] ? 'qty' : 'noqty', $self->{media}{$_}[0]
          for (sort keys %{$self->{media}});
       end;
      end;
    }],
  ],

  'Producers' => [
    [ hidden => short => 'producers' ],
    [ static => nolabel => 1, content => sub {
      h2 'Selected producers';
      div id => 'producerssel';
      end;
      h2 'Add producer';
      div;
       input type => 'text', class => 'text';
       a href => '#', 'add';
      end;
    }],
  ],

  'Visual novels' => [
    [ hidden => short => 'vn' ],
    [ static => nolabel => 1, content => sub {
      h2 'Selected visual novels';
      div id => 'vnsel';
      end;
      h2 'Add visual novel';
      div;
       input type => 'text', class => 'text';
       a href => '#', 'add';
      end;
    }],
  ],
  );
}


sub browse {
  my $self = shift;

  my $f = $self->formValidate(
    { name => 'p',  required => 0, default => 1, template => 'int' },
    { name => 's',  required => 0, default => 'title', enum => [qw|released minage title|] },
    { name => 'o',  required => 0, default => 'a', enum => ['a', 'd'] },
    { name => 'q',  required => 0, default => '', maxlength => 500 },
    { name => 'ln', required => 0, multi => 1, default => '', enum => [ keys %{$self->{languages}} ] },
    { name => 'pl', required => 0, multi => 1, default => '', enum => [ keys %{$self->{platforms}} ] },
    { name => 'tp', required => 0, default => -1, enum => [ -1..$#{$self->{release_types}} ] },
    { name => 'pa', required => 0, default => 0, enum => [ 0..2 ] },
    { name => 'ma_m', required => 0, default => 0, enum => [ 0, 1 ] },
    { name => 'ma_a', required => 0, default => 0, enum => [ keys %{$self->{age_ratings}} ] },
    { name => 'mi', required => 0, default => 0, multi => 1, template => 'int' },
    { name => 'ma', required => 0, default => 9999, multi => 1, template => 'int' },
  );
  return 404 if $f->{_err};

  $f->{mi}[1] ||= 0; $f->{mi}[2] ||= 0;
  $f->{ma}[1] ||= 0; $f->{ma}[2] ||= 0;
  my $mindate  = !$f->{mi}[0] ? 0 : $f->{mi}[0] == 9999 ? 99999999 :
    sprintf '%04d%02d%02d',  $f->{mi}[0], $f->{mi}[1]||99, $f->{mi}[2]||99;
  my $maxdate  = !$f->{ma}[0] ? 0 : $f->{ma}[0] == 9999 ? 99999999 :
    sprintf '%04d%02d%02d',  $f->{ma}[0], $f->{ma}[1]||99, $f->{ma}[2]||99;

  my($list, $np) = $self->dbReleaseGet(
    order => $f->{s}.($f->{o}eq'd'?' DESC':' ASC'),
    page => $f->{p},
    results => 50,
    $mindate > 0 || $maxdate < 99990000 ? (date => [ $mindate, $maxdate ]) : (),
    $f->{q} ? (search => $f->{q}) : (),
    $f->{pl}[0] ? (platforms => $f->{pl}) : (),
    $f->{ln}[0] ? (languages => $f->{ln}) : (),
    $f->{tp} >= 0 ? (type => $f->{tp}) : (),
    $f->{ma_a} || $f->{ma_m} ? (minage => [$f->{ma_m}, $f->{ma_a}]) : (),
    $f->{pa} ? (patch => $f->{pa}) : (),
    what => 'platforms',
  );

  my $url = "/r?tp=$f->{tp};pa=$f->{pa};ma_m=$f->{ma_m};ma_a=$f->{ma_a};q=$f->{q}"
    .";mi=$f->{mi}[0];mi=$f->{mi}[1];mi=$f->{mi}[2];ma=$f->{ma}[0];ma=$f->{ma}[1];ma=$f->{ma}[2]";
  $_&&($url .= ";ln=$_") for @{$f->{ln}};
  $_&&($url .= ";pl=$_") for @{$f->{pl}};

  $self->htmlHeader(title => 'Browse releases');
  _filters($self, $f);
  $self->htmlBrowse(
    class    => 'relbrowse',
    items    => $list,
    options  => $f,
    nextpage => $np,
    pageurl  => "$url;s=$f->{s};o=$f->{o}",
    sorturl  => $url,
    header   => [
      [ 'Released', 'released' ],
      [ 'Rating',   'minage' ],
      [ '',         '' ],
      [ 'Title',    'title' ],
    ],
    row      => sub {
      my($s, $n, $l) = @_;
      Tr $n % 2 ? (class => 'odd') : ();
       td class => 'tc1';
        lit datestr $l->{released};
       end;
       td class => 'tc2', $l->{minage} > -1 ? $self->{age_ratings}{$l->{minage}} : '';
       td class => 'tc3';
        $_ ne 'oth' && cssicon $_, $self->{platforms}{$_} for (@{$l->{platforms}});
        cssicon "lang $l->{language}", $self->{languages}{$l->{language}};
        cssicon lc(substr($self->{release_types}[$l->{type}],0,3)), $self->{release_types}[$l->{type}];
       end;
       td class => 'tc4';
        a href => "/r$l->{id}", title => $l->{original}||$l->{title}, shorten $l->{title}, 90;
        b class => 'grayedout', ' (patch)' if $l->{patch};
       end;
      end;
    },
  );
  $self->htmlFooter;
}


sub _filters {
  my($self, $f) = @_;

  form method => 'get', action => '/r', 'accept-charset' => 'UTF-8';
  div class => 'mainbox';
   h1 'Browse releases';

   fieldset class => 'search';
    input type => 'text', name => 'q', id => 'q', class => 'text', value => $f->{q};
    input type => 'submit', class => 'submit', value => 'Search!';
   end;

   a id => 'advselect', href => '#';
    lit '<i>&#9656;</i> filters';
   end;
   div id => 'advoptions', class => 'hidden';

    h2 'Filters';
    table class => 'formtable', style => 'margin-left: 0';
     $self->htmlFormPart($f, [ select => short => 'tp', name => 'Release type',
       options => [ [-1, 'All'], map [ $_, $self->{release_types}[$_] ], 0..$#{$self->{release_types}} ]]);
     $self->htmlFormPart($f, [ select => short => 'pa', name => 'Patch status',
       options => [ [0, 'All'], [1, 'Only patches'], [2, 'Only standalone releases']]]);
     Tr class => 'newfield';
      td class => 'label'; label for => 'ma_m', 'Age rating'; end;
      td class => 'field';
       Select id => 'ma_m', name => 'ma_m', style => 'width: 70px';
        option value => 0, $f->{ma_m} == 0 ? ('selected' => 'selected') : (), 'greater';
        option value => 1, $f->{ma_m} == 1 ? ('selected' => 'selected') : (), 'smaller';
       end;
       txt ' than or equal to ';
       Select id => 'ma_a', name => 'ma_a', style => 'width: 80px; text-align: center';
        $_>=0 && option value => $_, $f->{ma_a} == $_ ? ('selected' => 'selected') : (), $self->{age_ratings}{$_}
          for (sort { $a <=> $b } keys %{$self->{age_ratings}});
       end;
      end;
     end;
     $self->htmlFormPart($f, [ date => short => 'mi', name => 'Released after' ]);
     $self->htmlFormPart($f, [ date => short => 'ma', name => 'Released before' ]);
    end;

    h2;
     lit 'Languages <b>(boolean or, selecting more gives more results)</b>';
    end;
    for my $i (sort @{$self->dbLanguages}) {
      span;
       input type => 'checkbox', name => 'ln', value => $i, id => "lang_$i", grep($_ eq $i, @{$f->{ln}}) ? (checked => 'checked') : ();
       label for => "lang_$i";
        cssicon "lang $i", $self->{languages}{$i};
        txt $self->{languages}{$i};
       end;
      end;
    }

    h2;
     lit 'Platforms <b>(boolean or, selecting more gives more results)</b>';
    end;
    for my $i (sort keys %{$self->{platforms}}) {
      next if $i eq 'oth';
      span;
       input type => 'checkbox', name => 'pl', value => $i, id => "plat_$i", grep($_ eq $i, @{$f->{pl}}) ? (checked => 'checked') : ();
       label for => "plat_$i";
        cssicon $i, $self->{platforms}{$i};
        txt $self->{platforms}{$i};
       end;
      end;
    }

    div style => 'text-align: center; clear: left;';
     input type => 'submit', value => 'Apply', class => 'submit';
    end;
   end;
  end;
  end;
}


1;

