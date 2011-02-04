
package VNDB::Handler::VNPage;

use strict;
use warnings;
use TUWF ':html', 'xml_escape';
use VNDB::Func;


TUWF::register(
  qr{v/rand}                        => \&rand,
  qr{v([1-9]\d*)/rg}                => \&rg,
  qr{v([1-9]\d*)(?:\.([1-9]\d*))?}  => \&page,
);


sub rand {
  my $self = shift;
  $self->resRedirect('/v'.$self->filFetchDB(vn => undef, undef, {results => 1, sort => 'rand'})->[0]{id}, 'temp');
}


sub rg {
  my($self, $vid) = @_;

  my $v = $self->dbVNGet(id => $vid, what => 'relgraph')->[0];
  return $self->resNotFound if !$v->{id} || !$v->{rgraph};

  my $title = mt '_vnrg_title', $v->{title};
  return if $self->htmlRGHeader($title, 'v', $v);

  $v->{svg} =~ s/id="node_v$vid"/id="graph_current"/;
  $v->{svg} =~ s/\$___(_vnrel_[a-z]+)____\$/mt $1/eg;

  div class => 'mainbox';
   h1 $title;
   p class => 'center';
    lit $v->{svg};
   end;
  end;
  $self->htmlFooter;
}


sub page {
  my($self, $vid, $rev) = @_;

  my $v = $self->dbVNGet(
    id => $vid,
    what => 'extended anime relations screenshots rating ranking'.($rev ? ' changes' : ''),
    $rev ? (rev => $rev) : (),
  )->[0];
  return $self->resNotFound if !$v->{id};

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
       p mt '_vnpage_noimg';
     } elsif($v->{image} < 0) {
       p mt '_vnpage_imgproc';
     } else {
       p $v->{img_nsfw} ? (id => 'nsfw_hid', style => $self->authPref('show_nsfw') ? 'display: block' : '') : ();
        img src => sprintf("%s/cv/%02d/%d.jpg", $self->{url_static}, $v->{image}%100, $v->{image}), alt => $v->{title};
        i mt '_vnpage_imgnsfw_foot' if $v->{img_nsfw};
       end;
       if($v->{img_nsfw}) {
         p id => 'nsfw_show', $self->authPref('show_nsfw') ? (style => 'display: none') : ();
          txt mt('_vnpage_imgnsfw_msg');
          br; br;
          a href => '#', mt '_vnpage_imgnsfw_show';
          br; br;
          txt mt '_vnpage_imgnsfw_note';
         end;
       }
     }
    end 'div'; # /vnimg

    # general info
    table;
     my $i = 0;
     Tr ++$i % 2 ? (class => 'odd') : ();
      td class => 'key', mt '_vnpage_vntitle';
      td $v->{title};
     end;
     if($v->{original}) {
       Tr ++$i % 2 ? (class => 'odd') : ();
        td mt '_vnpage_original';
        td $v->{original};
       end;
     }
     if($v->{alias}) {
       $v->{alias} =~ s/\n/, /g;
       Tr ++$i % 2 ? (class => 'odd') : ();
        td mt '_vnpage_alias';
        td $v->{alias};
       end;
     }
     if($v->{length}) {
       Tr ++$i % 2 ? (class => 'odd') : ();
        td mt '_vnpage_length';
        td mt '_vnlength_'.$v->{length}, 1;
       end;
     }
     my @links = (
       $v->{l_wp} ?      [ 'wp', 'http://en.wikipedia.org/wiki/%s', $v->{l_wp} ] : (),
       $v->{l_encubed} ? [ 'encubed',   'http://novelnews.net/tag/%s/', $v->{l_encubed} ] : (),
       $v->{l_renai} ?   [ 'renai',  'http://renai.us/game/%s.shtml', $v->{l_renai} ] : (),
     );
     if(@links) {
       Tr ++$i % 2 ? (class => 'odd') : ();
        td mt '_vnpage_links';
        td;
         for(@links) {
           a href => sprintf($_->[1], $_->[2]), mt "_vnpage_l_$_->[0]";
           txt ', ' if $_ ne $links[$#links];
         }
        end;
       end;
     }

     _producers($self, \$i, $r);
     _relations($self, \$i, $v) if @{$v->{relations}};
     _anime($self, \$i, $v) if @{$v->{anime}};
     _useroptions($self, \$i, $v) if $self->authInfo->{id};

     Tr;
      td class => 'vndesc', colspan => 2;
       h2 mt '_vnpage_description';
       p;
        lit $v->{desc} ? bb2html $v->{desc} : '-';
       end;
      end;
     end;

    end 'table';
   end 'div';
   clearfloat;

   # tags
   my $t = $self->dbTagStats(vid => $v->{id}, sort => 'rating', reverse => 1, minrating => 0, results => 999);
   if(@$t) {
     div id => 'tagops';
      # NOTE: order of these links is hardcoded in JS
      a href => '#', class => 'tsel', mt '_vnpage_tags_spoil0';
      a href => '#', mt '_vnpage_tags_spoil1';
      a href => '#', mt '_vnpage_tags_spoil2';
      a href => '#', class => 'sec', mt '_vnpage_tags_summary';
      a href => '#', mt '_vnpage_tags_all';
     end;
     div id => 'vntags';
      for (@$t) {
        span class => sprintf 'tagspl%.0f %s', $_->{spoiler}, $_->{spoiler} > 0 ? 'hidden' : '';
         a href => "/g$_->{id}", style => sprintf('font-size: %dpx', $_->{rating}*3.5+6), $_->{name};
         b class => 'grayedout', sprintf ' %.1f', $_->{rating};
        end;
        txt ' ';
      }
     end;
   }
  end 'div'; # /mainbox

  _releases($self, $v, $r);
  _stats($self, $v);
  _screenshots($self, $v, $r) if @{$v->{screenshots}};

  $self->htmlFooter;
}


