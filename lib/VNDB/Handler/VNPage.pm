
package VNDB::Handler::VNPage;

use strict;
use warnings;
use YAWF ':html', 'xml_escape';
use VNDB::Func;


YAWF::register(
  qr{v([1-9]\d*)/rg}                => \&rg,
  qr{v([1-9]\d*)(?:\.([1-9]\d*))?}  => \&page,
);


sub rg {
  my($self, $vid) = @_;

  my $v = $self->dbVNGet(id => $vid, what => 'relgraph')->[0];
  return 404 if !$v->{id} || !$v->{rgraph};

  $self->htmlHeader(title => 'Relation graph for '.$v->{title});
  $self->htmlMainTabs('v', $v, 'rg');
  div class => 'mainbox';
   h1 'Relation graph for '.$v->{title};
   lit $v->{cmap};
   p class => 'center';
    img src => sprintf('%s/rg/%02d/%d.png', $self->{url_static}, $v->{rgraph}%100, $v->{rgraph}),
      alt => 'Relation graph for '.$v->{title}, usemap => '#rgraph';
   end;
  end;
}


sub page {
  my($self, $vid, $rev) = @_;

  my $v = $self->dbVNGet(
    id => $vid,
    what => 'extended categories anime relations screenshots'.($rev ? ' changes' : ''),
    $rev ? (rev => $rev) : (),
  )->[0];
  return 404 if !$v->{id};

  my $r = $self->dbReleaseGet(vid => $vid, what => 'producers platforms');

  $self->htmlHeader(title => $v->{title}, noindex => $rev);
  $self->htmlMainTabs('v', $v);
  return if $self->htmlHiddenMessage('v', $v);

  _revision($self, $v, $rev);

  div class => 'mainbox';
   $self->htmlItemMessage('v', $v);
   h1 $v->{title};
   h2 class => 'alttitle', $v->{original} if $v->{original};

   div class => 'vndetails';

    # image
    div class => 'vnimg';
     if(!$v->{image}) {
       p 'No image uploaded yet';
     } elsif($v->{image} < 0) {
       p '[processing image, please return in a few minutes]';
     } elsif($v->{img_nsfw} && !$self->authInfo->{show_nsfw}) {
       img id => 'nsfw_hid', src => sprintf("%s/cv/%02d/%d.jpg", $self->{url_static}, $v->{image}%100, $v->{image}), alt => $v->{title};
       p id => 'nsfw_show';
        txt "This image has been flagged\nas Not Safe For Work.\n\n";
        a href => '#', id => 'nsfw_show', 'Show me anyway';
        txt "\n\n(This warning can be disabled in your account)";
       end;
     } else {
       img src => sprintf("%s/cv/%02d/%d.jpg", $self->{url_static}, $v->{image}%100, $v->{image}), alt => $v->{title};
       i 'Flagged as NSFW' if $v->{img_nsfw} && $self->authInfo->{show_nsfw};
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

     _producers($self, \$i, $r);
     _categories($self, \$i, $v) if @{$v->{categories}};
     _relations($self, \$i, $v) if @{$v->{relations}};
     _anime($self, \$i, $v) if @{$v->{anime}};

     # User options
     if($self->authInfo->{id}) {
       my $vote = $self->dbVoteGet(uid => $self->authInfo->{id}, vid => $v->{id})->[0];
       my $wish = $self->dbWishListGet(uid => $self->authInfo->{id}, vid => $v->{id})->[0];
       Tr ++$i % 2 ? (class => 'odd') : ();
        td 'User options';
        td;
         Select id => 'votesel';
          option $vote ? "your vote: $vote->{vote}" : 'not voted yet';
          optgroup label => $vote ? 'Change vote' : 'Vote';
           option value => $_, "$_ ($self->{votes}[$_-1])" for (reverse 1..10);
          end;
          option value => -1, 'revoke' if $vote;
         end;
         br;
         Select id => 'wishsel';
          option $wish ? "wishlist: $self->{wishlist_status}[$wish->{wstat}]" : 'not on your wishlist';
          optgroup label => $wish ? 'Change status' : 'Add to wishlist';
           option value => $_, $self->{wishlist_status}[$_] for (0..$#{$self->{wishlist_status}});
          end;
          option value => -1, 'remove from wishlist';
         end;
        end;
       end;
     }

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
  _stats($self, $v);
  _screenshots($self, $v, $r) if @{$v->{screenshots}};

  $self->htmlFooter;
}


sub _revision {
  my($self, $v, $rev) = @_;
  return if !$rev;

  my $prev = $rev && $rev > 1 && $self->dbVNGet(
    id => $v->{id}, rev => $rev-1, what => 'extended categories anime relations screenshots changes'
  )->[0];

  $self->htmlRevision('v', $prev, $v,
    [ title       => 'Title (romaji)',   diff => 1 ],
    [ original    => 'Original title',   diff => 1 ],
    [ alias       => 'Alias',            diff => 1 ],
    [ desc        => 'Description',      diff => 1 ],
    [ length      => 'Length',           serialize => sub { $self->{vn_lengths}[$_[0]][0] } ],
    [ l_wp        => 'Wikipedia link',   htmlize => sub {
      $_[0] ? sprintf '<a href="http://en.wikipedia.org/wiki/%s">%1$s</a>', xml_escape $_[0] : '[no link]'
    }],
    [ l_encubed   => 'Encubed tag',      htmlize => sub {
      $_[0] ? sprintf '<a href="http://novelnews.net/tag/%s/">%1$s</a>', xml_escape $_[0] : '[no link]'
    }],
    [ l_renai     => 'Renai.us link',    htmlize => sub {
      $_[0] ? sprintf '<a href="http://renai.us/game/%s.shtml">%1$s</a>', xml_escape $_[0] : '[no link]'
    }],
    [ l_vnn       => 'V-N.net link',     htmlize => sub {
      $_[0] ? sprintf '<a href="http://visual-novels.net/vn/index.php?option=com_content&amp;task=view&amp;id=%d">%1$d</a>', xml_escape $_[0] : '[no link]'
    }],
    [ categories  => 'Categories',       join => ', ', split => sub {
      my @r = map $self->{categories}{substr($_->[0],0,1)}[1]{substr($_->[0],1,2)}."($_->[1])", sort { $a->[0] cmp $b->[0] } @{$_[0]};
      return @r ? @r : ('[no categories selected]');
    }],
    [ relations   => 'Relations',        join => '<br />', split => sub {
      my @r = map sprintf('%s: <a href="/v%d" title="%s">%s</a>',
        $self->{vn_relations}[$_->{relation}][0], $_->{id}, xml_escape($_->{original}||$_->{title}), xml_escape shorten $_->{title}, 40
      ), sort { $a->{id} <=> $b->{id} } @{$_[0]};
      return @r ? @r : ('[none]');
    }],
    [ anime       => 'Anime',            join => ', ', split => sub {
      my @r = map sprintf('<a href="http://anidb.net/a%d">a%1$d</a>', $_->{id}), sort { $a->{id} <=> $b->{id} } @{$_[0]};
      return @r ? @r : ('[none]');
    }],
    [ screenshots => 'Screenshots',      join => '<br />', split => sub {
      my @r = map sprintf('[%s] <a href="%s/sf/%02d/%d.jpg" rel="iv:%dx%d">%4$d</a> (%s)',
        $_->{rid} ? qq|<a href="/r$_->{rid}">r$_->{rid}</a>| : 'no release',
        $self->{url_static}, $_->{id}%100, $_->{id}, $_->{width}, $_->{height}, $_->{nsfw} ? 'NSFW' : 'Safe'
      ), @{$_[0]};
      return @r ? @r : ('[no screenshots]');
    }],
    [ image       => 'Image',            htmlize => sub {
      $_[0] > 0 ? sprintf '<img src="%s/cv/%02d/%d.jpg" />', $self->{url_static}, $_[0]%100, $_[0] : $_[0] < 0 ? '[processing]' : 'No image';
    }],
    [ img_nsfw    => 'Image NSFW',       serialize => sub { $_[0] ? 'Not safe' : 'Safe' } ],
  );
}


sub _producers {
  my($self, $i, $r) = @_;
  return if !grep @{$_->{producers}}, @$r;

  my @lang;
  for my $l (@$r) {
    push @lang, $l->{language} if !grep $l->{language} eq $_, @lang;
  }

  Tr ++$$i % 2 ? (class => 'odd') : ();
   td 'Producers';
   td;
    for my $l (@lang) {
      my %p = map { $_->{id} => $_ } map @{$_->{producers}}, grep $_->{language} eq $l, @$r;
      my @p = values %p;
      next if !@p;
      acronym class => "icons lang $l", title => $self->{languages}{$l}, ' ';
      for (@p) {
        a href => "/p$_->{id}", title => $_->{original}||$_->{name}, shorten $_->{name}, 30;
        txt ' & ' if $_ != $p[$#p];
      }
      txt "\n";
    }
   end;
  end;
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
   td class => 'relations';
    dl;
     for(sort keys %rel) {
       dt $self->{vn_relations}[$_][0];
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
        txt "\n";
      }
    }
   end;
  end;
}


sub _releases {
  my($self, $v, $r) = @_;

  div class => 'mainbox releases';
   a class => 'addnew', href => "/v$v->{id}/add", 'add release';
   h1 'Releases';
   if(!@$r) {
     p 'We don\'t have any information about releases of this visual novel yet...';
     end;
     return;
   }

   if($self->authInfo->{id}) {
     my $l = $self->dbVNListGet(uid => $self->authInfo->{id}, rid => [map $_->{id}, @$r]);
     for my $i (@$l) {
       (grep $i->{rid} == $_->{id}, @$r)[0]{ulist} = $i;
     }
   }

   my @lang;
   for my $l (@$r) {
     push @lang, $l->{language} if !grep $l->{language} eq $_, @lang;
   }

   table;
    for my $l (@lang) {
      Tr class => 'lang';
       td colspan => 6;
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
          if($rel->{ulist}) {
            a href => "/r$rel->{id}";
             lit liststat $rel->{ulist};
            end;
          } else {
            txt ' ';
          }
         end;
         td class => 'tc6';
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
  my($self, $v, $r) = @_;
  div class => 'mainbox', id => 'screenshots';

   if(grep $_->{nsfw}, @{$v->{screenshots}}) {
     p class => 'nsfwtoggle';
      lit sprintf 'Showing <i id="nsfwshown">%d</i> out of %d screenshots, ',
        $self->authInfo->{show_nsfw} ? scalar @{$v->{screenshots}} : scalar grep(!$_->{nsfw}, @{$v->{screenshots}}),
        scalar @{$v->{screenshots}};
      a href => '#', id => "nsfwhide", 'show/hide NSFW';
      txt '.';
     end;
   }

   h1 'Screenshots';
   table;
    for my $rel (@$r) {
      my @scr = grep $_->{rid} && $rel->{id} == $_->{rid}, @{$v->{screenshots}};
      next if !@scr;
      Tr class => 'rel';
       td colspan => 5;
        acronym class => 'icons lang '.$rel->{language}, title => $self->{languages}{$rel->{language}}, ' ';
        txt $rel->{title};
       end;
      end;
      Tr;
       td class => 'scr';
        for (@scr) {
          div $_->{nsfw} ? (class => 'nsfw'.(!$self->authInfo->{show_nsfw} ? ' hidden' : '')) : ();
           a href => sprintf('%s/sf/%02d/%d.jpg', $self->{url_static}, $_->{id}%100, $_->{id}),
             rel => "iv:$_->{width}x$_->{height}:scr", $_->{nsfw} && !$self->authInfo->{show_nsfw} ? (class => 'hidden') : ();
            img src => sprintf('%s/st/%02d/%d.jpg', $self->{url_static}, $_->{id}%100, $_->{id}), alt => "Screenshot #$_->{id}";
           end;
          end;
        }
       end;
      end;
    }
   end;
  end;
}


sub _stats {
  my($self, $v) = @_;

  my $stats = $self->dbVoteStats(vid => $v->{id});
  my($max, $count, $total) = (0, 0);
  for (0..$#$stats) {
    $max = $stats->[$_] if $stats->[$_] > $max;
    $count += $stats->[$_];
    $total += $stats->[$_]*($_+1);
  }

  div class => 'mainbox';
   h1 'User stats';
   if(!$max) {
     p "Nobody has voted on this visual novel yet...";
   } else {
     table class => 'votegraph';
      thead; Tr;
       td colspan => 2, 'Vote graph';
      end; end;
      for (reverse 0..$#$stats) {
        Tr;
         td class => 'number', $_+1;
         td class => 'graph';
          div style => 'width: '.($stats->[$_] ? $stats->[$_]/$max*250 : 0).'px', ' ';
          txt $stats->[$_];
         end;
        end;
      }
      tfoot; Tr;
       td colspan => 2, sprintf '%d votes total, average %.2f (%s)', $count, $total/$count, $self->{votes}[sprintf '%.0f', $total/$count-1];
      end; end;
     end;
   }
  end;
}


1;

