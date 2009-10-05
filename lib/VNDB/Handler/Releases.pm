
package VNDB::Handler::Releases;

use strict;
use warnings;
use YAWF ':html';
use VNDB::Func;


YAWF::register(
  qr{r([1-9]\d*)(?:\.([1-9]\d*))?} => \&page,
  qr{(v)([1-9]\d*)/add}            => \&edit,
  qr{r}                            => \&browse,
  qr{r(?:([1-9]\d*)(?:\.([1-9]\d*))?/(edit|copy))}
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
      [ vn         => join => '<br />', split => sub {
        map sprintf('<a href="/v%d" title="%s">%s</a>', $_->{vid}, $_->{original}||$_->{title}, shorten $_->{title}, 50), @{$_[0]};
      } ],
      [ type       => serialize => sub { mt "_rtype_$_[0]" } ],
      [ patch      => serialize => sub { $_[0] ? 'Patch' : 'Not a patch' } ],
      [ freeware   => serialize => sub { $_[0] ? 'yes' : 'nope' } ],
      [ doujin     => serialize => sub { $_[0] ? 'yups' : 'nope' } ],
      [ title      => diff => 1 ],
      [ original   => diff => 1 ],
      [ gtin       => serialize => sub { $_[0]||'[none]' } ],
      [ catalog    => serialize => sub { $_[0]||'[none]' } ],
      [ languages  => join => ', ', split => sub { map mt("_lang_$_"), @{$_[0]} } ],
      [ 'website' ],
      [ released   => htmlize   => sub { $self->{l10n}->datestr($_[0]) } ],
      [ minage     => serialize => sub { $self->{age_ratings}{$_[0]}[0] } ],
      [ notes      => diff => 1 ],
      [ platforms  => join => ', ', split => sub { map mt("_plat_$_"), @{$_[0]} } ],
      [ media      => join => ', ', split => sub {
        map {
          my $med = $self->{media}{$_->{medium}};
          $med->[1] ? sprintf('%d %s%s', $_->{qty}, $med->[0], $_->{qty}>1?'s':'') : $med->[0]
        } @{$_[0]};
      } ],
      [ resolution => serialize => sub { $self->{resolutions}[$_[0]][0] } ],
      [ voiced     => serialize => sub { mt '_voiced_'.$_[0] } ],
      [ ani_story  => serialize => sub { mt '_animated_'.$_[0] } ],
      [ ani_ero    => serialize => sub { mt '_animated_'.$_[0] } ],
      [ producers  => join => '<br />', split => sub {
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
    td class => 'key', mt '_relinfo_vnrel';
    td;
     for (@{$r->{vn}}) {
       a href => "/v$_->{vid}", title => $_->{original}||$_->{title}, shorten $_->{title}, 60;
       br if $_ != $r->{vn}[$#{$r->{vn}}];
     }
    end;
   end;

   Tr ++$i % 2 ? (class => 'odd') : ();
    td mt '_relinfo_title';
    td $r->{title};
   end;

   if($r->{original}) {
     Tr ++$i % 2 ? (class => 'odd') : ();
      td mt '_relinfo_original';
      td $r->{original};
     end;
   }

   Tr ++$i % 2 ? (class => 'odd') : ();
    td mt '_relinfo_type';
    td;
     cssicon "rt$r->{type}", mt "_rtype_$r->{type}";
     txt ' '.mt '_relinfo_type_format', mt("_rtype_$r->{type}"), $r->{patch}?1:0;
    end;
   end;

   Tr ++$i % 2 ? (class => 'odd') : ();
    td mt '_relinfo_lang';
    td;
     for (@{$r->{languages}}) {
       cssicon "lang $_", mt "_lang_$_";
       txt ' '.mt("_lang_$_");
       br if $_ ne $r->{languages}[$#{$r->{languages}}];
     }
    end;
   end;

   Tr ++$i % 2 ? (class => 'odd') : ();
    td mt '_relinfo_publication';
    td mt $r->{patch} ? '_relinfo_pub_patch' : '_relinfo_pub_nopatch', $r->{freeware}?0:1, $r->{doujin}?0:1;
   end;

   if(@{$r->{platforms}}) {
     Tr ++$i % 2 ? (class => 'odd') : ();
      td mt '_relinfo_platform', scalar @{$r->{platforms}};
      td;
       for(@{$r->{platforms}}) {
         cssicon $_, mt "_plat_$_";
         txt ' '.mt("_plat_$_");
         br if $_ ne $r->{platforms}[$#{$r->{platforms}}];
       }
      end;
     end;
   }

   if(@{$r->{media}}) {
     Tr ++$i % 2 ? (class => 'odd') : ();
      td mt '_relinfo_media', scalar @{$r->{media}};
      # TODO: TL the media
      td join ', ', map {
        my $med = $self->{media}{$_->{medium}};
        $med->[1] ? sprintf('%d %s%s', $_->{qty}, $med->[0], $_->{qty}>1?'s':'') : $med->[0]
      } @{$r->{media}};
     end;
   }

   if($r->{resolution}) {
     Tr ++$i % 2 ? (class => 'odd') : ();
      td mt '_relinfo_resolution';
      td $self->{resolutions}[$r->{resolution}][0];
     end;
   }

   if($r->{voiced}) {
     Tr ++$i % 2 ? (class => 'odd') : ();
      td mt '_relinfo_voiced';
      td mt '_voiced_'.$r->{voiced};
     end;
   }

   if($r->{ani_story} || $r->{ani_ero}) {
     Tr ++$i % 2 ? (class => 'odd') : ();
      td mt '_relinfo_ani';
      td join ', ',
        $r->{ani_story} ? mt('_relinfo_ani_story', mt '_animated_'.$r->{ani_story}):(),
        $r->{ani_ero}   ? mt('_relinfo_ani_ero',   mt '_animated_'.$r->{ani_ero}  ):();
     end;
   }

   Tr ++$i % 2 ? (class => 'odd') : ();
    td mt '_relinfo_released';
    td;
     lit $self->{l10n}->datestr($r->{released});
    end;
   end;

   if($r->{minage} >= 0) {
     Tr ++$i % 2 ? (class => 'odd') : ();
      td mt '_relinfo_minage';
      td $self->{age_ratings}{$r->{minage}}[0];
     end;
   }

   if(@{$r->{producers}}) {
     Tr ++$i % 2 ? (class => 'odd') : ();
      td mt '_relinfo_producer', scalar @{$r->{producers}};
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
      td mt '_relinfo_catalog';
      td $r->{catalog};
     end;
   }

   if($r->{website}) {
     Tr ++$i % 2 ? (class => 'odd') : ();
      td mt '_relinfo_links';
      td;
       a href => $r->{website}, rel => 'nofollow', mt '_relinfo_website';
      end;
     end;
   }

   if($self->authInfo->{id}) {
     my $rl = $self->dbVNListGet(uid => $self->authInfo->{id}, rid => $r->{id})->[0];
     Tr ++$i % 2 ? (class => 'odd') : ();
      td mt '_relinfo_user';
      td;
       Select id => 'listsel', name => 'listsel';
        option mt !$rl ? '_relinfo_user_notlist' :
          ('_relinfo_user_inlist', $self->{vn_rstat}[$rl->{rstat}], $self->{vn_vstat}[$rl->{vstat}]);
        optgroup label => mt '_relinfo_user_setr';
         option value => "r$_", $self->{vn_rstat}[$_]
           for (0..$#{$self->{vn_rstat}});
        end;
        optgroup label => mt '_relinfo_user_setv';
         option value => "v$_", $self->{vn_vstat}[$_]
           for (0..$#{$self->{vn_vstat}});
        end;
        option value => 'del', mt '_relinfo_user_del' if $rl;
       end;
      end;
     end;
   }

  end;
}


# rid = \d   -> edit/copy release
# rid = 'v'  -> add release to VN with id $rev
sub edit {
  my($self, $rid, $rev, $copy) = @_;

  my $vid = 0;
  $copy = $rev && $rev eq 'copy' || $copy && $copy eq 'copy';
  $rev = undef if defined $rev && $rev !~ /^\d+$/;
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
    (map { $_ => $r->{$_} } qw|type title original gtin catalog languages website released
      notes minage platforms patch resolution voiced freeware doujin ani_story ani_ero|),
    media     => join(',',   sort map "$_->{medium} $_->{qty}", @{$r->{media}}),
    producers => join('|||', map "$_->{id},$_->{name}", sort { $a->{id} <=> $b->{id} } @{$r->{producers}}),
  );
  $b4{vn} = join('|||', map "$_->{vid},$_->{title}", @$vn);
  my $frm;

  if($self->reqMethod eq 'POST') {
    $frm = $self->formValidate(
      { name => 'type',      enum => $self->{release_types} },
      { name => 'patch',     required => 0, default => 0 },
      { name => 'freeware',  required => 0, default => 0 },
      { name => 'doujin',    required => 0, default => 0 },
      { name => 'title',     maxlength => 250 },
      { name => 'original',  required => 0, default => '', maxlength => 250 },
      { name => 'gtin',      required => 0, default => '0',
        func => [ \&gtintype, 'Not a valid JAN/UPC/EAN code' ] },
      { name => 'catalog',   required => 0, default => '', maxlength => 50 },
      { name => 'languages', multi => 1, enum => $self->{languages} },
      { name => 'website',   required => 0, default => '', template => 'url' },
      { name => 'released',  required => 0, default => 0, template => 'int' },
      { name => 'minage' ,   required => 0, default => -1, enum => [ keys %{$self->{age_ratings}} ] },
      { name => 'notes',     required => 0, default => '', maxlength => 10240 },
      { name => 'platforms', required => 0, default => '', multi => 1, enum => $self->{platforms} },
      { name => 'media',     required => 0, default => '' },
      { name => 'resolution',required => 0, default => 0, enum => [ 0..$#{$self->{resolutions}} ] },
      { name => 'voiced',    required => 0, default => 0, enum => $self->{voiced} },
      { name => 'ani_story', required => 0, default => 0, enum => $self->{animated} },
      { name => 'ani_ero',   required => 0, default => 0, enum => $self->{animated} },
      { name => 'producers', required => 0, default => '' },
      { name => 'vn',        maxlength => 5000 },
      { name => 'editsum',   maxlength => 5000 },
    );

    my($media, $producers, $new_vn);
    if(!$frm->{_err}) {
      # de-serialize
      $media     = [ map [ split / / ], split /,/, $frm->{media} ];
      $producers = [ map { /^([0-9]+)/ ? $1 : () } split /\|\|\|/, $frm->{producers} ];
      $new_vn    = [ map { /^([0-9]+)/ ? $1 : () } split /\|\|\|/, $frm->{vn} ];
      $frm->{platforms} = [ grep $_, @{$frm->{platforms}} ];
      $frm->{$_} = $frm->{$_} ? 1 : 0 for (qw|patch freeware doujin|);

      # reset some fields when the patch flag is set
      $frm->{doujin} = $frm->{resolution} = $frm->{voiced} = $frm->{ani_story} = $frm->{ani_ero} = 0 if $frm->{patch};

      my $same = $rid &&
          (join(',', sort @{$b4{platforms}}) eq join(',', sort @{$frm->{platforms}})) &&
          (join(',', sort @$producers) eq join(',', sort map $_->{id}, @{$r->{producers}})) &&
          (join(',', sort @$new_vn) eq join(',', sort map $_->{vid}, @$vn)) &&
          (join(',', sort @{$b4{languages}}) eq join(',', sort @{$frm->{languages}})) &&
          !grep !/^(platforms|producers|vn|languages)$/ && $frm->{$_} ne $b4{$_}, keys %b4;
      return $self->resRedirect("/r$rid", 'post') if !$copy && $same;
      $frm->{_err} = [ 'nochanges' ] if $copy && $same;
    }

    if(!$frm->{_err}) {
      my %opts = (
        (map { $_ => $frm->{$_} } qw| type title original gtin catalog languages website released
          notes minage platforms resolution editsum patch voiced freeware doujin ani_story ani_ero|),
        vn        => $new_vn,
        producers => $producers,
        media     => $media,
      );

      $rev = 1;
      ($rev) = $self->dbReleaseEdit($rid, %opts) if !$copy && $rid;
      ($rid) = $self->dbReleaseAdd(%opts) if $copy || !$rid;

      $self->dbVNCache(@$new_vn, map $_->{vid}, @$vn);

      return $self->resRedirect("/r$rid.$rev", 'post');
    }
  }

  !defined $frm->{$_} && ($frm->{$_} = $b4{$_}) for keys %b4;
  $frm->{languages} = ['ja'] if !$rid && !defined $frm->{languages};
  $frm->{editsum} = sprintf 'Reverted to revision r%d.%d', $rid, $rev if !$copy && $rev && !defined $frm->{editsum};
  $frm->{editsum} = sprintf 'New release based on r%d.%d', $rid, $r->{rev} if $copy && !defined $frm->{editsum};
  $frm->{title} = $v->{title} if !defined $frm->{title} && !$r;
  $frm->{original} = $v->{original} if !defined $frm->{original} && !$r;

  my $title = mt $rid ? ($copy ? '_redit_title_copy' : '_redit_title_edit', $r->{title}) : ('_redit_title_add', $v->{title});
  $self->htmlHeader(title => $title, noindex => 1);
  $self->htmlMainTabs('r', $r, $copy ? 'copy' : 'edit') if $rid;
  $self->htmlMainTabs('v', $v, 'edit') if $vid;
  $self->htmlEditMessage('r', $r, $title, $copy);
  _form($self, $r, $v, $frm, $copy);
  $self->htmlFooter;
}


sub _form {
  my($self, $r, $v, $frm, $copy) = @_;

  $self->htmlForm({ frm => $frm, action => $r ? "/r$r->{id}/".($copy ? 'copy' : 'edit') : "/v$v->{id}/add", editsum => 1 },
  rel_geninfo => [ mt('_redit_form_geninfo'),
    [ select => short => 'type',      name => mt('_redit_form_type'),
      options => [ map [ $_, mt "_rtype_$_" ], @{$self->{release_types}} ] ],
    [ check  => short => 'patch',     name => mt('_redit_form_patch') ],
    [ check  => short => 'freeware',  name => mt('_redit_form_freeware') ],
    [ check  => short => 'doujin',    name => mt('_redit_form_doujin') ],
    [ input  => short => 'title',     name => mt('_redit_form_title'),    width => 300 ],
    [ input  => short => 'original',  name => mt('_redit_form_original'), width => 300 ],
    [ static => content => mt '_redit_form_original_note' ],
    [ select => short => 'languages', name => mt('_redit_form_languages'), multi => 1,
      options => [ map [ $_, "$_ (".mt("_lang_$_").')' ], sort @{$self->{languages}} ] ],
    [ input  => short => 'gtin',      name => mt('_redit_form_gtin') ],
    [ input  => short => 'catalog',   name => mt('_redit_form_catalog') ],
    [ input  => short => 'website',   name => mt('_redit_form_website') ],
    [ date   => short => 'released',  name => mt('_redit_form_released') ],
    [ static => content => mt('_redit_form_released_note') ],
    [ select => short => 'minage', name => mt('_redit_form_minage'),
      options => [ map [ $_, $self->{age_ratings}{$_}[0].($self->{age_ratings}{$_}[1]?" (e.g. $self->{age_ratings}{$_}[1])":'') ],
        sort { $a <=> $b } keys %{$self->{age_ratings}} ] ],
    [ textarea => short => 'notes', name => mt('_redit_form_notes').'<br /><b class="standout">'.mt('_inenglish').'</b>' ],
    [ static => content => mt('_redit_form_notes_note') ],
  ],

  rel_format => [ mt('_redit_form_format'),
    [ select => short => 'resolution', name => mt('_redit_form_resolution'), options => [
      map [ $_, @{$self->{resolutions}[$_]} ], 0..$#{$self->{resolutions}} ] ],
    [ select => short => 'voiced',     name => mt('_redit_form_voiced'), options => [
      map [ $_, mt '_voiced_'.$_ ], @{$self->{voiced}} ] ],
    [ select => short => 'ani_story',  name => mt('_redit_form_ani_story'), options => [
      map [ $_, mt '_animated_'.$_ ], @{$self->{animated}} ] ],
    [ select => short => 'ani_ero',  name => mt('_redit_form_ani_ero'), options => [
      map [ $_, $_ ? mt '_animated_'.$_ : mt('_redit_form_ani_ero_none') ], @{$self->{animated}} ] ],
    [ static => content => mt('_redit_form_ani_ero_note') ],
    [ hidden => short => 'media' ],
    [ static => nolabel => 1, content => sub {
      h2 mt '_redit_form_platforms';
      div class => 'platforms';
       for my $p (sort @{$self->{platforms}}) {
         span;
          input type => 'checkbox', name => 'platforms', value => $p, id => $p,
            $frm->{platforms} && grep($_ eq $p, @{$frm->{platforms}}) ? (checked => 'checked') : ();
          label for => $p;
           cssicon $p, mt "_plat_$p";
           txt ' '.mt("_plat_$p");
          end;
         end;
       }
      end;

      h2 mt '_redit_form_media';
      div id => 'media_div';
       Select;
        option value => $_, class => $self->{media}{$_}[1] ? 'qty' : 'noqty', $self->{media}{$_}[0]
          for (sort keys %{$self->{media}});
       end;
      end;
    }],
  ],

  rel_prod => [ mt('_redit_form_prod'),
    [ hidden => short => 'producers' ],
    [ static => nolabel => 1, content => sub {
      h2 mt('_redit_form_prod_sel');
      table; tbody id => 'producer_tbl'; end; end;
      h2 mt('_redit_form_prod_add');
      div;
       input id => 'producer_input', type => 'text', class => 'text';
       a id => 'producer_add', href => '#', 'add';
      end;
    }],
  ],

  rel_vn => [ mt('_redit_form_vn'),
    [ hidden => short => 'vn' ],
    [ static => nolabel => 1, content => sub {
      h2 mt('_redit_form_vn_sel');
      table; tbody id => 'vn_tbl'; end; end;
      h2 mt('_redit_form_vn_add');
      div;
       input id => 'vn_input', type => 'text', class => 'text';
       a href => '#', id => 'vn_add', 'add';
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
    { name => 'ln', required => 0, multi => 1, default => '', enum => $self->{languages} },
    { name => 'pl', required => 0, multi => 1, default => '', enum => $self->{platforms} },
    { name => 'me', required => 0, multi => 1, default => '', enum => [ keys %{$self->{media}} ] },
    { name => 'tp', required => 0, default => -1, enum => [ -1, @{$self->{release_types}} ] },
    { name => 'pa', required => 0, default => 0, enum => [ 0..2 ] },
    { name => 'fw', required => 0, default => 0, enum => [ 0..2 ] },
    { name => 'do', required => 0, default => 0, enum => [ 0..2 ] },
    { name => 'ma_m', required => 0, default => 0, enum => [ 0, 1 ] },
    { name => 'ma_a', required => 0, default => 0, enum => [ keys %{$self->{age_ratings}} ] },
    { name => 'mi', required => 0, default => 0, template => 'int' },
    { name => 'ma', required => 0, default => 99999999, template => 'int' },
    { name => 're', required => 0, multi => 1, default => 0, enum => [ 1..$#{$self->{resolutions}} ] },
  );
  return 404 if $f->{_err};

  my @filters = (
    $f->{mi} > 0 || $f->{ma} < 99990000 ? (date => [ $f->{mi}, $f->{ma} ]) : (),
    $f->{q} ? (search => $f->{q}) : (),
    $f->{pl}[0] ? (platforms => $f->{pl}) : (),
    $f->{ln}[0] ? (languages => $f->{ln}) : (),
    $f->{me}[0] ? (media => $f->{me}) : (),
    $f->{re}[0] ? (resolutions => $f->{re} ) : (),
    $f->{tp} >= 0 ? (type => $f->{tp}) : (),
    $f->{ma_a} || $f->{ma_m} ? (minage => [$f->{ma_m}, $f->{ma_a}]) : (),
    $f->{pa} ? (patch => $f->{pa}) : (),
    $f->{fw} ? (freeware => $f->{fw}) : (),
    $f->{do} ? (doujin => $f->{do}) : (),
  );
  my($list, $np) = !@filters ? ([], 0) : $self->dbReleaseGet(
    order => $f->{s}.($f->{o}eq'd'?' DESC':' ASC'),
    page => $f->{p},
    results => 50,
    what => 'platforms',
    @filters,
  );

  my $url = "/r?tp=$f->{tp};pa=$f->{pa};ma_m=$f->{ma_m};ma_a=$f->{ma_a};q=$f->{q};mi=$f->{mi};ma=$f->{ma}";
  $_&&($url .= ";ln=$_") for @{$f->{ln}};
  $_&&($url .= ";pl=$_") for @{$f->{pl}};
  $_&&($url .= ";re=$_") for @{$f->{re}};
  $_&&($url .= ";me=$_") for @{$f->{me}};

  $self->htmlHeader(title => mt('_rbrowse_title'));
  _filters($self, $f, !@filters || !@$list);
  $self->htmlBrowse(
    class    => 'relbrowse',
    items    => $list,
    options  => $f,
    nextpage => $np,
    pageurl  => "$url;s=$f->{s};o=$f->{o}",
    sorturl  => $url,
    header   => [
      [ mt('_rbrowse_col_released'), 'released' ],
      [ mt('_rbrowse_col_minage'),   'minage' ],
      [ '',         '' ],
      [ mt('_rbrowse_col_title'),    'title' ],
    ],
    row      => sub {
      my($s, $n, $l) = @_;
      Tr $n % 2 ? (class => 'odd') : ();
       td class => 'tc1';
        lit $self->{l10n}->datestr($l->{released});
       end;
       td class => 'tc2', $l->{minage} > -1 ? $self->{age_ratings}{$l->{minage}}[0] : '';
       td class => 'tc3';
        $_ ne 'oth' && cssicon $_, mt "_plat_$_" for (@{$l->{platforms}});
        cssicon "lang $_", mt "_lang_$_" for (@{$l->{languages}});
        cssicon "rt$l->{type}", mt "_rtype_$l->{type}";
       end;
       td class => 'tc4';
        a href => "/r$l->{id}", title => $l->{original}||$l->{title}, shorten $l->{title}, 90;
        b class => 'grayedout', ' (patch)' if $l->{patch};
       end;
      end;
    },
  ) if @$list;
  if(@filters && !@$list) {
    div class => 'mainbox';
     h1 mt '_rbrowse_noresults_title';
     div class => 'notice';
      p mt '_rbrowse_noresults_msg';
     end;
    end;
  }
  $self->htmlFooter;
}


sub _filters {
  my($self, $f, $shown) = @_;

  form method => 'get', action => '/r', 'accept-charset' => 'UTF-8';
  div class => 'mainbox';
   h1 mt '_rbrowse_title';

   $self->htmlSearchBox('r', $f->{q});

   a id => 'advselect', href => '#';
    lit '<i>'.($shown?'&#9662;':'&#9656;').'</i> '.mt('_rbrowse_filters');
   end;
   div id => 'advoptions', !$shown ? (class => 'hidden') : ();

    h2 mt '_rbrowse_filters';
    table class => 'formtable', style => 'margin-left: 0';
     Tr class => 'newfield';
      td class => 'label'; label for => 'ma_m', mt '_rbrowse_minage'; end;
      td class => 'field';
       Select id => 'ma_m', name => 'ma_m', style => 'width: 160px';
        option value => 0, $f->{ma_m} == 0 ? ('selected' => 'selected') : (), mt '_rbrowse_ge';
        option value => 1, $f->{ma_m} == 1 ? ('selected' => 'selected') : (), mt '_rbrowse_le';
       end;
       Select id => 'ma_a', name => 'ma_a', style => 'width: 80px; text-align: center';
        $_>=0 && option value => $_, $f->{ma_a} == $_ ? ('selected' => 'selected') : (), $self->{age_ratings}{$_}[0]
          for (sort { $a <=> $b } keys %{$self->{age_ratings}});
       end;
      end;
      td rowspan => 5, style => 'padding-left: 40px';
       label for => 're', mt '_rbrowse_resolution'; br;
       Select id => 're', name => 're', multiple => 'multiple', size => 8;
        my $l='';
        for my $i (1..$#{$self->{resolutions}}) {
          if($l ne $self->{resolutions}[$i][1]) {
            end if $l;
            $l = $self->{resolutions}[$i][1];
            optgroup label => $l;
          }
          option value => $i, scalar grep($i==$_, @{$f->{re}}) ? (selected => 'selected') : (), $self->{resolutions}[$i][0];
        }
        end if $l;
       end;
      end;
     end;
     $self->htmlFormPart($f, [ select => short => 'tp', name => mt('_rbrowse_type'),
       options => [ [-1, mt '_rbrowse_all'], map [ $_, mt "_rtype_$_" ], @{$self->{release_types}} ]]);
     $self->htmlFormPart($f, [ select => short => 'pa', name => mt('_rbrowse_patch'),
       options => [ [0, mt '_rbrowse_all' ], [1, mt '_rbrowse_patchonly'], [2, mt '_rbrowse_patchnone']]]);
     $self->htmlFormPart($f, [ select => short => 'fw', name => mt('_rbrowse_freeware'),
       options => [ [0, mt '_rbrowse_all' ], [1, mt '_rbrowse_freewareonly'], [2, mt '_rbrowse_freewarenone']]]);
     $self->htmlFormPart($f, [ select => short => 'do', name => mt('_rbrowse_doujin'),
       options => [ [0, mt '_rbrowse_all' ], [1, mt '_rbrowse_doujinonly'], [2, mt '_rbrowse_doujinnone']]]);
     $self->htmlFormPart($f, [ date => short => 'mi', name => mt '_rbrowse_dateafter' ]);
     $self->htmlFormPart($f, [ date => short => 'ma', name => mt '_rbrowse_datebefore' ]);
    end;

    h2;
     txt mt '_rbrowse_languages';
     b ' ('.mt('_rbrowse_boolor').')';
    end;
    for my $i (sort @{$self->dbLanguages}) {
      span;
       input type => 'checkbox', name => 'ln', value => $i, id => "lang_$i", grep($_ eq $i, @{$f->{ln}}) ? (checked => 'checked') : ();
       label for => "lang_$i";
        cssicon "lang $i", mt "_lang_$i";
        txt mt "_lang_$i";
       end;
      end;
    }

    h2;
     txt mt '_rbrowse_platforms';
     b ' ('.mt('_rbrowse_boolor').')';
    end;
    for my $i (sort @{$self->{platforms}}) {
      next if $i eq 'oth';
      span;
       input type => 'checkbox', name => 'pl', value => $i, id => "plat_$i", grep($_ eq $i, @{$f->{pl}}) ? (checked => 'checked') : ();
       label for => "plat_$i";
        cssicon $i, mt "_plat_$i";
        txt mt "_plat_$i";
       end;
      end;
    }

    h2;
     txt mt '_rbrowse_media';
     b ' ('.mt('_rbrowse_boolor').')';
    end;
    for my $i (sort keys %{$self->{media}}) {
      next if $i eq 'otc';
      span;
       input type => 'checkbox', name => 'me', value => $i, id => "med_$i", grep($_ eq $i, @{$f->{me}}) ? (checked => 'checked') : ();
       label for => "med_$i", $self->{media}{$i}[0];
      end;
    }

    div style => 'text-align: center; clear: left;';
     input type => 'submit', value => mt('_rbrowse_apply'), class => 'submit';
     input type => 'reset', value => mt('_rbrowse_clear'), class => 'submit', onclick => 'location.href="/r"';
    end;
   end;
  end;
  end;
}


1;

