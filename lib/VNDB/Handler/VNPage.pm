
package VNDB::Handler::VNPage;

use strict;
use warnings;
use YAWF ':html';
use VNDB::Func;


YAWF::register(
  qr{v([1-9]\d*)}       => \&page,
);


sub page {
  my($self, $vid) = @_;

  # TODO: revision-awareness, hidden/locked flag check

  my $v = $self->dbVNGet(id => $vid, what => 'extended categories anime relations screenshots')->[0];
  return 404 if !$v->{id};

  my $r = $self->dbReleaseGet(vid => $vid, what => 'producers platforms');

  $self->htmlHeader(title => $v->{title});
  $self->htmlMainTabs('v', $v);
  div class => 'mainbox';
   h1 $v->{title};
   h2 class => 'alttitle', $v->{original} if $v->{original};

   div class => 'vndetails';

    # image 
    div class => 'vnimg';
     # TODO: check for img_nsfw and processing flag
     if($v->{image}) {
       img src => sprintf("%s/cv/%02d/%d.jpg", $self->{url_static}, $v->{image}%100, $v->{image}), alt => $v->{title};
     } else {
       p 'No image uploaded yet';
     }
    end;

    # general info
    table;
     Tr;
      td class => 'key', ' ';
      td ' ';
     end;
     my $i = 0;
     if($v->{length}) {
       Tr ++$i % 2 ? (class => 'odd') : ();
        td 'Length';
        td "$self->{vn_lengths}[$v->{length}][0] ($self->{vn_lengths}[$v->{length}][1])";
       end;
     }
     if($v->{alias}) {
       Tr ++$i % 2 ? (class => 'odd') : ();
        td 'Aliases';
        td $v->{alias};
       end;
     }
     my @links = (
       $v->{l_wp} ?      [ 'Wikipedia', 'http://en.wikipedia.org/wiki/%s', $v->{l_wp} ] : (),
       $v->{l_encubed} ? [ 'Encubed',   'http://novelnews.net/tag/%s/', $v->{l_encubed} ] : (),
       $v->{l_renai} ?   [ 'Renai.us',  'http://renai.us/game/%s.shtml', $v->{l_renai} ] : (),
       $v->{l_vnn}  ?    [ 'V-N.net',   'http://visual-novels.net/vn/index.php?option=com_content&task=view&id=%d', $v->{l_vnn} ] : (),
     );
     if(@links) {
       Tr ++$i % 2 ? (class => 'odd') : ();
        td 'Links';
        td;
         for(@links) {
           a href => sprintf($_->[1], $_->[2]), $_->[0];
           txt ', ' if $_ ne $links[$#links];
         }
        end;
       end;
     }

     _categories($self, \$i, $v) if @{$v->{categories}};
     _relations($self, \$i, $v) if @{$v->{relations}};
     _anime($self, \$i, $v) if @{$v->{anime}};
     
     # TODO: producers

    end;
   end;

   # description
   div class => 'vndescription';
    h2 'Description';
    p;
     lit bb2html $v->{desc};
    end;
   end;
  end;

  _releases($self, $v, $r);
  _screenshots($self, $v) if @{$v->{screenshots}};

  # TODO: stats, relation graph

  $self->htmlFooter;
}


sub _categories {
  my($self, $i, $v) = @_;

  # create an ordered list of selected categories in the form of: [ parent, [ p, sub, lvl ], .. ], ..
  my @cat;
  my %nolvl = (map {$_=>1} qw| pli pbr gaa gab hfa hfe |);
  for my $cp (qw|e s g p h|) {
    my $thisparent = 0;
    my @sel = sort grep substr($_->[0], 0, 1) eq $cp, @{$v->{categories}};
    if(@sel) {
      push @cat, [ $self->{categories}{$cp}[0] ];
      push @{$cat[$#cat]}, map [ $cp, substr($_->[0],1,2), $nolvl{$_->[0]} ? 0 : $_->[1] ], @sel;
    }
  }
  my @placetime = grep $_->[0] =~ /^[tl]/, @{$v->{categories}};
  if(@placetime) {
    push @cat, [ 'Place/Time' ];
    push @{$cat[$#cat]}, map [ substr($_->[0],0,1), substr($_->[0],1,2), 0], sort { $a->[0] cmp $b->[0] } @placetime;
  }

  # format & output categories
  Tr ++$$i % 2 ? (class => 'odd') : ();
   td 'Categories';
   td;
    dl;
     for (@cat) {
       dt shift(@$_).':';
       dd;
        lit join ', ', map qq|<i class="catlvl_$_->[2]">$self->{categories}{$_->[0]}[1]{$_->[1]}</i>|, @$_;
       end;
     }
    end;
   end;
  end;
}


sub _relations {
  my($self, $i, $v) = @_;

  my %rel;
  push @{$rel{$_->{relation}}}, $_
    for (sort { $a->{title} cmp $b->{title} } @{$v->{relations}});

  
  Tr ++$$i % 2 ? (class => 'odd') : ();
   td 'Relations';
   td;
    dl;
     for(sort keys %rel) {
       dt $self->{vn_relations}[$_][0].': ';
       dd;
        for (@{$rel{$_}}) {
          a href => "/v$_->{id}", title => $_->{original}||$_->{title}, shorten $_->{title}, 40;
          br;
        }
       end;
     }
    end;
   end;
  end;
}


sub _anime {
  my($self, $i, $v) = @_;

  Tr ++$$i % 2 ? (class => 'odd') : ();
   td 'Related anime';
   td class => 'anime';
    for (sort { ($a->{year}||9999) <=> ($b->{year}||9999) } @{$v->{anime}}) {
      if($_->{lastfetch} < 1) {
        b;
         txt $_->{lastfetch} < 0 ? '[unknown anidb id: ' : '[no information available at this time: ';
         a href => "http://anidb.net/a$_->{id}", $_->{id};
         txt ']';
        end;
      } else {
        b;
         txt '[';
         a href => "http://anidb.net/a$_->{id}", title => 'AniDB', 'DB';
         if($_->{nfo_id}) {
           txt '-';
           a href => "http://animenfo.com/animetitle,$_->{nfo_id},a.html", title => 'AnimeNFO', 'NFO';
         }
         if($_->{ann_id}) {
           txt '-';
           a href => "http://www.animenewsnetwork.com/encyclopedia/anime.php?id=$_->{ann_id}", title => 'Anime News Network', 'ANN';
         }
         txt '] ';
        end;
        acronym title => $_->{title_kanji}, shorten $_->{title_romaji}, 50;
        b ' ('.($self->{anime_types}[$_->{type}][0] eq 'unknown' ? '' : $self->{anime_types}[$_->{type}][0].', ').$_->{year}.')';
      }
    }
   end;
  end;
}


sub _releases {
  my($self, $v, $r) = @_;

  div class => 'mainbox releases';
   h1 'Releases';
   if(!@$r) {
     p 'We don\'t have any information about releases of this visual novel yet...';
     end;
     return;
   }

   my @lang;
   for my $l (@$r) {
     push @lang, $l->{language} if !grep $l->{language} eq $_, @lang;
   }

   table;
    for my $l (@lang) {
      Tr class => 'lang';
       td colspan => 5;
        acronym class => 'icons lang '.$l, title => $self->{languages}{$l}, ' ';
        txt $self->{languages}{$l};
       end;
      end;
      for my $rel (grep $l eq $_->{language}, @$r) {
        Tr;
         td class => 'tc1'; lit datestr $rel->{released}; end;
         td class => 'tc2', $rel->{minage} < 0 ? '' : $self->{age_ratings}{$rel->{minage}};
         td class => 'tc3';
          for (sort @{$rel->{platforms}}) {
            next if $_ eq 'oth';
            acronym class => "icons $_", title => $self->{platforms}{$_}, ' ';
          }
          acronym class => 'icons '.lc(substr($self->{release_types}[$rel->{type}],0,3)), title => $self->{release_types}[$rel->{type}], ' ';
         end;
         td class => 'tc4';
          a href => "/r$rel->{id}", title => $rel->{original}||$rel->{title}, $rel->{title};
         end;
         td class => 'tc5';
          if($rel->{website}) {
            a href => $rel->{website}, rel => 'nofollow', class => 'icons ext', title => 'WWW', ' ';
          } else {
            txt ' ';
          }
         end;
        end;
      }
    }
   end;
  end;
}


sub _screenshots {
  my($self, $v) = @_;
  div class => 'mainbox';
   h1 'Screenshots';
   p 'Here be screenshots';
  end;
}


1;

