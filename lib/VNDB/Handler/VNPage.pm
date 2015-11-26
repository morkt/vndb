
package VNDB::Handler::VNPage;

use strict;
use warnings;
use TUWF ':html', 'xml_escape';
use VNDB::Func;


TUWF::register(
  qr{v/rand}                        => \&rand,
  qr{v([1-9]\d*)/rg}                => \&rg,
  qr{v([1-9]\d*)/releases}          => \&releases,
  qr{v([1-9]\d*)/(chars)}           => \&page,
  qr{v([1-9]\d*)/staff}             => sub { $_[0]->resRedirect("/v$_[1]#staff") },
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


# Description of each column, field:
#   id:            Identifier used in URLs
#   sort_field:    Name of the field when sorting
#   what:          Required dbReleaseGet 'what' flag
#   column_string: String to use as column header
#   column_width:  Maximum width (in pixels) of the column in 'restricted width' mode
#   button_string: String to use for the hide/unhide button
#   na_for_patch:  When the field is N/A for patch releases
#   default:       Set when it's visible by default
#   has_data:      Subroutine called with a release object, should return true if the release has data for the column
#   draw:          Subroutine called with a release object, should draw its column contents
my @rel_cols = (
  {    # Title
    id            => 'tit',
    sort_field    => 'title',
    column_string => '_relinfo_title',
    draw          => sub { a href => "/r$_[0]{id}", shorten $_[0]{title}, 60 },
  }, { # Type
    id            => 'typ',
    sort_field    => 'type',
    button_string => '_relinfo_type',
    default       => 1,
    draw          => sub { cssicon "rt$_[0]{type}", mt "_rtype_$_[0]{type}"; txt mt '_vnpage_rel_patch' if $_[0]{patch} },
  }, { # Languages
    id            => 'lan',
    button_string => '_relinfo_lang',
    default       => 1,
    has_data      => sub { !!@{$_[0]{languages}} },
    draw          => sub {
      for(@{$_[0]{languages}}) {
        cssicon "lang $_", mt "_lang_$_";
        br if $_ ne $_[0]{languages}[$#{$_[0]{languages}}];
      }
    },
  }, { # Publication
    id            => 'pub',
    sort_field    => 'publication',
    column_string => '_relinfo_publication',
    column_width  => 70,
    button_string => '_relinfo_publication',
    default       => 1,
    what          => 'extended',
    draw          => sub { txt mt $_[0]{patch} ? '_relinfo_pub_patch' : '_relinfo_pub_nopatch', $_[0]{freeware}?0:1, $_[0]{doujin}?0:1 },
  }, { # Platforms
    id             => 'pla',
    button_string => '_redit_form_platforms',
    default       => 1,
    what          => 'platforms',
    has_data      => sub { !!@{$_[0]{platforms}} },
    draw          => sub {
      for(@{$_[0]{platforms}}) {
        cssicon $_, mt "_plat_$_";
        br if $_ ne $_[0]{platforms}[$#{$_[0]{platforms}}];
      }
      txt mt '_unknown' if !@{$_[0]{platforms}};
    },
  }, { # Media
    id            => 'med',
    column_string => '_redit_form_media',
    button_string => '_redit_form_media',
    what          => 'media',
    has_data      => sub { !!@{$_[0]{media}} },
    draw          => sub {
      for(@{$_[0]{media}}) {
        txt $TUWF::OBJ->{media}{$_->{medium}} ? $_->{qty}.' '.mt("_med_$_->{medium}", $_->{qty}) : mt("_med_$_->{medium}",1);
        br if $_ ne $_[0]{media}[$#{$_[0]{media}}];
      }
      txt mt '_unknown' if !@{$_[0]{media}};
    },
  }, { # Resolution
    id            => 'res',
    sort_field    => 'resolution',
    column_string => '_relinfo_resolution',
    button_string => '_relinfo_resolution',
    na_for_patch  => 1,
    default       => 1,
    what          => 'extended',
    has_data      => sub { !!$_[0]{resolution} },
    draw          => sub {
      if($_[0]{resolution}) {
        my $res = $TUWF::OBJ->{resolutions}[$_[0]{resolution}][0];
        txt $res =~ /^_/ ? mt $res : $res;
      } else {
        txt mt '_unknown';
      }
    },
  }, { # Voiced
    id            => 'voi',
    sort_field    => 'voiced',
    column_string => '_relinfo_voiced',
    column_width  => 70,
    button_string => '_relinfo_voiced',
    na_for_patch  => 1,
    default       => 1,
    what          => 'extended',
    has_data      => sub { !!$_[0]{voiced} },
    draw          => sub { txt mtvoiced $_[0]{voiced} },
  }, { # Animation
    id            => 'ani',
    sort_field    => 'ani_ero',
    column_string => '_relinfo_ani',
    column_width  => 110,
    button_string => '_relinfo_ani',
    na_for_patch  => '1',
    what          => 'extended',
    has_data      => sub { !!($_[0]{ani_story} || $_[0]{ani_ero}) },
    draw          => sub {
      txt join ', ',
        $_[0]{ani_story} ? mt('_relinfo_ani_story', mtani $_[0]{ani_story}):(),
        $_[0]{ani_ero}   ? mt('_relinfo_ani_ero',   mtani $_[0]{ani_ero}  ):();
      txt mt '_unknown' if !$_[0]{ani_story} && !$_[0]{ani_ero};
    },
  }, { # Released
    id            => 'rel',
    sort_field    => 'released',
    column_string => '_relinfo_released',
    button_string => '_relinfo_released',
    default       => 1,
    draw          => sub { lit $TUWF::OBJ->{l10n}->datestr($_[0]{released}) },
  }, { # Age rating
    id            => 'min',
    sort_field    => 'minage',
    button_string => '_relinfo_minage',
    default       => 1,
    has_data      => sub { $_[0]{minage} != -1 },
    draw          => sub { txt minage $_[0]{minage} },
  }, { # Notes
    id            => 'not',
    sort_field    => 'notes',
    column_string => '_redit_form_notes',
    column_width  => 400,
    button_string => '_redit_form_notes',
    default       => 1,
    what          => 'extended',
    has_data      => sub { !!$_[0]{notes} },
    draw          => sub { lit bb2html $_[0]{notes} },
  }
);


sub releases {
  my($self, $vid) = @_;

  my $v = $self->dbVNGet(id => $vid)->[0];
  return $self->resNotFound if !$v->{id};

  my $title = mt('_vnpage_rel_title', $v->{title});
  $self->htmlHeader(title => $title);
  $self->htmlMainTabs('v', $v, 'releases');

  my $f = $self->formValidate(
    map({ get => $_->{id}, required => 0, default => $_->{default}||0, enum => [0,1] }, grep $_->{button_string}, @rel_cols),
    { get => 'cw',   required => 0, default => 0, enum => [0,1] },
    { get => 'o',    required => 0, default => 0, enum => [0,1] },
    { get => 's',    required => 0, default => 'released', enum => [ map $_->{sort_field}, grep $_->{sort_field}, @rel_cols ]},
    { get => 'os',   required => 0, default => 'all',      enum => [ 'all', @{$self->{platforms}} ] },
    { get => 'lang', required => 0, default => 'all',      enum => [ 'all', @{$self->{languages}} ] },
  );
  return $self->resNotFound if $f->{_err};

  # Get the release info
  my %what = map +($_->{what}, 1), grep $_->{what} && $f->{$_->{id}}, @rel_cols;
  my $r = $self->dbReleaseGet(vid => $vid, what => join(' ', keys %what), sort => $f->{s}, reverse => $f->{o}, results => 200);

  # url generator
  my $url = sub {
    my %u = (%$f, @_);
    return "/v$vid/releases?".join(';', map "$_=$u{$_}", sort keys %u);
  };

  div class => 'mainbox releases_compare';
   h1 $title;

   if(!@$r) {
     td mt '_vnpage_rel_none';
   } else {
     _releases_buttons($self, $f, $url, $r);
   }
  end 'div';

  _releases_table($self, $f, $url, $r) if @$r;
  $self->htmlFooter;
}


sub _releases_buttons {
  my($self, $f, $url, $r) = @_;

  # Column visibility
  p class => 'browseopts';
   a href => $url->($_->{id}, $f->{$_->{id}} ? 0 : 1), $f->{$_->{id}} ? (class => 'optselected') : (), mt $_->{button_string}
     for (grep $_->{button_string}, @rel_cols);
  end;

  # Misc options
  my $all_selected   = !grep $_->{button_string} && !$f->{$_->{id}}, @rel_cols;
  my $all_unselected = !grep $_->{button_string} &&  $f->{$_->{id}}, @rel_cols;
  my $all_url = sub { $url->(map +($_->{id},$_[0]), grep $_->{button_string}, @rel_cols); };
  p class => 'browseopts';
   a href => $all_url->(1),                  $all_selected   ? (class => 'optselected') : (), mt '_all_on';
   a href => $all_url->(0),                  $all_unselected ? (class => 'optselected') : (), mt '_all_off';
   a href => $url->('cw', $f->{cw} ? 0 : 1), $f->{cw}        ? (class => 'optselected') : (), mt '_vnpage_restrict_column_width';
  end;

  # Platform/language filters
  my $plat_lang_draw = sub {
    my($row, $option, $l10nprefix, $csscat) = @_;
    my %opts = map +($_,1), map @{$_->{$row}}, @$r;
    return if !keys %opts;
    p class => 'browseopts';
     for('all', sort keys %opts) {
       a href => $url->($option, $_), $_ eq $f->{$option} ? (class => 'optselected') : ();
        $_ eq 'all' ? txt mt '_all' : cssicon "$csscat $_", mt $l10nprefix.$_;
       end 'a';
     }
    end 'p';
  };
  $plat_lang_draw->('platforms', 'os',  '_plat_', '')     if $f->{pla};
  $plat_lang_draw->('languages', 'lang','_lang_', 'lang') if $f->{lan};
}


sub _releases_table {
  my($self, $f, $url, $r) = @_;

  # Apply language and platform filters
  my @r = grep +
    ($f->{os}   eq 'all' || ($_->{platforms} && grep $_ eq $f->{os}, @{$_->{platforms}})) &&
    ($f->{lang} eq 'all' || ($_->{languages} && grep $_ eq $f->{lang}, @{$_->{languages}})), @$r;

  # Figure out which columns to display
  my @col;
  for my $c (@rel_cols) {
    next if $c->{button_string} && !$f->{$c->{id}}; # Hidden by settings
    push @col, $c if !@r || !$c->{has_data} || grep $c->{has_data}->($_), @r; # Must have relevant data
  }

  div class => 'mainbox releases_compare';
   table;

    thead;
     Tr;
      for my $c (@col) {
        td class => 'key';
         txt mt $c->{column_string} if $c->{column_string};
         for($c->{sort_field} ? (0,1) : ()) {
           my $active = $f->{s} eq $c->{sort_field} && !$f->{o} == !$_;
           a href => $url->(o => $_, s => $c->{sort_field}) if !$active;
            lit $_ ? "\x{25BE}" : "\x{25B4}";
           end 'a' if !$active;
         }
        end 'td';
      }
     end 'tr';
    end 'thead';

    for my $r (@r) {
      Tr;
       # Combine "N/A for patches" columns
       my $cspan = 1;
       for my $c (0..$#col) {
         if($r->{patch} && $col[$c]{na_for_patch} && $c < $#col && $col[$c+1]{na_for_patch}) {
           $cspan++;
           next;
         }
         td $cspan > 1 ? (colspan => $cspan) : (),
            $col[$c]{column_width} && $f->{cw} ? (style => "max-width: $col[$c]{column_width}px") : ();
          if($r->{patch} && $col[$c]{na_for_patch}) {
            txt mt '_vnpage_na_for_patches';
          } else {
            $col[$c]{draw}->($r);
          }
         end;
         $cspan = 1;
       }
      end;
    }
   end 'table';
  end 'div';
}


sub page {
  my($self, $vid, $rev) = @_;

  my $char = $rev && $rev eq 'chars';
  $rev = undef if $char;

  my $method = $rev ? 'dbVNGetRev' : 'dbVNGet';
  my $v = $self->$method(
    id => $vid,
    what => 'extended anime relations screenshots rating ranking credits',
    $rev ? (rev => $rev) : (),
  )->[0];
  return $self->resNotFound if !$v->{id};

  my $r = $self->dbReleaseGet(vid => $vid, what => 'producers platforms', results => 200);

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
     } else {
       p $v->{img_nsfw} ? (id => 'nsfw_hid', $self->authPref('show_nsfw') ? () : (class => 'hidden')) : ();
        img src => imgurl(cv => $v->{image}), alt => $v->{title};
        i mt '_vnpage_imgnsfw_foot' if $v->{img_nsfw};
       end;
       if($v->{img_nsfw}) {
         p id => 'nsfw_show', $self->authPref('show_nsfw') ? (class => 'hidden') : ();
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
    table class => 'stripe';
     Tr;
      td class => 'key', mt '_vnpage_vntitle';
      td $v->{title};
     end;
     if($v->{original}) {
       Tr;
        td mt '_vnpage_original';
        td $v->{original};
       end;
     }
     if($v->{alias}) {
       $v->{alias} =~ s/\n/, /g;
       Tr;
        td mt '_vnpage_alias';
        td $v->{alias};
       end;
     }
     if($v->{length}) {
       Tr;
        td mt '_vnpage_length';
        td mtvnlen $v->{length}, 1;
       end;
     }
     my @links = (
       $v->{l_wp} ?      [ 'wp', 'http://en.wikipedia.org/wiki/%s', $v->{l_wp} ] : (),
       $v->{l_encubed} ? [ 'encubed',   'http://novelnews.net/tag/%s/', $v->{l_encubed} ] : (),
       $v->{l_renai} ?   [ 'renai',  'http://renai.us/game/%s.shtml', $v->{l_renai} ] : (),
     );
     if(@links) {
       Tr;
        td mt '_vnpage_links';
        td;
         for(@links) {
           a href => sprintf($_->[1], $_->[2]), mt "_vnpage_l_$_->[0]";
           txt ', ' if $_ ne $links[$#links];
         }
        end;
       end;
     }

     _producers($self, $r);
     _relations($self, $v) if @{$v->{relations}};
     _anime($self, $v) if @{$v->{anime}};
     _useroptions($self, $v) if $self->authInfo->{id};
     _affiliate_links($self, $r);

     Tr class => 'nostripe';
      td class => 'vndesc', colspan => 2;
       h2 mt '_vnpage_description';
       p;
        lit $v->{desc} ? bb2html $v->{desc} : '-';
       end;
      end;
     end;

    end 'table';
   end 'div';
   div class => 'clearfloat', style => 'height: 5px', ''; # otherwise the tabs below aren't positioned correctly

   # tags
   my $t = $self->dbTagStats(vid => $v->{id}, sort => 'rating', reverse => 1, minrating => 0, results => 999);
   if(@$t) {
     div id => 'tagops';
      # NOTE: order of these links is hardcoded in JS
      my $tags_cat = $self->authPref('tags_cat') || $self->{default_tags_cat};
      a href => "#$_", $tags_cat =~ /\Q$_/ ? (class => 'tsel') : (), lc mt "_tagcat_$_" for qw|cont ero tech|;
      my $spoiler = $self->authPref('spoilers') || 0;
      a href => '#', class => 'sec'.($spoiler == 0 ? ' tsel' : ''), lc mt '_spoilset_0';
      a href => '#', $spoiler == 1 ? (class => 'tsel') : (), lc mt '_spoilset_1';
      a href => '#', $spoiler == 2 ? (class => 'tsel') : (), lc mt '_spoilset_2';
      a href => '#', class => 'sec'.($self->authPref('tags_all') ? '': ' tsel'), mt '_vnpage_tags_summary';
      a href => '#', $self->authPref('tags_all') ? (class => 'tsel') : (), mt '_vnpage_tags_all';
     end;
     div id => 'vntags';
      for (@$t) {
        span class => sprintf 'tagspl%.0f cat_%s %s', $_->{spoiler}, $_->{cat}, $_->{spoiler} > 0 ? 'hidden' : '';
         a href => "/g$_->{id}", style => sprintf('font-size: %dpx', $_->{rating}*3.5+6), $_->{name};
         b class => 'grayedout', sprintf ' %.1f', $_->{rating};
        end;
        txt ' ';
      }
     end;
   }
  end 'div'; # /mainbox

  my $haschar = $self->dbVNHasChar($v->{id});
  if($haschar || $self->authCan('edit')) {
    clearfloat; # fix tabs placement when tags are hidden
    ul class => 'maintabs notfirst';
     if($haschar) {
       li class => 'left '.(!$char ? ' tabselected' : ''); a href => "/v$v->{id}#main", name => 'main', mt '_vnpage_tab_main'; end;
       li class => 'left '.($char  ? ' tabselected' : ''); a href => "/v$v->{id}/chars#chars", name => 'chars', mt '_vnpage_tab_chars'; end;
     }
     if($self->authCan('edit')) {
       li; a href => "/c/new?vid=$v->{id}", mt '_vnpage_char_add'; end;
       li; a href => "/v$v->{id}/add", mt '_vnpage_rel_add'; end;
     }
    end;
  }

  if($char) {
    _chars($self, $haschar, $v);
  } else {
    _releases($self, $v, $r);
    _staff($self, $v);
    _stats($self, $v);
    _screenshots($self, $v, $r) if @{$v->{screenshots}};
  }

  $self->htmlFooter;
}


sub _revision {
  my($self, $v, $rev) = @_;
  return if !$rev;

  my $prev = $rev && $rev > 1 && $self->dbVNGetRev(
    id => $v->{id}, rev => $rev-1, what => 'extended anime relations screenshots credits'
  )->[0];

  $self->htmlRevision('v', $prev, $v,
    [ title       => diff => 1 ],
    [ original    => diff => 1 ],
    [ alias       => diff => qr/[ ,\n\.]/ ],
    [ desc        => diff => qr/[ ,\n\.]/ ],
    [ length      => serialize => sub { mtvnlen $_[0] } ],
    [ l_wp        => htmlize => sub {
      $_[0] ? sprintf '<a href="http://en.wikipedia.org/wiki/%s">%1$s</a>', xml_escape $_[0] : mt '_revision_nolink'
    }],
    [ l_encubed   => htmlize => sub {
      $_[0] ? sprintf '<a href="http://novelnews.net/tag/%s/">%1$s</a>', xml_escape $_[0] : mt '_revision_nolink'
    }],
    [ l_renai     => htmlize => sub {
      $_[0] ? sprintf '<a href="http://renai.us/game/%s.shtml">%1$s</a>', xml_escape $_[0] : mt '_revision_nolink'
    }],
    [ credits     => join => '<br />', split => sub {
      my @r = map sprintf('<a href="/s%d" title="%s">%s</a> [%s]%s', $_->{id},
          xml_escape($_->{original}||$_->{name}), xml_escape($_->{name}), mt("_credit_$_->{role}"),
          $_->{note} ? ' ['.xml_escape($_->{note}).']' : ''),
        sort { $a->{id} <=> $b->{id} || $a->{role} cmp $b->{role} } @{$_[0]};
      return @r ? @r : (mt '_revision_empty');
    }],
    [ seiyuu      => join => '<br />', split => sub {
      my @r = map sprintf('<a href="/s%d" title="%s">%s</a> %s%s',
          $_->{id}, xml_escape($_->{original}||$_->{name}), xml_escape($_->{name}),
          mt('_staff_as', xml_escape($_->{cname})),
          $_->{note} ? ' ['.xml_escape($_->{note}).']' : ''),
        sort { $a->{id} <=> $b->{id} || $a->{cid} <=> $b->{cid} || $a->{note} cmp $b->{note} } @{$_[0]};
      return @r ? @r : (mt '_revision_empty');
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
      my @r = map sprintf('[%s] <a href="%s" data-iv="%dx%d">%d</a> (%s)',
        $_->{rid} ? qq|<a href="/r$_->{rid}">r$_->{rid}</a>| : 'no release',
        imgurl(sf => $_->{id}), $_->{width}, $_->{height}, $_->{id},
        mt($_->{nsfw} ? '_vndiff_nsfw_notsafe' : '_vndiff_nsfw_safe')
      ), @{$_[0]};
      return @r ? @r : (mt '_revision_empty');
    }],
    [ image       => htmlize => sub {
      my $url = imgurl(cv => $_[0]);
      if($_[0]) {
        return $_[1]->{img_nsfw} && !$self->authPref('show_nsfw') ? "<a href=\"$url\">".mt('_vndiff_image_nsfw').'</a>' : "<img src=\"$url\" />";
      } else {
        return mt '_vndiff_image_none';
      }
    }],
    [ img_nsfw    => serialize => sub { mt $_[0] ? '_vndiff_nsfw_notsafe' : '_vndiff_nsfw_safe' } ],
  );
}


sub _producers {
  my($self, $r) = @_;

  my %lang;
  my @lang = grep !$lang{$_}++, map @{$_->{languages}}, @$r;

  if(grep $_->{developer}, map @{$_->{producers}}, @$r) {
    my %dev = map $_->{developer} ? ($_->{id} => $_) : (), map @{$_->{producers}}, @$r;
    my @dev = values %dev;
    Tr;
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
    Tr;
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
  my($self, $v) = @_;

  my %rel;
  push @{$rel{$_->{relation}}}, $_
    for (sort { $a->{title} cmp $b->{title} } @{$v->{relations}});


  Tr;
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
  my($self, $v) = @_;

  Tr;
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
        abbr title => $_->{title_kanji}||$_->{title_romaji}, shorten $_->{title_romaji}, 50;
        b ' ('.(defined $_->{type} ? mt("_animetype_$_->{type}").', ' : '').$_->{year}.')';
        br;
      }
    }
   end;
  end 'tr';
}


sub _useroptions {
  my($self, $v) = @_;

  my $vote = $self->dbVoteGet(uid => $self->authInfo->{id}, vid => $v->{id})->[0];
  my $list = $self->dbVNListGet(uid => $self->authInfo->{id}, vid => $v->{id})->[0];
  my $wish = $self->dbWishListGet(uid => $self->authInfo->{id}, vid => $v->{id})->[0];

  Tr;
   td mt '_vnpage_uopt';
   td;
    if($vote || !$wish) {
      Select id => 'votesel', name => $self->authGetCode("/v$v->{id}/vote");
       option value => -3, $vote ? mt '_vnpage_uopt_voted', fmtvote($vote->{vote}) : mt '_vnpage_uopt_novote';
       optgroup label => $vote ? mt '_vnpage_uopt_changevote' : mt '_vnpage_uopt_dovote';
        option value => $_, "$_ (".mt("_vote_$_").')' for (reverse 1..10);
        option value => -2, mt '_vnpage_uopt_othvote';
       end;
       option value => -1, mt '_vnpage_uopt_delvote' if $vote;
      end;
      br;
    }

    Select id => 'listsel', name => $self->authGetCode("/v$v->{id}/list");
     option $list ? mt '_vnpage_uopt_vnlisted', mtvnlstat $list->{status} : mt '_vnpage_uopt_novn';
     optgroup label => $list ? mt '_vnpage_uopt_changevn' : mt '_vnpage_uopt_addvn';
      option value => $_, mtvnlstat $_ for (@{$self->{rlist_status}});
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


sub _affiliate_links {
  my($self, $r) = @_;
  return if !keys @$r;
  my %r = map +($_->{id}, $_), @$r;
  my $links = $self->dbAffiliateGet(rids => [ keys %r ], hidden => 0);
  return if !@$links;

  $links = [ sort { $b->{priority}||$self->{affiliates}[$b->{affiliate}]{default_prio} <=> $a->{priority}||$self->{affiliates}[$a->{affiliate}]{default_prio} } @$links ];
  my $en = VNDB::L10N->get_handle('en');

  Tr id => 'buynow';
   td 'Available at';
   td;
    for my $link (@$links) {
      my $f = $self->{affiliates}[$link->{affiliate}];
      my $rel = $r{$link->{rid}};
      my $plat = join(' and ', map $en->maketext("_plat_$_"), @{$rel->{platforms}});
      my $version = join(' and ', map $en->maketext("_lang_$_"), @{$rel->{languages}}).' '.$plat.' version';

      a rel => 'nofollow', href => $f->{link_format} ? $f->{link_format}->($link->{url}) : $link->{url};
       use utf8;
       txt $link->{version}
         || ($f->{default_version} && $f->{default_version}->($self, $link, $rel))
         || $version;
       txt " at $f->{name}";
       abbr class => 'pricenote', title =>
           $link->{lastfetch} ? sprintf('Last updated: %s.', $en->age($link->{lastfetch})) : '', " for $link->{price}"
         if $link->{price};
       txt ' »';
      end;
      br;
    }
   end;
  end;
}


sub _releases {
  my($self, $v, $r) = @_;

  div class => 'mainbox releases';
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
             $rel->{ulist} ? mtrlstat $rel->{ulist}{status} : '--';
          } else {
            txt ' ';
          }
         end;
         td class => 'tc6';
          a href => "/affiliates/new?rid=$rel->{id}", 'a' if $self->authCan('affiliate');
          if($rel->{website}) {
            a href => $rel->{website}, rel => 'nofollow';
             cssicon 'external', mt '_vnpage_rel_extlink';
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
        a href => imgurl(sf => $_->{id}),
          class => sprintf('scrlnk%s%s', $_->{nsfw} ? ' nsfw':'', $_->{nsfw}&&!$self->authPref('show_nsfw')?' hidden':''),
          'data-iv' => "$_->{width}x$_->{height}:scr";
         img src => imgurl(st => $_->{id}),
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
   if(!grep $_->[0] > 0, @$stats) {
     p mt '_vnpage_stats_none';
   } else {
     $self->htmlVoteStats(v => $v, $stats);
   }
  end;
}


sub _chars {
  my($self, $has, $v) = @_;
  my $l = $has && $self->dbCharGet(vid => $v->{id}, what => "extended vns($v->{id}) seiyuu traits", results => 100);
  return if !$has;
  my %done;
  my %rol;
  for my $r (@{$self->{char_roles}}) {
    $rol{$r} = [ grep grep($_->{role} eq $r, @{$_->{vns}}) && !$done{$_->{id}}++, @$l ];
  }
  my $first = 0;
  for my $r (@{$self->{char_roles}}) {
    next if !@{$rol{$r}};
    div class => 'mainbox';
     $self->charOps(1) if !$first++;
     h1 mt "_charrole_$r", scalar @{$rol{$r}};
     for my $c (@{$rol{$r}}) {
       my $minspoil = 5;
       $minspoil = $_->{vid} == $v->{id} && $_->{spoil} < $minspoil ? $_->{spoil} : $minspoil
         for(@{$c->{vns}});
       $self->charTable($c, 1, $c != $rol{$r}[0], 1, $minspoil);
     }
    end;
  }
}


sub _staff {
  my ($self, $v) = @_;
  if(@{$v->{credits}}) {
    div class => 'mainbox staff', id => 'staff';
     h1 mt '_vnpage_staff';
     for my $r (@{$self->{staff_roles}}) {
       my @s = grep $_->{role} eq $r, @{$v->{credits}};
       next if !@s;
       ul;
        li; b mt '_credit_'.$r; end;
        for(@s) {
          li;
           a href => "/s$_->{id}", title => $_->{original}||$_->{name}, $_->{name};
           b class => 'grayedout', $_->{note} if $_->{note};
          end;
        }
       end;
     }
     clearfloat;
    end;
  }
  if(@{$v->{seiyuu}}) {
    my($has_spoilers, %cast);
    # %cast hash serves only one purpose: in the rare case of several voice
    # actors voicing single character it groups them all together.
    for(@{$v->{seiyuu}}) {
      $has_spoilers ||= $_->{spoil};
      push @{$cast{$_->{cid}}}, $_;
    }
    div class => 'mainbox staff cast';
     $self->charOps(0) if $has_spoilers;
     h1 mt '_vnpage_cast';
     div class => 'cast_list';
      # i wonder whether it's better to just ask database for character list instead
      # of doing this manual group/sort
      for my $cid (sort { $cast{$a}[0]{cname} cmp $cast{$b}[0]{cname} } keys %cast) {
        my $s = $cast{$cid};
        div class => 'char_bubble'.($has_spoilers ? ' '.charspoil($s->[0]{spoil}) : '');
         div class => 'name';
          a href => "/c$cid", $s->[0]{cname};
         end;
         div class => 'actor';
          txt mt '_charp_voice';
          @{$s} > 1 ? br : txt ' ';
          for(@{$s}) {
            a href => "/s$_->{id}", title => $_->{original}||$_->{name}, $_->{name};
            b class => 'grayedout', $_->{note} if $_->{note};
            br;
          }
         end;
        end;
      }
     end;
    end;
  }
}


1;

