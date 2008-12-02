
package VNDB::Handler::Releases;

use strict;
use warnings;
use YAWF ':html';
use VNDB::Func;


YAWF::register(
  qr{r([1-9]\d*)(?:\.([1-9]\d*))?} => \&page,
);


sub page {
  my($self, $rid, $rev) = @_;

  my $r = $self->dbReleaseGet(
    id => $rid,
    what => 'vn producers platforms media'.($rev ? ' changes' : ''),
    $rev ? (rev => $rev) : (),
  )->[0];
  return 404 if !$r->{id};

  $self->htmlHeader(title => $r->{title});
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
   p class => 'locked', 'Locked for editing' if $r->{locked};
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
   Tr;
    td class => 'key', ' ';
    td ' ';
   end;
   my $i = 0;

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
     acronym class => 'icons '.lc(substr $type, 0, 3), title => $type, ' ';
     txt ' '.$type;
    end;
   end;

   Tr ++$i % 2 ? (class => 'odd') : ();
    td 'Language';
    td;
     acronym class => "icons lang $r->{language}", title => $self->{languages}{$r->{language}}, ' ';
     txt ' '.$self->{languages}{$r->{language}};
    end;
   end;

   if(@{$r->{platforms}}) {
     Tr ++$i % 2 ? (class => 'odd') : ();
      td 'Platform'.($#{$r->{platforms}} ? 's' : '');
      td;
       for(@{$r->{platforms}}) {
         acronym class => "icons $_", title => $self->{platforms}{$_}, ' ';
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

  end;
}



1;

