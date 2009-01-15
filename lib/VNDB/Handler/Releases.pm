
package VNDB::Handler::Releases;

use strict;
use warnings;
use YAWF ':html';
use VNDB::Func;
use POSIX 'strftime';


YAWF::register(
  qr{r([1-9]\d*)(?:\.([1-9]\d*))?} => \&page,
  qr{(v)([1-9]\d*)/add}            => \&edit,
  qr{r(?:([1-9]\d*)(?:\.([1-9]\d*))?/edit)}
    => \&edit,
);


sub page {
  my($self, $rid, $rev) = @_;

  my $r = $self->dbReleaseGet(
    id => $rid,
    what => 'vn producers platforms media'.($rev ? ' changes' : ''),
    $rev ? (rev => $rev) : (),
  )->[0];
  return 404 if !$r->{id};

  $self->htmlHeader(title => $r->{title}, noindex => $rev);
  $self->htmlMainTabs('r', $r);
  return if $self->htmlHiddenMessage('r', $r);

  if($rev) {
    my $prev = $rev && $rev > 1 && $self->dbReleaseGet(
      id => $rid, rev => $rev-1,
      what => 'vn producers platforms media changes'
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
    td class => 'key', 'Title';
    td $r->{title};
   end;

   if($r->{original}) {
     Tr ++$i % 2 ? (class => 'odd') : ();
      td 'Original title';
      td $r->{original};
     end;
   }

   Tr ++$i % 2 ? (class => 'odd') : ();
    td 'Relation';
    td;
     for (@{$r->{vn}}) {
       a href => "/v$_->{vid}", title => $_->{original}||$_->{title}, shorten $_->{title}, 60;
       br if $_ != $r->{vn}[$#{$r->{vn}}];
     }
    end;
   end;

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

  my $r = $rid && $self->dbReleaseGet(id => $rid, what => 'vn producers platforms media changes', $rev ? (rev => $rev) : ())->[0];
  return 404 if $rid && !$r->{id};
  $rev = undef if !$r || $r->{cid} == $r->{latest};

  my $v = $vid && $self->dbVNGet(id => $vid)->[0];
  return 404 if $vid && !$v->{id};

  return $self->htmlDenied if !$self->authCan('edit')
    || $rid && ($r->{locked} && !$self->authCan('lock') || $r->{hidden} && !$self->authCan('del'));

  my $vn = $rid ? $r->{vn} : [{ vid => $vid, title => $v->{title} }];
  my %b4 = !$rid ? () : (
    (map { $_ => $r->{$_} } qw|type title original gtin language website notes minage platforms patch|),
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
        (map { $_ => $frm->{$_} } qw| type title original gtin language website notes minage platforms editsum patch|),
        vn        => $new_vn,
        producers => $producers,
        media     => $media,
        released  => $released,
      );

      $rev = 1;
      ($rev) = $self->dbReleaseEdit($rid, %opts) if $rid;
      ($rid) = $self->dbReleaseAdd(%opts) if !$rid;

      $self->multiCmd("ircnotify r$rid.$rev");
      _update_vncache($self, @$new_vn, map $_->{vid}, @$vn);

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
    [ check  => short => 'patch',     name => 'This release is a patch to an other release.' ],
    [ input  => short => 'title',     name => 'Title (romaji)', width => 300 ],
    [ input  => short => 'original',  name => 'Original title', width => 300 ],
    [ static => content => 'The original title of this release, leave blank if it already is in the Latin alphabet.' ],
    [ select => short => 'language',  name => 'Language',
      options => [ map [ $_, "$_ ($self->{languages}{$_})" ], sort keys %{$self->{languages}} ] ],
    [ input  => short => 'gtin',      name => 'JAN/UPC/EAN' ],
    [ input  => short => 'website',   name => 'Official website' ],
    [ static => label => 'Release date', content => sub {
      Select id => 'released', name => 'released';
       option value => $_, $frm->{released} && $frm->{released}[0] == $_ ? (selected => 'selected') : (),
          !$_ ? '-year-' : $_ < 9999 ? $_ : 'TBA'
         for (0, 1980..((localtime())[5]+1905), 9999);
      end;
      Select id => 'released_m', name => 'released';
       option value => $_, $frm->{released} && $frm->{released}[1] == $_ ? (selected => 'selected') : (),
          !$_ ? '-month-' : strftime '%B', 0, 0, 0, 0, $_, 0, 0, 0
         for(0..12);
      end;
      Select id => 'released_d', name => 'released';
       option value => $_, $frm->{released} && $frm->{released}[2] == $_ ? (selected => 'selected') : (),
          !$_ ? '-day-' : $_
         for(0..31);
      end;
    }],
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


# Recalculates the vn.c_* columns and regenerates the related relation graphs on any change
sub _update_vncache {
  my($self, @vns) = @_;

  my $before = $self->dbVNGet(id => \@vns, order => 'v.id', what => 'relations');
  $self->dbVNCache(@vns);
  my $after = $self->dbVNGet(id => \@vns, order => 'v.id');

  my @upd = map {
    @{$before->[$_]{relations}} && (
      $before->[$_]{c_released} != $after->[$_]{c_released}
      || $before->[$_]{c_languages} ne $after->[$_]{c_languages}
    ) ? $before->[$_]{id} : ();
  } 0..$#$before;
  $self->multiCmd('relgraph '.join(' ', @upd)) if @upd;
}


1;

