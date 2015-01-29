
package VNDB::Handler::VNPage;

use strict;
use warnings;
no if $] >= 5.018, warnings => 'experimental::smartmatch';
use feature qw{ switch };
use TUWF ':html', 'xml_escape';
use VNDB::Func;


TUWF::register(
  qr{v/rand}                        => \&rand,
  qr{v([1-9]\d*)/rg}                => \&rg,
  qr{v([1-9]\d*)/releases}          => \&releases,
  qr{v([1-9]\d*)/(chars|staff)}     => \&page,
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

sub releases {
  my($self, $vid) = @_;

  my $v = $self->dbVNGet(
     id => $vid)->[0];
  return $self->resNotFound if !$v->{id};

  my $title = mt('_vnpage_rel_title', $v->{title});
  $self->htmlHeader(title => $title);

  $self->htmlMainTabs('v', $v, 'releases');

  # the order of buttons and columns
  my @columb_list = (    'type',
                         'languages',
                         'publication',
                         'platforms',
                         'media',
                         'resolution',
                         'voiced',
                         'ani_ero',
                         'released',
                         'minage',
                         'notes');

  # All data specific to the individual columns
  my %c = (
   'title'       => { column_string => '_relinfo_title',
                    },
   'type'        => { button_string => '_relinfo_type',
                    },
   'languages'   => { button_string => '_relinfo_lang',
                      unsortable    => 'true',
                    },
   'publication' => { column_string => '_relinfo_publication',
                      column_width  => 'max-width: 70px',
                      button_string => '_relinfo_publication',
                    },
   'platforms'   => { button_string => '_redit_form_platforms',
                      unsortable    => 'true',
                    },
   'media'       => { column_string => '_redit_form_media',
                      button_string => '_redit_form_media',
                      unsortable    => 'true',
                    },
   'resolution'  => { column_string => '_relinfo_resolution',
                      button_string => '_relinfo_resolution',
                      na_for_patch  => '1',
                    },
   'voiced'      => { column_string => '_relinfo_voiced',
                      column_width  => 'max-width: 70px',
                      button_string => '_relinfo_voiced',
                      na_for_patch  => '1',
                    },
   'ani_ero'     => { column_string => '_relinfo_ani',
                      column_width  => 'max-width: 110px',
                      button_string => '_relinfo_ani',
                      na_for_patch  => '1',
                    },
   'released'    => { column_string => '_relinfo_released',
                      button_string => '_relinfo_released',
                    },
   'minage'      => { button_string => '_relinfo_minage',
                    },
   'notes'       => { column_string => '_redit_form_notes',
                      column_width  => 'max-width: 400px',
                      button_string => '_redit_form_notes',
                    },
   'legend'      => { unsortable    => 'true',
                    },
  );

  my $f = $self->formValidate(
   { get => 'typ',  required => 0, default => '1', enum => [ '0', '1' ] }, # type
   { get => 'lan',  required => 0, default => '1', enum => [ '0', '1' ] }, # language
   { get => 'pub',  required => 0, default => '1', enum => [ '0', '1' ] }, # publication
   { get => 'pla',  required => 0, default => '1', enum => [ '0', '1' ] }, # platform
   { get => 'med',  required => 0, default => '0', enum => [ '0', '1' ] }, # media
   { get => 'res',  required => 0, default => '1', enum => [ '0', '1' ] }, # resolution
   { get => 'voi',  required => 0, default => '1', enum => [ '0', '1' ] }, # voiced
   { get => 'ani',  required => 0, default => '0', enum => [ '0', '1' ] }, # animation
   { get => 'rel',  required => 0, default => '1', enum => [ '0', '1' ] }, # released
   { get => 'min',  required => 0, default => '1', enum => [ '0', '1' ] }, # min age
   { get => 'not',  required => 0, default => '1', enum => [ '0', '1' ] }, # notes
   { get => 'cw',   required => 0, default => '0', enum => [ '0', '1' ] }, # restrict column width
   { get => 'o',    required => 0, default => '0', enum => [ '0', '1' ] }, # sort order
   { get => 's',    required => 0, default => 'released', enum => [ grep !$c{$_}{unsortable}, keys %c ]}, # sort by column
   { get => 'os',   required => 0, default => 'all',      enum => [ 'all',  @{$self->{platforms}} ]    }, # filter by os
   { get => 'lang', required => 0, default => 'all',      enum => [ 'all',  @{$self->{languages}} ]    }, # filter by language
  );
  return $self->resNotFound if $f->{_err};

  # Get the releases
  # Setup $what_string to use only the bare minimum to reduce database load
  my $what_string = '';
  $what_string .= ' extended'  if $f->{pub}||$f->{res}||$f->{voi}||$f->{ani}||$f->{not};
  $what_string .= ' platforms' if $f->{pla};
  $what_string .= ' media'     if $f->{med};
  my $r = $self->dbReleaseGet(vid => $vid, what => $what_string, sort => $f->{s}, reverse => $f->{o});

  # url generator
  my $url = sub {
   my($type, $new_val, $new_sort_type) = @_;

   # create a link, which includes all settings in $f
   my $generated_url = "/v$vid/releases?";
   foreach ( keys %$f ) {
    if ($_ eq 's' && $type eq 'o' ) {
     # changing o changes s as well
     $generated_url .= ';s=' . $new_sort_type;
     next;
    }
    $generated_url .= ';' . $_ . '='.($type eq $_ ? $new_val : $f->{$_});
   }
   return $generated_url;
  };

  div class => 'mainbox releases_compare';
   h1 $title;

   if(!@$r) {
     # No releases to write in table
     # End before drawing anything in the table
     td mt '_vnpage_rel_none';
   } else {

    # change all column hide/show status to $new_val while keeping the rest of the settings untouched
    my $all_url = sub {
     my($new_val) = @_;

     my $generated_url = "/v$vid/releases?";
     foreach my $key ( keys %$f ) {
      # Note all columns have a length of 3 while non-columns have lengths different from 3
      $generated_url .= ';' . $key . '='. (length($key) == 3 ? $new_val : $f->{$key});
     }
     return $generated_url;
    };

    my $get_lang_plat_list = sub {
     my($type) = @_;

     my @return_array = ();
     for my $rel (@$r) {
       for my $element (@{$rel->{$type}}) {
         push(@return_array, $element) if not (grep $_ eq $element, @return_array);
        }
      }
     return sort(@return_array); # sort to make order consistent
    };

    my $all_selected = sub {
     my($value) = @_;

     for (@columb_list) {
      if (!$f->{substr($_,0,3)} != !$value) {
       return 0;
      }
     }
     return 1;
    };

    # Language and platform drawing code is almost identical. Skip writing it twice
    my $plat_lang_draw = sub {
     my($row, $option, $lang) = @_;

     if (!$f->{substr($row, 0, 3)}) {
      # Column is hidden
      # Do not display row of platforms/flags as they aren't read from the database
      # Set filter to all as it makes no sense to try to filter by hidden and potientially unread data
      $f->{$option} = 'all';
      return;
     }

     p class => 'browseopts';
     foreach ( 'all', $get_lang_plat_list->($row)) {
      a href => $url->($option, $_),                            $_ eq $f->{$option} ? (class => 'optselected') : ();
      $_ eq 'all' ? txt mt '_all' :
      cssicon "$lang $_", mt '_' . substr($row, 0, 4) . '_' . $_;
      end 'a';
     };
     end 'p';
    };

    p class => 'browseopts';
     foreach ( @columb_list ) {
      my $short_name = substr($_, 0, 3);
      a href => $url->($short_name, $f->{$short_name} ? 0 : 1), $f->{$short_name}   ? (class => 'optselected') : (), mt $c{$_}{button_string};
     };
    end;
    p class => 'browseopts';
    a href => $all_url->(1),                                    $all_selected->(1)  ? (class => 'optselected') : (), mt '_all_on';
    a href => $all_url->(0),                                    $all_selected->(0)  ? (class => 'optselected') : (), mt '_all_off';
     a href => $url->('cw', $f->{cw} ? 0 : 1),                  $f->{cw}            ? (class => 'optselected') : (), mt '_vnpage_restrict_column_width';
    end;

    $plat_lang_draw->('platforms', 'os',    ''   );
    $plat_lang_draw->('languages', 'lang', 'lang');
   }
  end 'div';
  if(!@$r) {
   $self->htmlFooter;
   return;
  }

  # Remove all releases which fails to meet the platform and language filter settings
  my $counter = 0;
  while ($counter <= $#$r) {
   my $rel = @$r[$counter];
   if (($f->{os}   eq 'all' || $f->{os}   ~~ $rel->{platforms}) &&
       ($f->{lang} eq 'all' || $f->{lang} ~~ $rel->{languages}) ){
    $counter++;
   } else {
    splice @$r, $counter, 1;
   }
  };

  div class => 'mainbox releases_compare';
   table;

    $counter = 0;
    my @column_types = ( 'title' );
    foreach ( @columb_list ) {
     next if not $f->{substr($_, 0, 3)}; # skip columns unselected in f
     if (_column_is_in_use($r, $_)){
      push(@column_types, $_);
      $counter++;
      if ($counter == 3) {
       $counter = 0;
       push(@column_types, 'legend');
       # Legend adds a narrow column, which is hardcoded with rowspan => 1
       # This gives each block the same colour as the titles, which should help read the spreadsheet
      }
     }
    }

    # Draw the top/key row based on @column_types
    thead;
     Tr;
      foreach my $column_type (@column_types) {
       td class => 'key';
        txt mt $c{$column_type}{column_string} if $c{$column_type}{column_string};
        if (!$c{$column_type}{unsortable}) {
         for(0..1) {
          # draw the assending/decending arrows
          # draw it in a a container with a link unless it is the already selected one
          my $make_link = !($f->{s} eq $column_type && $f->{o} == $_);
          a href => $url->('o', $_, $column_type) if $make_link;
           lit $_ ? "\x{25BE}" : "\x{25B4}";
          end 'a' if $make_link;
         }
        }
       end 'td';
      }
     end 'tr';
    end 'thead';

    my $td_type      = 0;
    my $column_width = 0;
    my @height = ((0) x $#column_types);

    for my $r_index (0 .. $#{$r}) {
     my $rel = @$r[$r_index];
     Tr;
     for my $column_index (0 .. $#column_types) {
      next if $height[$column_index] || $column_width; # already drawn multicell box

      my $column = $column_types[$column_index];

      # assume a height of 1, then add 1 for each following release with identical setting in $column
      $height[$column_index] = 1;
      while ($r_index + $height[$column_index] <= $#{$r} &&                                                    # end of release array not reached
             _compare_rel(@$r[$r_index + $height[$column_index]], $rel, $column, $c{$column}{na_for_patch})) { # $column are identical in both releases
       $height[$column_index]++;
      }

      $column_width = 1;
      if ($c{$column}{na_for_patch} && $rel->{patch}) {
       my $skipped_legend = 0;
       while (($column_index + $column_width + $skipped_legend) <= $#column_types &&                # end array not reached
             (($c{$column_types[$column_index + $column_width + $skipped_legend]}{na_for_patch}) || # column with no data for patches
               $column_types[$column_index + $column_width + $skipped_legend] eq 'legend' )) {      # ignore legends
        if ($column_types[$column_index + $column_width + $skipped_legend] eq 'legend') {
         # column just right of a patch cell is a legend
         # remember this and continue to check
         $skipped_legend = 1;
        } else {
         if ($skipped_legend) {
          # last column was a legend
          # include this one in the patch cell since the columns on both sides will be included in the patch cell
          $height[$column_index + $column_width] = $height[$column_index];
          $column_width++;
          $skipped_legend = 0;
         }
         $height[$column_index + $column_width] = $height[$column_index];
         $column_width++;
        }
       }
      }

      td class   => $height[$column_index] > 1 ? 'multi' : ($td_type ? 'bg' : 'normal'),
         rowspan => $height[$column_index],
         colspan => $column_width,
         $column_width > 1 ? ( align => 'center' ) : (),
         $c{$column}{column_width} && $f->{cw} ? (style => $c{$column}{column_width}) : ();
      if ($c{$column}{na_for_patch} && $rel->{patch}) {
       txt mt '_vnpage_na_for_patches';
      } else {
       _write_release_string($self, $rel, $column);
      }
      end 'td';
     } continue {
      $height[$column_index]-- if $height[$column_index];
      $column_width--          if $column_width;
     }
     end 'tr';
    } continue {
     # Toggle td_type
     # This will provide the same effect as stripe table class,
     #  except rowspan settings will not cause the columns to go out of sync
     $td_type = !$td_type;
    }
   end 'table';
  end 'div';
  $self->htmlFooter;
}

sub _column_is_in_use {
  my($r, $column_type) = @_;

  for my $rel (@$r) {
   given ($column_type) {
    # Some types should always be printet. Title is always needed
    # Some types contains info even when unset (like non-free commercial publications)
    when ('title')      { return 1                                       }
    when ('type')       { return 1                                       }
    when ('languages')  { return 1 if @{$rel->{languages}}               }
    when ('publication'){ return 1                                       }
    when ('platforms')  { return 1 if @{$rel->{platforms}}               }
    when ('media')      { return 1 if @{$rel->{media}}                   }
    when ('resolution') { return 1 if $rel->{resolution}                 }
    when ('voiced')     { return 1 if $rel->{voiced}                     }
    when ('ani_ero')    { return 1 if $rel->{ani_story}||$rel->{ani_ero} }
    when ('released')   { return 1                                       }
    when ('minage')     { return 1 if $rel->{minage} != -1               }
    when ('notes')      { return 1 if $rel->{notes}                      }
   }
  }
  # No release has data set in the column in question and return value should be false
  # However every row should be drawn (true) in case all releases are filtered out
  return !@$r;
}

## Compare a specific variable in two releases
#  Returns true if $variable is identical in both releases
sub _compare_rel {
  my($last_rel, $rel, $variable, $patch_na_var) = @_;

  if ($patch_na_var) {
   return 0 if !$rel->{patch} != !$last_rel->{patch};
   return 1 if  $rel->{patch} &&  $last_rel->{patch};
  }

  if ($variable eq 'resolution' || $variable eq 'voiced' || $variable eq 'released' || $variable eq 'minage') {
   return $last_rel->{$variable} == $rel->{$variable}
  } elsif ($variable eq 'ani_ero') {
   return $last_rel->{ani_story} eq $rel->{ani_story} &&
          $last_rel->{ani_ero}   eq $rel->{ani_ero};
  } elsif ($variable eq 'media' || $variable eq 'platforms' || $variable eq 'languages'){
   if (scalar @{$last_rel->{$variable}} != scalar @{$rel->{$variable}}) {
    # last_rel and rel can't be identical if they even fail to have the same length of arrays
    # No need to check anything else
    return 0;
   }
   if (scalar @{$last_rel->{$variable}} == 0) {
    # Both are empty
    return 1;
   }

   # check for each item in last_rel to find an identical item in rel
   for my $item_a (@{$last_rel->{$variable}}) {
    my $test_var = 0;
    for my $item_b (@{$rel->{$variable}}) {
     if ($variable eq 'media') {
      if ($item_a->{medium} eq $item_b->{medium} &&
        $item_a->{qty}    == $item_b->{qty}){
       $test_var = 1;
      }
     } elsif ($item_a eq $item_b){
       $test_var = 1;
     }
    }
    if ($test_var == 0) {
     # no match
     # $item_a from $last_rel is not present in $rel
     return 0;
    }
   }
   # everything from last_rel is found in rel
   return 1;
  } elsif ($variable eq 'type') {
   return  $last_rel->{type}     eq  $rel->{type} &&
          !$last_rel->{patch}    == !$rel->{patch}
  } elsif ($variable eq 'publication') {
   return !$last_rel->{patch}    == !$rel->{patch} &&
          !$last_rel->{freeware} == !$rel->{freeware} &&
          !$last_rel->{doujin}   == !$rel->{doujin}
  } elsif ($variable eq 'notes') {
   return  $last_rel->{notes}    eq  $rel->{notes};
  }
  # Any line reaching this has no code to compare.
  # Treat everything as unique and return 0.
  # Note: certain types like title ends up here by design
  return 0;
}

## Draw the text/icon for a release
#  Draw the string for $variable in release $rel
#  No code to tell where to draw. Caller is responsible for setup of Tr, td and similar
sub _write_release_string {
  my($self, $rel, $variable) = @_;

  given ($variable) {
   when ('title')      { a href => "/r$rel->{id}", shorten $rel->{title}, 60 }
   when ('type')       { cssicon "rt$rel->{type}", mt "_rtype_$rel->{type}";
                         txt mt '_vnpage_rel_patch' if $rel->{patch};
                       }
   when ('languages')  { for (@{$rel->{languages}}) {
                          cssicon "lang $_", mt "_lang_$_";
                          br if $_ ne $rel->{languages}[$#{$rel->{languages}}];
                         }
                         txt mt '_unknown' if !@{$rel->{languages}};
                       }
   when ('publication'){ txt mt $rel->{patch} ? '_relinfo_pub_patch' : '_relinfo_pub_nopatch', $rel->{freeware}?0:1, $rel->{doujin}?0:1 }
   when ('platforms')  { for(@{$rel->{platforms}}) {
                          cssicon $_, mt "_plat_$_";
                          br if $_ ne $rel->{platforms}[$#{$rel->{platforms}}];
                         }
                         txt mt '_unknown' if !@{$rel->{platforms}};
                       }
   when ('media')      { for (@{$rel->{media}}) {
                         txt $self->{media}{$_->{medium}} ? $_->{qty}.' '.mt("_med_$_->{medium}", $_->{qty}) : mt("_med_$_->{medium}",1);
                         br if $_ ne $rel->{media}[$#{$rel->{media}}];
                        }
                        txt mt '_unknown' if !@{$rel->{media}};
                       }
   when ('resolution') { if($rel->{resolution}) {
                          my $res = $self->{resolutions}[$rel->{resolution}][0];
                          txt $res =~ /^_/ ? mt $res : $res;
                         } else {
                          txt mt '_unknown';
                         }
                       }
   when ('voiced')     { txt mtvoiced $rel->{voiced}; }
   when ('ani_ero')    { txt join ', ',
                         $rel->{ani_story} ? mt('_relinfo_ani_story', mtani $rel->{ani_story}):(),
                         $rel->{ani_ero}   ? mt('_relinfo_ani_ero',   mtani $rel->{ani_ero}  ):();
                         txt mt '_unknown' if !$rel->{ani_story} && !$rel->{ani_ero};
                       }
   when ('released')   { lit $self->{l10n}->datestr($rel->{released}) }
   when ('minage')     { txt minage $rel->{minage} }
   when ('notes')      { lit bb2html "$rel->{notes}"; }
  }
}

sub page {
  my($self, $vid, $rev) = @_;

  my $char = $rev && $rev eq 'chars';
  my $staff = $rev && $rev eq 'staff';
  $rev = undef if $char || $staff;

  my $v = $self->dbVNGet(
    id => $vid,
    what => 'extended anime relations screenshots rating ranking'.($staff || $rev ? ' credits' : '').($rev ? ' changes' : ''),
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
     } else {
       p $v->{img_nsfw} ? (id => 'nsfw_hid', style => $self->authPref('show_nsfw') ? 'display: block' : '') : ();
        img src => imgurl(cv => $v->{image}), alt => $v->{title};
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
      a href => '#cont', lc mt '_tagcat_cont';
      a href => '#ero',  lc mt '_tagcat_ero';
      a href => '#tech', lc mt '_tagcat_tech';
      a href => '#', class => 'sec tsel', mt '_vnpage_tags_spoil0';
      a href => '#', mt '_vnpage_tags_spoil1';
      a href => '#', mt '_vnpage_tags_spoil2';
      a href => '#', class => 'sec', mt '_vnpage_tags_summary';
      a href => '#', mt '_vnpage_tags_all';
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
  my $hasstaff = $self->dbVNHasStaff($v->{id});
  if($haschar || $hasstaff || $self->authCan('edit')) {
    clearfloat; # fix tabs placement when tags are hidden
    ul class => 'maintabs notfirst';
     if($haschar || $hasstaff) {
       li class => 'left '.(!($char || $staff) && ' tabselected'); a href => "/v$v->{id}#main", name => 'main', mt '_vnpage_tab_main'; end;
       if ($haschar) {
         li class => 'left '.($char ? ' tabselected' : ''); a href => "/v$v->{id}/chars#chars", name => 'chars', mt '_vnpage_tab_chars'; end;
       }
       if ($hasstaff) {
         li class => 'left '.($staff ? ' tabselected' : ''); a href => "/v$v->{id}/staff#staff", name => 'staff', mt '_vnpage_tab_staff'; end;
       }
     }
     if($self->authCan('edit')) {
       li; a href => "/c/new?vid=$v->{id}", mt '_vnpage_char_add'; end;
       if(!$v->{locked}) {
         li;
          a href => "/v$v->{id}/edit#vn_staff", mt $hasstaff ? '_vnpage_staff_edit' : '_vnpage_staff_add';
         end;
       }
       li; a href => "/v$v->{id}/add", mt '_vnpage_rel_add'; end;
     }
    end;
  }

  if($char) {
    _chars($self, $haschar, $v);
  } elsif ($staff) {
    _staff($self, $v) if $hasstaff;
  } else {
    _releases($self, $v, $r);
    _stats($self, $v);
    _screenshots($self, $v, $r) if @{$v->{screenshots}};
  }

  $self->htmlFooter;
}


sub _revision {
  my($self, $v, $rev) = @_;
  return if !$rev;

  my $prev = $rev && $rev > 1 && $self->dbVNGet(
    id => $v->{id}, rev => $rev-1, what => 'extended anime relations screenshots credits changes'
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
      my @r = map sprintf('<a href="/s%d" title="%s">%s</a> [%s]%s',
        $_->{id}, xml_escape($_->{original}||$_->{name}), xml_escape($_->{name}), mt("_credit_$_->{role}"), $_->{note} ? ' ['.xml_escape($_->{note}).']' : ''), sort { $a->{id} <=> $b->{id} } @{$_[0]};
      return @r ? @r : (mt '_revision_empty');
    }],
    [ seiyuu      => join => '<br />', split => sub {
      my @r = map sprintf('<a href="/s%d" title="%s">%s</a> %s%s',
          $_->{id}, xml_escape($_->{original}||$_->{name}), xml_escape($_->{name}),
          mt('_staff_as', xml_escape($_->{cname})),
          $_->{note} ? ' ['.xml_escape($_->{note}).']' : ''),
        sort { $a->{id} <=> $b->{id} } @{$_[0]};
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
      my @r = map sprintf('[%s] <a href="%s" rel="iv:%dx%d">%d</a> (%s)',
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
        acronym title => $_->{title_kanji}||$_->{title_romaji}, shorten $_->{title_romaji}, 50;
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
       acronym class => 'pricenote', title =>
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
        a href => imgurl(sf => $_->{id}),
          class => sprintf('scrlnk%s%s', $_->{nsfw} ? ' nsfw':'', $_->{nsfw}&&!$self->authPref('show_nsfw')?' hidden':''),
          rel => "iv:$_->{width}x$_->{height}:scr";
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
  # TODO: spoiler handling + hide unimportant roles by default
  my %done;
  my %rol;
  for my $r (@{$self->{char_roles}}) {
    $rol{$r} = [ grep grep($_->{role} eq $r, @{$_->{vns}}) && !$done{$_->{id}}++, @$l ];
  }
  my $first = 0;
  for my $r (@{$self->{char_roles}}) {
    next if !@{$rol{$r}};
    div class => 'mainbox';
     if(!$first++) {
       p id => 'charspoil_sel';
        a href => '#', class => 'sel', mt '_vnpage_tags_spoil0'; # _vnpage!?
        a href => '#', mt '_vnpage_tags_spoil1';
        a href => '#', mt '_vnpage_tags_spoil2';
       end;
     }
     h1 mt "_charrole_$r";
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
    div class => 'mainbox staff';
     h1 mt '_vnpage_staff';
     my $has_notes = grep { $_->{note} } @{$v->{credits}};
     table class => 'stripe';
      thead;
       Tr;
        td class => 'tc1', mt '_staff_col_role';
        td class => 'tc2', mt '_staff_col_credit';
        td class => 'tc3', mt '_staff_col_note' if $has_notes;
       end;
      end;
      my $last_role = '';
      for my $s (@{$v->{credits}}) {
        Tr;
         td class => 'tc1', $s->{role} ne $last_role ? mt '_credit_'.$s->{role} : '';
         td class => 'tc2';
          a href => "/s$s->{id}", title => $s->{original}||$s->{name}, $s->{name};
         end;
         td class => 'tc3', $s->{note} if $has_notes;
        end;
        $last_role = $s->{role};
      }
     end 'table';
    end;
  }
  my @seiyuu = grep !$_->{spoil}, @{$v->{seiyuu}};
  if(@seiyuu) {
    div class => 'mainbox staff cast';
     h1 mt '_vnpage_cast';
     my $has_notes  = grep { $_->{note} } @seiyuu;
     table class => 'stripe';
      thead;
       Tr;
        td class => 'tc1', mt '_staff_col_cast';
        td class => 'tc2', mt '_staff_col_seiyuu';
        td class => 'tc3', mt '_staff_col_note' if $has_notes;
       end;
      end;
      for my $s (@seiyuu) {
        next if $s->{spoil};
        Tr;
         td class => 'tc1';
          a href => "/c$s->{cid}", $s->{cname};
         end;
         td class => 'tc2';
          a href => "/s$s->{id}", title => $s->{original}||$s->{name}, $s->{name};
         end;
         td class => 'tc3', $s->{note} if $has_notes;
        end;
      }
     end 'table';
    end;
  }
}


1;