sub _revision {
  my($self, $v, $rev) = @_;
  return if !$rev;

  my $prev = $rev && $rev > 1 && $self->dbVNGet(
    id => $v->{id}, rev => $rev-1, what => 'extended anime relations screenshots changes'
  )->[0];

  $self->htmlRevision('v', $prev, $v,
    [ title       => diff => 1 ],
    [ original    => diff => 1 ],
    [ alias       => diff => qr/[ ,\n\.]/ ],
    [ desc        => diff => qr/[ ,\n\.]/ ],
    [ length      => serialize => sub { mt '_vnlength_'.$_[0] } ],
    [ l_wp        => htmlize => sub {
      $_[0] ? sprintf '<a href="http://en.wikipedia.org/wiki/%s">%1$s</a>', xml_escape $_[0] : mt '_revision_nolink'
    }],
    [ l_encubed   => htmlize => sub {
      $_[0] ? sprintf '<a href="http://novelnews.net/tag/%s/">%1$s</a>', xml_escape $_[0] : mt '_revision_nolink'
    }],
    [ l_renai     => htmlize => sub {
      $_[0] ? sprintf '<a href="http://renai.us/game/%s.shtml">%1$s</a>', xml_escape $_[0] : mt '_revision_nolink'
    }],
    [ relations   => join => '<br />', split => sub {
      my @r = map sprintf('[%s] %s: <a href="/v%d" title="%s">%s</a>',
        mt($_->{official} ? '_vndiff_rel_official' : '_vndiff_rel_unofficial'),
        mt("_vnrel_$_->{relation}"), $_->{id}, xml_escape($_->{original}||$_->{title}), xml_escape shorten $_->{title}, 40
      ), sort { $a->{id} <=> $b->{id} } @{$_[0]};
      return @r ? @r : (mt '_revision_empty');
    }],
    [ anime       => join => ', ', split => sub {
      my @r = map sprintf('<a href="http://anidb.net/a%d">a%1$d</a>', $_->{id}), sort { $a->{id} <=> $b->{id} } @{$_[0]};
      return @r ? @r : (mt '_revision_empty');
    }],
    [ screenshots => join => '<br />', split => sub {
      my @r = map sprintf('[%s] <a href="%s/sf/%02d/%d.jpg" rel="iv:%dx%d">%4$d</a> (%s)',
        $_->{rid} ? qq|<a href="/r$_->{rid}">r$_->{rid}</a>| : 'no release',
        $self->{url_static}, $_->{id}%100, $_->{id}, $_->{width}, $_->{height},
        mt($_->{nsfw} ? '_vndiff_nsfw_notsafe' : '_vndiff_nsfw_safe')
      ), @{$_[0]};
      return @r ? @r : (mt '_revision_empty');
    }],
    [ image       => htmlize => sub {
      my $url = sprintf "%s/cv/%02d/%d.jpg", $self->{url_static}, $_[0]%100, $_[0];
      if($_[0] > 0) {
        return $_[1]->{img_nsfw} && !$self->authPref('show_nsfw') ? "<a href=\"$url\">".mt('_vndiff_image_nsfw').'</a>' : "<img src=\"$url\" />";
      } else {
        return mt $_[0] < 0 ? '_vndiff_image_proc' : '_vndiff_image_none';
      }
    }],
    [ img_nsfw    => serialize => sub { mt $_[0] ? '_vndiff_nsfw_notsafe' : '_vndiff_nsfw_safe' } ],
  );
}


