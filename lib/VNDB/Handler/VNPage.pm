
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

  my $title = "Relation graph for $v->{title}";
  return if $self->htmlRGHeader($title, 'v', $v);

  $v->{svg} =~ s/id="node_v$vid"/id="graph_current"/;

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
    column_string => 'Title',
    draw          => sub { a href => "/r$_[0]{id}", shorten $_[0]{title}, 60 },
  }, { # Type
    id            => 'typ',
    sort_field    => 'type',
    button_string => 'Type',
    default       => 1,
    draw          => sub { cssicon "rt$_[0]{type}", $_[0]{type}; txt '(patch)' if $_[0]{patch} },
  }, { # Languages
    id            => 'lan',
    button_string => 'Language',
    default       => 1,
    has_data      => sub { !!@{$_[0]{languages}} },
    draw          => sub {
      for(@{$_[0]{languages}}) {
        cssicon "lang $_", $TUWF::OBJ->{languages}{$_};
        br if $_ ne $_[0]{languages}[$#{$_[0]{languages}}];
      }
    },
  }, { # Publication
    id            => 'pub',
    sort_field    => 'publication',
    column_string => 'Publication',
    column_width  => 70,
    button_string => 'Publication',
    default       => 1,
    what          => 'extended',
    draw          => sub { txt join ', ', $_[0]{freeware} ? 'Freeware' : 'Non-free', $_[0]{patch} ? () : ($_[0]{doujin} ? 'doujin' : 'commercial') },
  }, { # Platforms
    id             => 'pla',
    button_string => 'Platforms',
    default       => 1,
    what          => 'platforms',
    has_data      => sub { !!@{$_[0]{platforms}} },
    draw          => sub {
      for(@{$_[0]{platforms}}) {
        cssicon $_, $TUWF::OBJ->{platforms}{$_};
        br if $_ ne $_[0]{platforms}[$#{$_[0]{platforms}}];
      }
      txt 'Unknown' if !@{$_[0]{platforms}};
    },
  }, { # Media
    id            => 'med',
    column_string => 'Media',
    button_string => 'Media',
    what          => 'media',
    has_data      => sub { !!@{$_[0]{media}} },
    draw          => sub {
      for(@{$_[0]{media}}) {
        txt fmtmedia($_->{medium}, $_->{qty});
        br if $_ ne $_[0]{media}[$#{$_[0]{media}}];
      }
      txt 'Unknown' if !@{$_[0]{media}};
    },
  }, { # Resolution
    id            => 'res',
    sort_field    => 'resolution',
    column_string => 'Resolution',
    button_string => 'Resolution',
    na_for_patch  => 1,
    default       => 1,
    what          => 'extended',
    has_data      => sub { !!$_[0]{resolution} },
    draw          => sub {
      if($_[0]{resolution}) {
        txt $TUWF::OBJ->{resolutions}[$_[0]{resolution}][0];
      } else {
        txt 'Unknown';
      }
    },
  }, { # Voiced
    id            => 'voi',
    sort_field    => 'voiced',
    column_string => 'Voiced',
    column_width  => 70,
    button_string => 'Voiced',
    na_for_patch  => 1,
    default       => 1,
    what          => 'extended',
    has_data      => sub { !!$_[0]{voiced} },
    draw          => sub { txt $TUWF::OBJ->{voiced}[$_[0]{voiced}] },
  }, { # Animation
    id            => 'ani',
    sort_field    => 'ani_ero',
    column_string => 'Animation',
    column_width  => 110,
    button_string => 'Animation',
    na_for_patch  => '1',
    what          => 'extended',
    has_data      => sub { !!($_[0]{ani_story} || $_[0]{ani_ero}) },
    draw          => sub {
      txt join ', ',
        $_[0]{ani_story} ? "Story: $TUWF::OBJ->{animated}[$_[0]{ani_story}]"   :(),
        $_[0]{ani_ero}   ? "Ero scenes: $TUWF::OBJ->{animated}[$_[0]{ani_ero}]":();
      txt 'Unknown' if !$_[0]{ani_story} && !$_[0]{ani_ero};
    },
  }, { # Released
    id            => 'rel',
    sort_field    => 'released',
    column_string => 'Released',
    button_string => 'Released',
    default       => 1,
    draw          => sub { lit fmtdatestr $_[0]{released} },
  }, { # Age rating
    id            => 'min',
    sort_field    => 'minage',
    button_string => 'Age rating',
    default       => 1,
    has_data      => sub { $_[0]{minage} != -1 },
    draw          => sub { txt minage $_[0]{minage} },
  }, { # Notes
    id            => 'not',
    sort_field    => 'notes',
    column_string => 'Notes',
    column_width  => 400,
    button_string => 'Notes',
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

  my $title = "Releases for $v->{title}";
  $self->htmlHeader(title => $title);
  $self->htmlMainTabs('v', $v, 'releases');

  my $f = $self->formValidate(
    map({ get => $_->{id}, required => 0, default => $_->{default}||0, enum => [0,1] }, grep $_->{button_string}, @rel_cols),
    { get => 'cw',   required => 0, default => 0, enum => [0,1] },
    { get => 'o',    required => 0, default => 0, enum => [0,1] },
    { get => 's',    required => 0, default => 'released', enum => [ map $_->{sort_field}, grep $_->{sort_field}, @rel_cols ]},
    { get => 'os',   required => 0, default => 'all',      enum => [ 'all', keys %{$self->{platforms}} ] },
    { get => 'lang', required => 0, default => 'all',      enum => [ 'all', keys %{$self->{languages}} ] },
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
     td 'We don\'t have any information about releases of this visual novel yet...';
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
   a href => $url->($_->{id}, $f->{$_->{id}} ? 0 : 1), $f->{$_->{id}} ? (class => 'optselected') : (), $_->{button_string}
     for (grep $_->{button_string}, @rel_cols);
  end;

  # Misc options
  my $all_selected   = !grep $_->{button_string} && !$f->{$_->{id}}, @rel_cols;
  my $all_unselected = !grep $_->{button_string} &&  $f->{$_->{id}}, @rel_cols;
  my $all_url = sub { $url->(map +($_->{id},$_[0]), grep $_->{button_string}, @rel_cols); };
  p class => 'browseopts';
   a href => $all_url->(1),                  $all_selected   ? (class => 'optselected') : (), 'All on';
   a href => $all_url->(0),                  $all_unselected ? (class => 'optselected') : (), 'All off';
   a href => $url->('cw', $f->{cw} ? 0 : 1), $f->{cw}        ? (class => 'optselected') : (), 'Restrict column width';
  end;

  # Platform/language filters
  my $plat_lang_draw = sub {
    my($row, $option, $txt, $csscat) = @_;
    my %opts = map +($_,1), map @{$_->{$row}}, @$r;
    return if !keys %opts;
    p class => 'browseopts';
     for('all', sort keys %opts) {
       a href => $url->($option, $_), $_ eq $f->{$option} ? (class => 'optselected') : ();
        $_ eq 'all' ? txt 'All' : cssicon "$csscat $_", $txt->{$_};
       end 'a';
     }
    end 'p';
  };
  $plat_lang_draw->('platforms', 'os',  $self->{platforms}, '')     if $f->{pla};
  $plat_lang_draw->('languages', 'lang',$self->{languages}, 'lang') if $f->{lan};
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
         txt $c->{column_string} if $c->{column_string};
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
            txt 'NA for patches';
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
    what => 'extended anime relations screenshots rating ranking staff'.($rev ? ' seiyuu' : ''),
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
       p 'No image uploaded yet';
     } else {
       p $v->{img_nsfw} ? (id => 'nsfw_hid', $self->authPref('show_nsfw') ? () : (class => 'hidden')) : ();
        img src => imgurl(cv => $v->{image}), alt => $v->{title};
        i 'Flagged as NSFW' if $v->{img_nsfw};
       end;
       if($v->{img_nsfw}) {
         p id => 'nsfw_show', $self->authPref('show_nsfw') ? (class => 'hidden') : ();
          txt 'This image has been flagged as Not Safe For Work.';
          br; br;
          a href => '#', 'Show me anyway';
          br; br;
          txt '(This warning can be disabled in your account)';
         end;
       }
     }
    end 'div'; # /vnimg

    # general info
    table class => 'stripe';
     Tr;
      td class => 'key', 'Title';
      td $v->{title};
     end;
     if($v->{original}) {
       Tr;
        td 'Original title';
        td $v->{original};
       end;
     }
     if($v->{alias}) {
       $v->{alias} =~ s/\n/, /g;
       Tr;
        td 'Aliases';
        td $v->{alias};
       end;
     }
     if($v->{length}) {
       Tr;
        td 'Length';
        td fmtvnlen $v->{length}, 1;
       end;
     }
     my @links = (
       $v->{l_wp} ?      [ 'Wikipedia', 'http://en.wikipedia.org/wiki/%s', $v->{l_wp} ] : (),
       $v->{l_encubed} ? [ 'Encubed',   'http://novelnews.net/tag/%s/', $v->{l_encubed} ] : (),
       $v->{l_renai} ?   [ 'Renai.us',  'http://renai.us/game/%s.shtml', $v->{l_renai} ] : (),
     );
     if(@links) {
       Tr;
        td 'Links';
        td;
         for(@links) {
           a href => sprintf($_->[1], $_->[2]), $_->[0];
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
       h2 'Description';
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
      a href => "#$_", $tags_cat =~ /\Q$_/ ? (class => 'tsel') : (), lc $self->{tag_categories}{$_} for keys %{$self->{tag_categories}};
      my $spoiler = $self->authPref('spoilers') || 0;
      a href => '#', class => 'sec'.($spoiler == 0 ? ' tsel' : ''), lc 'Hide spoilers';
      a href => '#', $spoiler == 1 ? (class => 'tsel') : (), lc 'Show minor spoilers';
      a href => '#', $spoiler == 2 ? (class => 'tsel') : (), lc 'Spoil me!';
      a href => '#', class => 'sec'.($self->authPref('tags_all') ? '': ' tsel'), 'summary';
      a href => '#', $self->authPref('tags_all') ? (class => 'tsel') : (), 'all';
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

  my $chars = $self->dbCharGet(vid => $v->{id}, what => "seiyuu vns($v->{id})".($char ? ' extended traits' : ''), results => 100);
  if(@$chars || $self->authCan('edit')) {
    clearfloat; # fix tabs placement when tags are hidden
    ul class => 'maintabs notfirst';
     if(@$chars) {
       li class => 'left '.(!$char ? ' tabselected' : ''); a href => "/v$v->{id}#main", name => 'main', 'main'; end;
       li class => 'left '.($char  ? ' tabselected' : ''); a href => "/v$v->{id}/chars#chars", name => 'chars', 'characters'; end;
     }
     if($self->authCan('edit')) {
       li; a href => "/c/new?vid=$v->{id}", 'add character'; end;
       li; a href => "/v$v->{id}/add", 'add release'; end;
     }
    end;
  }

  if($char) {
    _chars($self, $chars, $v);
  } else {
    _releases($self, $v, $r);
    _staff($self, $v);
    _charsum($self, $chars, $v);
    _stats($self, $v);
    _screenshots($self, $v, $r) if @{$v->{screenshots}};
  }

  $self->htmlFooter;
}


sub _revision {
  my($self, $v, $rev) = @_;
  return if !$rev;

  my $prev = $rev && $rev > 1 && $self->dbVNGetRev(
    id => $v->{id}, rev => $rev-1, what => 'extended anime relations screenshots staff seiyuu'
  )->[0];

  $self->htmlRevision('v', $prev, $v,
    [ title       => 'Title (romaji)', diff => 1 ],
    [ original    => 'Original title', diff => 1 ],
    [ alias       => 'Alias',          diff => qr/[ ,\n\.]/ ],
    [ desc        => 'Description',    diff => qr/[ ,\n\.]/ ],
    [ length      => 'Length',         serialize => sub { fmtvnlen $_[0] } ],
    [ l_wp        => 'Wikipedia link', htmlize => sub {
      $_[0] ? sprintf '<a href="http://en.wikipedia.org/wiki/%s">%1$s</a>', xml_escape $_[0] : '[empty]'
    }],
    [ l_encubed   => 'Encubed tag', htmlize => sub {
      $_[0] ? sprintf '<a href="http://novelnews.net/tag/%s/">%1$s</a>', xml_escape $_[0] : '[empty]'
    }],
    [ l_renai     => 'Renai.us link', htmlize => sub {
      $_[0] ? sprintf '<a href="http://renai.us/game/%s.shtml">%1$s</a>', xml_escape $_[0] : '[empty]'
    }],
    [ credits     => 'Credits', join => '<br />', split => sub {
      my @r = map sprintf('<a href="/s%d" title="%s">%s</a> [%s]%s', $_->{id},
          xml_escape($_->{original}||$_->{name}), xml_escape($_->{name}), xml_escape($self->{staff_roles}{$_->{role}}),
          $_->{note} ? ' ['.xml_escape($_->{note}).']' : ''),
        sort { $a->{id} <=> $b->{id} || $a->{role} cmp $b->{role} } @{$_[0]};
      return @r ? @r : ('[empty]');
    }],
    [ seiyuu      => 'Seiyuu', join => '<br />', split => sub {
      my @r = map sprintf('<a href="/s%d" title="%s">%s</a> as %s%s',
          $_->{id}, xml_escape($_->{original}||$_->{name}), xml_escape($_->{name}), xml_escape($_->{cname}),
          $_->{note} ? ' ['.xml_escape($_->{note}).']' : ''),
        sort { $a->{id} <=> $b->{id} || $a->{cid} <=> $b->{cid} || $a->{note} cmp $b->{note} } @{$_[0]};
      return @r ? @r : ('[empty]');
    }],
    [ relations   => 'Relations', join => '<br />', split => sub {
      my @r = map sprintf('[%s] %s: <a href="/v%d" title="%s">%s</a>',
        $_->{official} ? 'official' : 'unofficial', $self->{vn_relations}{$_->{relation}}[1],
        $_->{id}, xml_escape($_->{original}||$_->{title}), xml_escape shorten $_->{title}, 40
      ), sort { $a->{id} <=> $b->{id} } @{$_[0]};
      return @r ? @r : ('[empty]');
    }],
    [ anime       => 'Anime', join => ', ', split => sub {
      my @r = map sprintf('<a href="http://anidb.net/a%d">a%1$d</a>', $_->{id}), sort { $a->{id} <=> $b->{id} } @{$_[0]};
      return @r ? @r : ('[empty]');
    }],
    [ screenshots => 'Screenshots', join => '<br />', split => sub {
      my @r = map sprintf('[%s] <a href="%s" data-iv="%dx%d">%d</a> (%s)',
        $_->{rid} ? qq|<a href="/r$_->{rid}">r$_->{rid}</a>| : 'no release',
        imgurl(sf => $_->{id}), $_->{width}, $_->{height}, $_->{id},
        $_->{nsfw} ? 'Not safe' : 'Safe'
      ), @{$_[0]};
      return @r ? @r : ('[empty]');
    }],
    [ image       => 'Image', htmlize => sub {
      my $url = imgurl(cv => $_[0]);
      if($_[0]) {
        return $_[1]->{img_nsfw} && !$self->authPref('show_nsfw') ? "<a href=\"$url\">(NSFW)</a>" : "<img src=\"$url\" />";
      } else {
        return 'No image';
      }
    }],
    [ img_nsfw    => 'Image NSFW', serialize => sub { $_[0] ? 'Not safe' : 'Safe' } ],
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
     td 'Developer';
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
     td 'Publishers';
     td;
      for my $l (@lang) {
        my %p = map $_->{publisher} ? ($_->{id} => $_) : (), map @{$_->{producers}}, grep grep($_ eq $l, @{$_->{languages}}), @$r;
        my @p = values %p;
        next if !@p;
        cssicon "lang $l", $self->{languages}{$l};
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
   td 'Relations';
   td class => 'relations';
    dl;
     for(sort keys %rel) {
       dt $self->{vn_relations}{$_}[1];
       dd;
        for (@{$rel{$_}}) {
          b class => 'grayedout', '[unofficial] ' if !$_->{official};
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
   td 'Related anime';
   td class => 'anime';
    for (sort { ($a->{year}||9999) <=> ($b->{year}||9999) } @{$v->{anime}}) {
      if(!$_->{lastfetch} || !$_->{year} || !$_->{title_romaji}) {
        b;
         lit sprintf '[no information available at this time: <a href="http://anidb.net/a%d">%1$d</a>]', $_->{id};
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
        b ' ('.(defined $_->{type} ? $self->{anime_types}{$_->{type}}.', ' : '').$_->{year}.')';
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
   td 'User options';
   td;
    if($vote || !$wish) {
      Select id => 'votesel', name => $self->authGetCode("/v$v->{id}/vote");
       option value => -3, $vote ? 'your vote: '.fmtvote($vote->{vote}) : 'not voted yet';
       optgroup label => $vote ? 'Change vote' : 'Vote';
        option value => $_, "$_ (".fmtrating($_).')' for (reverse 1..10);
        option value => -2, 'Other';
       end;
       option value => -1, 'revoke' if $vote;
      end;
      br;
    }

    Select id => 'listsel', name => $self->authGetCode("/v$v->{id}/list");
     option $list ? "VN list: $self->{vnlist_status}[$list->{status}]" : 'not on your VN list';
     optgroup label => $list ? 'Change status' : 'Add to VN list';
      option value => $_, $self->{vnlist_status}[$_] for (0..$#{$self->{vnlist_status}});
     end;
     option value => -1, 'remove from VN list' if $list;
    end;
    br;

    if(!$vote || $wish) {
      Select id => 'wishsel', name => $self->authGetCode("/v$v->{id}/wish");
       option $wish ? "wishlist: $self->{wishlist_status}[$wish->{wstat}]" : 'not on your wishlist';
       optgroup label => $wish ? 'Change status' : 'Add to wishlist';
        option value => $_, $self->{wishlist_status}[$_] for (0..$#{$self->{wishlist_status}});
       end;
       option value => -1, 'remove from wishlist' if $wish;
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

  Tr id => 'buynow';
   td 'Available at';
   td;
    for my $link (@$links) {
      my $f = $self->{affiliates}[$link->{affiliate}];
      my $rel = $r{$link->{rid}};
      my $plat = join(' and ', map $self->{platforms}{$_}, @{$rel->{platforms}});
      my $version = join(' and ', map $self->{languages}{$_}, @{$rel->{languages}}).' '.$plat.' version';

      a rel => 'nofollow', href => $f->{link_format} ? $f->{link_format}->($link->{url}) : $link->{url};
       use utf8;
       txt $link->{version}
         || ($f->{default_version} && $f->{default_version}->($self, $link, $rel))
         || $version;
       txt " at $f->{name}";
       abbr class => 'pricenote', title =>
           $link->{lastfetch} ? sprintf('Last updated: %s.', fmtage($link->{lastfetch})) : '', " for $link->{price}"
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
   h1 'Releases';
   if(!@$r) {
     p 'We don\'t have any information about releases of this visual novel yet...';
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
        cssicon "lang $l", $self->{languages}{$l};
        txt $self->{languages}{$l};
       end;
      end;
      for my $rel (grep grep($_ eq $l, @{$_->{languages}}), @$r) {
        Tr;
         td class => 'tc1'; lit fmtdatestr $rel->{released}; end;
         td class => 'tc2', $rel->{minage} < 0 ? '' : minage $rel->{minage};
         td class => 'tc3';
          for (sort @{$rel->{platforms}}) {
            next if $_ eq 'oth';
            cssicon $_, $self->{platforms}{$_};
          }
          cssicon "rt$rel->{type}", $rel->{type};
         end;
         td class => 'tc4';
          a href => "/r$rel->{id}", title => $rel->{original}||$rel->{title}, $rel->{title};
          b class => 'grayedout', ' (patch)' if $rel->{patch};
         end;
         td class => 'tc5';
          if($self->authInfo->{id}) {
            a href => "/r$rel->{id}", id => "rlsel_$rel->{id}", class => 'vnrlsel',
             $rel->{ulist} ? $self->{rlist_status}[ $rel->{ulist}{status} ] : '--';
          } else {
            txt ' ';
          }
         end;
         td class => 'tc6';
          a href => "/affiliates/new?rid=$rel->{id}", 'a' if $self->authCan('affiliate');
          if($rel->{website}) {
            a href => $rel->{website}, rel => 'nofollow';
             cssicon 'external', 'External link';
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
      txt 'Showing ';
      i id => 'nsfwshown', $self->authPref('show_nsfw') ? scalar @{$v->{screenshots}} : scalar grep(!$_->{nsfw}, @{$v->{screenshots}});
      txt sprintf ' out of %d screenshot%s. ', scalar @{$v->{screenshots}}, @{$v->{screenshots}} == 1 ? '' : 's';
      a href => '#', id => "nsfwhide", 'show/hide NSFW';
     end;
   }

   h1 'Screenshots';

   for my $rel (@$r) {
     my @scr = grep $_->{rid} && $rel->{id} == $_->{rid}, @{$v->{screenshots}};
     next if !@scr;
     p class => 'rel';
      cssicon "lang $_", $self->{languages}{$_} for (@{$rel->{languages}});
      a href => "/r$rel->{id}", $rel->{title};
     end;
     div class => 'scr';
      for (@scr) {
        my($w, $h) = imgsize($_->{width}, $_->{height}, @{$self->{scr_size}});
        a href => imgurl(sf => $_->{id}),
          class => sprintf('scrlnk%s%s', $_->{nsfw} ? ' nsfw':'', $_->{nsfw}&&!$self->authPref('show_nsfw')?' hidden':''),
          'data-iv' => "$_->{width}x$_->{height}:scr";
         img src => imgurl(st => $_->{id}),
           width => $w, height => $h, alt => "Screenshot #$_->{id}";
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
   h1 'User stats';
   if(!grep $_->[0] > 0, @$stats) {
     p 'Nobody has voted on this visual novel yet...';
   } else {
     $self->htmlVoteStats(v => $v, $stats);
   }
  end;
}


sub _charspoillvl {
  my($vid, $c) = @_;
  my $minspoil = 5;
  $minspoil = $_->{vid} == $vid && $_->{spoil} < $minspoil ? $_->{spoil} : $minspoil
    for(@{$c->{vns}});
  return $minspoil;
}


sub _chars {
  my($self, $l, $v) = @_;
  return if !@$l;
  my %done;
  my %rol;
  for my $r (keys %{$self->{char_roles}}) {
    $rol{$r} = [ grep grep($_->{role} eq $r, @{$_->{vns}}) && !$done{$_->{id}}++, @$l ];
  }
  my $first = 0;
  for my $r (keys %{$self->{char_roles}}) {
    next if !@{$rol{$r}};
    div class => 'mainbox';
     $self->charOps(1) if !$first++;
     h1 $self->{char_roles}{$r};
     $self->charTable($_, 1, $_ != $rol{$r}[0], 1, _charspoillvl $v->{id}, $_) for (@{$rol{$r}});
    end;
  }
}


sub _charsum {
  my($self, $l, $v) = @_;
  return if !@$l;

  my(@l, %done, $has_spoilers);
  for my $r (keys %{$self->{char_roles}}) {
    last if $r eq 'appears';
    for (grep grep($_->{role} eq $r, @{$_->{vns}}) && !$done{$_->{id}}++, @$l) {
      $_->{role} = $r;
      $has_spoilers = $has_spoilers || _charspoillvl $v->{id}, $_;
      push @l, $_;
    }
  }

  div class => 'mainbox charsum summarize';
   $self->charOps(0) if $has_spoilers;
   h1 'Character summary';
   div class => 'charsum_list';
    for my $c (@l) {
      div class => 'charsum_bubble'.($has_spoilers ? ' '.charspoil(_charspoillvl $v->{id}, $c) : '');
       div class => 'name';
        i $self->{char_roles}{$c->{role}};
        a href => "/c$c->{id}", title => $c->{original}||$c->{name}, $c->{name};
       end;
       if(@{$c->{seiyuu}}) {
         div class => 'actor';
          txt 'Voiced by';
          @{$c->{seiyuu}} > 1 ? br : txt ' ';
          for my $s (sort { $a->{name} cmp $b->{name} } @{$c->{seiyuu}}) {
            a href => "/s$s->{sid}", title => $s->{original}||$s->{name}, $s->{name};
            b class => 'grayedout', $s->{note} if $s->{note};
            br;
          }
         end;
       }
      end;
    }
   end;
  end;
}


sub _staff {
  my ($self, $v) = @_;
  return if !@{$v->{credits}};

  div class => 'mainbox staff summarize', 'data-summarize-height' => 100, id => 'staff';
   h1 'Staff';
   for my $r (keys %{$self->{staff_roles}}) {
     my @s = grep $_->{role} eq $r, @{$v->{credits}};
     next if !@s;
     ul;
      li; b $self->{staff_roles}{$r}; end;
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


1;