sub _producers {
  my($self, $i, $r) = @_;

  my %lang;
  my @lang = grep !$lang{$_}++, map @{$_->{languages}}, @$r;

  if(grep $_->{developer}, map @{$_->{producers}}, @$r) {
    my %dev = map $_->{developer} ? ($_->{id} => $_) : (), map @{$_->{producers}}, @$r;
    my @dev = values %dev;
    Tr ++$$i % 2 ? (class => 'odd') : ();
     td mt "_vnpage_developer";
     td;
      for (@dev) {
        a href => "/p$_->{id}", title => $_->{original}||$_->{name}, shorten $_->{name}, 30;
        txt ' & ' if $_ != $dev[$#dev];
      }
     end;
    end;
  }

  if(grep $_->{publisher}, map @{$_->{producers}}, @$r) {
    Tr ++$$i % 2 ? (class => 'odd') : ();
     td mt "_vnpage_publisher";
     td;
      for my $l (@lang) {
        my %p = map $_->{publisher} ? ($_->{id} => $_) : (), map @{$_->{producers}}, grep grep($_ eq $l, @{$_->{languages}}), @$r;
        my @p = values %p;
        next if !@p;
        cssicon "lang $l", mt "_lang_$l";
        for (@p) {
          a href => "/p$_->{id}", title => $_->{original}||$_->{name}, shorten $_->{name}, 30;
          txt ' & ' if $_ != $p[$#p];
        }
        br;
      }
     end;
    end 'tr';
  }
}


sub _relations {
  my($self, $i, $v) = @_;

  my %rel;
  push @{$rel{$_->{relation}}}, $_
    for (sort { $a->{title} cmp $b->{title} } @{$v->{relations}});


  Tr ++$$i % 2 ? (class => 'odd') : ();
   td mt '_vnpage_relations';
   td class => 'relations';
    dl;
     for(sort keys %rel) {
       dt mt "_vnrel_$_";
       dd;
        for (@{$rel{$_}}) {
          b class => 'grayedout', mt('_vnpage_relations_unofficial').' ' if !$_->{official};
          a href => "/v$_->{id}", title => $_->{original}||$_->{title}, shorten $_->{title}, 40;
          br;
        }
       end;
     }
    end;
   end;
  end 'tr';
}


sub _anime {
  my($self, $i, $v) = @_;

  Tr ++$$i % 2 ? (class => 'odd') : ();
   td mt '_vnpage_anime';
   td class => 'anime';
    for (sort { ($a->{year}||9999) <=> ($b->{year}||9999) } @{$v->{anime}}) {
      if(!$_->{lastfetch} || !$_->{year} || !$_->{title_romaji}) {
        b;
         lit mt '_vnpage_anime_noinfo', $_->{id}, "http://anidb.net/a$_->{id}";
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
        acronym title => $_->{title_kanji}||$_->{title_romaji}, shorten $_->{title_romaji}, 50;
        b ' ('.(defined $_->{type} ? mt("_animetype_$_->{type}").', ' : '').$_->{year}.')';
        br;
      }
    }
   end;
  end 'tr';
}


sub _useroptions {
  my($self, $i, $v) = @_;

  my $vote = $self->dbVoteGet(uid => $self->authInfo->{id}, vid => $v->{id})->[0];
  my $list = $self->dbVNListGet(uid => $self->authInfo->{id}, vid => $v->{id})->[0];
  my $wish = $self->dbWishListGet(uid => $self->authInfo->{id}, vid => $v->{id})->[0];

  Tr ++$$i % 2 ? (class => 'odd') : ();
   td mt '_vnpage_uopt';
   td;
    if($vote || !$wish) {
      Select id => 'votesel', name => $self->authGetCode("/v$v->{id}/vote");
       option $vote ? mt '_vnpage_uopt_voted', $vote->{vote} : mt '_vnpage_uopt_novote';
       optgroup label => $vote ? mt '_vnpage_uopt_changevote' : mt '_vnpage_uopt_dovote';
        option value => $_, "$_ (".mt("_vote_$_").')' for (reverse 1..10);
       end;
       option value => -1, mt '_vnpage_uopt_delvote' if $vote;
      end;
      br;
    }

    Select id => 'listsel', name => $self->authGetCode("/v$v->{id}/list");
     option $list ? mt '_vnpage_uopt_vnlisted', mt '_vnlist_status_'.$list->{status} : mt '_vnpage_uopt_novn';
     optgroup label => $list ? mt '_vnpage_uopt_changevn' : mt '_vnpage_uopt_addvn';
      option value => $_, mt "_vnlist_status_$_" for (@{$self->{rlist_status}});
     end;
     option value => -1, mt '_vnpage_uopt_delvn' if $list;
    end;
    br;

    if(!$vote || $wish) {
      Select id => 'wishsel', name => $self->authGetCode("/v$v->{id}/wish");
       option $wish ? mt '_vnpage_uopt_wishlisted', mt '_wish_'.$wish->{wstat} : mt '_vnpage_uopt_nowish';
       optgroup label => $wish ? mt '_vnpage_uopt_changewish' : mt '_vnpage_uopt_addwish';
        option value => $_, mt "_wish_$_" for (@{$self->{wishlist_status}});
       end;
       option value => -1, mt '_vnpage_uopt_delwish' if $wish;
      end;
    }
   end;
  end 'tr';
}


sub _releases {
  my($self, $v, $r) = @_;

  div class => 'mainbox releases';
   a class => 'addnew', href => "/v$v->{id}/add", mt '_vnpage_rel_add';
   h1 mt '_vnpage_rel';
   if(!@$r) {
     p mt '_vnpage_rel_none';
     end;
     return;
   }

   if($self->authInfo->{id}) {
     my $l = $self->dbRListGet(uid => $self->authInfo->{id}, rid => [map $_->{id}, @$r]);
     for my $i (@$l) {
       [grep $i->{rid} == $_->{id}, @$r]->[0]{ulist} = $i;
     }
     div id => 'vnrlist_code', class => 'hidden', $self->authGetCode('/xml/rlist.xml');
   }

   my %lang;
   my @lang = grep !$lang{$_}++, map @{$_->{languages}}, @$r;

   table;
    for my $l (@lang) {
      Tr class => 'lang';
       td colspan => 6;
        cssicon "lang $l", mt "_lang_$l";
        txt mt "_lang_$l";
       end;
      end;
      for my $rel (grep grep($_ eq $l, @{$_->{languages}}), @$r) {
        Tr;
         td class => 'tc1'; lit $self->{l10n}->datestr($rel->{released}); end;
         td class => 'tc2', $rel->{minage} < 0 ? '' : minage $rel->{minage};
         td class => 'tc3';
          for (sort @{$rel->{platforms}}) {
            next if $_ eq 'oth';
            cssicon $_, mt "_plat_$_";
          }
          cssicon "rt$rel->{type}", mt "_rtype_$rel->{type}";
         end;
         td class => 'tc4';
          a href => "/r$rel->{id}", title => $rel->{original}||$rel->{title}, $rel->{title};
          b class => 'grayedout', ' '.mt '_vnpage_rel_patch' if $rel->{patch};
         end;
         td class => 'tc5';
          if($self->authInfo->{id}) {
            a href => "/r$rel->{id}", id => "rlsel_$rel->{id}", class => 'vnrlsel',
             $rel->{ulist} ? mt '_rlist_status_'.$rel->{ulist}{status} : '--';
          } else {
            txt ' ';
          }
         end;
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


sub _screenshots {
  my($self, $v, $r) = @_;
  div class => 'mainbox', id => 'screenshots';

   if(grep $_->{nsfw}, @{$v->{screenshots}}) {
     p class => 'nsfwtoggle';
      lit mt '_vnpage_scr_showing',
        sprintf('<i id="nsfwshown">%d</i>', $self->authPref('show_nsfw') ? scalar @{$v->{screenshots}} : scalar grep(!$_->{nsfw}, @{$v->{screenshots}})),
        scalar @{$v->{screenshots}};
      txt " ";
      a href => '#', id => "nsfwhide", mt '_vnpage_scr_nsfwhide';
     end;
   }

   h1 mt '_vnpage_scr';

   for my $rel (@$r) {
     my @scr = grep $_->{rid} && $rel->{id} == $_->{rid}, @{$v->{screenshots}};
     next if !@scr;
     p class => 'rel';
      cssicon "lang $_", mt "_lang_$_" for (@{$rel->{languages}});
      a href => "/r$rel->{id}", $rel->{title};
     end;
     div class => 'scr';
      for (@scr) {
        my($w, $h) = imgsize($_->{width}, $_->{height}, @{$self->{scr_size}});
        a href => sprintf('%s/sf/%02d/%d.jpg', $self->{url_static}, $_->{id}%100, $_->{id}),
          class => sprintf('scrlnk%s%s', $_->{nsfw} ? ' nsfw':'', $_->{nsfw}&&!$self->authPref('show_nsfw')?' hidden':''),
          rel => "iv:$_->{width}x$_->{height}:scr";
         img src => sprintf('%s/st/%02d/%d.jpg', $self->{url_static}, $_->{id}%100, $_->{id}),
           width => $w, height => $h, alt => mt '_vnpage_scr_num', $_->{id};
        end;
      }
     end;
   }
  end 'div';
}


sub _stats {
  my($self, $v) = @_;

  my $stats = $self->dbVoteStats(vid => $v->{id}, 1);
  div class => 'mainbox';
   h1 mt '_vnpage_stats';
   if(!grep $_ > 0, @$stats) {
     p mt '_vnpage_stats_none';
   } else {
     $self->htmlVoteStats(v => $v, $stats);
   }
  end;
}


1;

