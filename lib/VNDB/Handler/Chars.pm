
package VNDB::Handler::Chars;

use strict;
use warnings;
use TUWF ':html', 'uri_escape';
use Exporter 'import';
use VNDB::Func;

our @EXPORT = ('charTable', 'charBrowseTable');

TUWF::register(
  qr{c([1-9]\d*)(?:\.([1-9]\d*))?} => \&page,
  qr{c(?:([1-9]\d*)(?:\.([1-9]\d*))?/(edit|copy)|/new)}
    => \&edit,
  qr{c/([a-z0]|all)} => \&list,
);


sub page {
  my($self, $id, $rev) = @_;

  my $r = $self->dbCharGet(
    id => $id,
    what => 'extended traits vns'.($rev ? ' changes' : ''),
    $rev ? ( rev => $rev ) : ()
  )->[0];
  return $self->resNotFound if !$r->{id};

  $self->htmlHeader(title => $r->{name}, noindex => $rev);
  $self->htmlMainTabs(c => $r);
  return if $self->htmlHiddenMessage('c', $r);

  if($rev) {
    my $prev = $rev && $rev > 1 && $self->dbCharGet(id => $id, rev => $rev-1, what => 'changes extended traits vns')->[0];
    $self->htmlRevision('c', $prev, $r,
      [ name      => diff => 1 ],
      [ original  => diff => 1 ],
      [ alias     => diff => qr/[ ,\n\.]/ ],
      [ desc      => diff => qr/[ ,\n\.]/ ],
      [ gender    => serialize => sub { mt "_gender_$_[0]" } ],
      [ b_month   => serialize => sub { $_[0]||mt '_revision_empty' } ],
      [ b_day     => serialize => sub { $_[0]||mt '_revision_empty' } ],
      [ s_bust    => serialize => sub { $_[0]||mt '_revision_empty' } ],
      [ s_waist   => serialize => sub { $_[0]||mt '_revision_empty' } ],
      [ s_hip     => serialize => sub { $_[0]||mt '_revision_empty' } ],
      [ height    => serialize => sub { $_[0]||mt '_revision_empty' } ],
      [ weight    => serialize => sub { $_[0]||mt '_revision_empty' } ],
      [ bloodt    => serialize => sub { mt "_bloodt_$_[0]" } ],
      [ main      => htmlize => sub { $_[0] ? sprintf '<a href="/c%d">c%d</a>', $_[0], $_[0] : mt '_revision_empty' } ],
      [ main_spoil=> serialize => sub { mt "_spoil_$_[0]" } ],
      [ image     => htmlize => sub {
        return $_[0] > 0 ? sprintf '<img src="%s" />', imgurl(ch => $_[0])
          : mt $_[0] < 0 ? '_chdiff_image_proc' : '_chdiff_image_none';
      }],
      [ traits    => join => '<br />', split => sub {
        map sprintf('%s<a href="/i%d">%s</a> (%s)', $_->{group}?qq|<b class="grayedout">$_->{groupname} / </b> |:'',
            $_->{tid}, $_->{name}, mt("_spoil_$_->{spoil}")), @{$_[0]}
      }],
      [ vns       => join => '<br />', split => sub {
        map sprintf('<a href="/v%d">v%d</a> %s %s (%s)', $_->{vid}, $_->{vid},
          $_->{rid}?sprintf('[<a href="/r%d">r%d</a>]', $_->{rid}, $_->{rid}):'',
          mt("_charrole_$_->{role}"), mt("_spoil_$_->{spoil}")), @{$_[0]};
      }],
    );
  }

  div class => 'mainbox';
   $self->htmlItemMessage('c', $r);
   p id => 'charspoil_sel';
    a href => '#', class => 'sel', mt '_vnpage_tags_spoil0'; # _vnpage!?
    a href => '#', mt '_vnpage_tags_spoil1';
    a href => '#', mt '_vnpage_tags_spoil2';
   end;
   h1 $r->{name};
   h2 class => 'alttitle', $r->{original} if $r->{original};
   $self->charTable($r);
  end;

  # TODO: ordering of these instances?
  my $inst = [];
  if(!$r->{main}) {
    $inst = $self->dbCharGet(instance => $r->{id}, what => 'extended traits vns');
  } else {
    $inst = $self->dbCharGet(instance => $r->{main}, notid => $r->{id}, what => 'extended traits vns');
    push @$inst, $self->dbCharGet(id => $r->{main}, what => 'extended traits vns')->[0];
  }
  if(@$inst) {
    div class => 'mainbox';
     h1 mt '_charp_instances';
     $self->charTable($_, 1, $_ != $inst->[0], 0, !$r->{main} ? $_->{main_spoil} : $_->{main_spoil} > $r->{main_spoil} ? $_->{main_spoil} : $r->{main_spoil}) for @$inst;
    end;
  }

  $self->htmlFooter;
}


# Also used from Handler::VNPage
sub charTable {
  my($self, $r, $link, $sep, $vn, $spoil) = @_;
  $spoil ||= 0;

  div class => 'chardetails '.charspoil($spoil).($sep ? ' charsep' : '');

   # image
   div class => 'charimg';
    if(!$r->{image}) {
      p mt '_charp_noimg';
    } elsif($r->{image} < 0) {
      p mt '_charp_imgproc';
    } else {
      img src => imgurl(ch => $r->{image}), alt => $r->{name};
    }
   end 'div';

   # info table
   table class => 'stripe';
    thead;
     Tr;
      td colspan => 2;
       if($link) {
         a href => "/c$r->{id}", style => 'margin-right: 10px; font-weight: bold', $r->{name};
       } else {
         b style => 'margin-right: 10px', $r->{name};
       }
       b class => 'grayedout', style => 'margin-right: 10px', $r->{original} if $r->{original};
       cssicon "gen $r->{gender}", mt "_gender_$r->{gender}" if $r->{gender} ne 'unknown';
       span mt "_bloodt_$r->{bloodt}" if $r->{bloodt} ne 'unknown';
      end;
     end;
    end;

    if($r->{alias}) {
      $r->{alias} =~ s/\n/, /g;
      Tr;
       td class => 'key', mt '_charp_alias';
       td $r->{alias};
      end;
    }
    if($r->{height} || $r->{s_bust} || $r->{s_waist} || $r->{s_hip}) {
      Tr;
       td class => 'key', mt '_charp_meas';
       td join ', ',
         $r->{height} ? mt('_charp_meas_h', $r->{height}) : (),
         $r->{weight} ? mt('_charp_meas_w', $r->{weight}) : (),
         $r->{s_bust} || $r->{s_waist} || $r->{s_hip} ? mt('_charp_meas_bwh', $r->{s_bust}||'??', $r->{s_waist}||'??', $r->{s_hip}||'??') : ();
      end;
    }
    if($r->{b_month} && $r->{b_day}) {
      Tr;
       td class => 'key', mt '_charp_bday';
       td mt '_charp_bday_fmt', $r->{b_day}, mt "_month_$r->{b_month}";
      end;
    }

    # traits
    # TODO: handle 'sexual' traits
    # TODO: fix striping of the table with hidden trait groups (due to spoilers)
    my %groups;
    my @groups;
    for (@{$r->{traits}}) {
      my $g = $_->{group}||$_->{tid};
      push @groups, $g if !$groups{$g};
      push @{$groups{ $g }}, $_
    }
    for my $g (@groups) {
      my $minspoil = 5;
      $minspoil = $minspoil > $_->{spoil} ? $_->{spoil} : $minspoil for(@{$groups{$g}});
      Tr class => charspoil($minspoil);
       td class => 'key'; a href => '/i'.($groups{$g}[0]{group}||$groups{$g}[0]{tid}), $groups{$g}[0]{groupname} || $groups{$g}[0]{name}; end;
       td;
        for (0..$#{$groups{$g}}) {
          my $t = $groups{$g}[$_];
          span class => charspoil $t->{spoil};
           a href => "/i$t->{tid}", $t->{name};
           # spoiler setting of the comma = max(current, min(@remaining_spoil))
           # since it is in the current <span>, which has 'current', only the second part is relevant if it is > current
           my $min_remaining = 5;
           $min_remaining = $min_remaining > $groups{$g}[$_]{spoil} ? $groups{$g}[$_]{spoil} : $min_remaining for($_+1..$#{$groups{$g}});
           span class => charspoil($min_remaining), ', ' if $min_remaining != 5 && $min_remaining > $t->{spoil};
           txt ', ' if $min_remaining != 5 && $min_remaining <= $t->{spoil};
          end;
        }
       end;
      end;
    }

    # vns
    if(@{$r->{vns}} && (!$vn || $vn && (@{$r->{vns}} > 1 || $r->{vns}[0]{rid}))) {
      my %vns;
      push @{$vns{$_->{vid}}}, $_ for(sort { !defined($a->{rid})?1:!defined($b->{rid})?-1:$a->{rtitle} cmp $b->{rtitle} } @{$r->{vns}});
      Tr;
       td class => 'key', mt $vn ? '_charp_releases' : '_charp_vns';
       td;
        my $first = 0;
        for my $g (sort { $vns{$a}[0]{vntitle} cmp $vns{$b}[0]{vntitle} } keys %vns) {
          br if $first++;
          my @r = @{$vns{$g}};
          # special case: all releases, no exceptions
          if(!$vn && @r == 1 && !$r[0]{rid}) {
            span class => charspoil $r[0]{spoil};
             txt mt("_charrole_$r[0]{role}").' - ';
             a href => "/v$r[0]{vid}/chars", $r[0]{vntitle};
            end;
            next;
          }
          # otherwise, print VN title and list releases separately
          my $minspoil = 5;
          $minspoil = $minspoil > $_->{spoil} ? $_->{spoil} : $minspoil for (@r);
          span class => charspoil $minspoil;
           a href => "/v$r[0]{vid}/chars", $r[0]{vntitle} if !$vn;
           for(@r) {
             span class => charspoil $_->{spoil};
              br if !$vn || $_ != $r[0];
              b class => 'grayedout', '> ';
              txt mt("_charrole_$_->{role}").' - ';
              if($_->{rid}) {
                b class => 'grayedout', "r$_->{rid}:";
                a href => "/r$_->{rid}", $_->{rtitle};
              } else {
                txt mt '_charp_vns_other';
              }
             end;
           }
          end;
        }
       end;
      end;
    }

    # description
    if($r->{desc}) {
      Tr class => 'nostripe';
       td class => 'chardesc', colspan => 2;
        h2 mt '_charp_description';
        p;
         lit bb2html $r->{desc}, 0, 1;
        end;
       end;
      end;
    }

   end 'table';
  end;
  clearfloat;
}



sub edit {
  my($self, $id, $rev, $copy) = @_;

  $copy = $rev && $rev eq 'copy' || $copy && $copy eq 'copy';
  $rev = undef if defined $rev && $rev !~ /^\d+$/;

  my $r = $id && $self->dbCharGet(id => $id, what => 'changes extended vns traits', $rev ? (rev => $rev) : ())->[0];
  return $self->resNotFound if $id && !$r->{id};
  $rev = undef if !$r || $r->{cid} == $r->{latest};

  return $self->htmlDenied if !$self->authCan('charedit')
    || $id && (($r->{locked} || $r->{hidden}) && !$self->authCan('dbmod'));

  my %b4 = !$id ? () : (
    (map +($_ => $r->{$_}), qw|name original alias desc image ihid ilock s_bust s_waist s_hip height weight bloodt gender main_spoil|),
    main => $r->{main}||0,
    bday => $r->{b_month} ? sprintf('%02d-%02d', $r->{b_month}, $r->{b_day}) : '',
    traits => join(' ', map sprintf('%d-%d', $_->{tid}, $_->{spoil}), sort { $a->{tid} <=> $b->{tid} } @{$r->{traits}}),
    vns => join(' ', map sprintf('%d-%d-%d-%s', $_->{vid}, $_->{rid}||0, $_->{spoil}, $_->{role}),
      sort { $a->{vid} <=> $b->{vid} || ($a->{rid}||0) <=> ($b->{rid}||0) } @{$r->{vns}}),
  );
  my $frm;

  if($self->reqMethod eq 'POST') {
    return if !$self->authCheckCode;
    $frm = $self->formValidate(
      { post => 'name',          maxlength => 200 },
      { post => 'original',      required  => 0, maxlength => 200,  default => '' },
      { post => 'alias',         required  => 0, maxlength => 500,  default => '' },
      { post => 'desc',          required  => 0, maxlength => 5000, default => '' },
      { post => 'gender',        required  => 0, default => 'unknown', enum => $self->{genders} },
      { post => 'image',         required  => 0, default => 0,  template => 'int' },
      { post => 'bday',          required  => 0, default => '', regex => [ qr/^\d{2}-\d{2}$/, mt('_chare_form_bday_err') ] },
      { post => 's_bust',        required  => 0, default => 0, template => 'int' },
      { post => 's_waist',       required  => 0, default => 0, template => 'int' },
      { post => 's_hip',         required  => 0, default => 0, template => 'int' },
      { post => 'height',        required  => 0, default => 0, template => 'int' },
      { post => 'weight',        required  => 0, default => 0, template => 'int' },
      { post => 'bloodt',        required  => 0, default => 'unknown', enum => $self->{blood_types} },
      { post => 'main',          required  => 0, default => 0, template => 'int' },
      { post => 'main_spoil',    required  => 0, default => 0, enum => [ 0..2 ] },
      { post => 'traits',        required  => 0, default => '', regex => [ qr/^(?:[1-9]\d*-[0-2])(?: +[1-9]\d*-[0-2])*$/, 'Incorrect trait format.' ] },
      { post => 'vns',           required  => 0, default => '', regex => [ qr/^(?:[1-9]\d*-\d+-[0-2]-[a-z]+)(?: +[1-9]\d*-\d+-[0-2]-[a-z]+)*$/, 'Incorrect VN format.' ] },
      { post => 'editsum',       required  => 0, maxlength => 5000 },
      { post => 'ihid',          required  => 0 },
      { post => 'ilock',         required  => 0 },
    );
    push @{$frm->{_err}}, 'badeditsum' if !$frm->{editsum} || lc($frm->{editsum}) eq lc($frm->{desc});

    # handle image upload
    $frm->{image} = _uploadimage($self, $frm);

    # validate main character
    if(!$frm->{_err} && $frm->{main}) {
      my $m = $self->dbCharGet(id => $frm->{main}, what => 'extended')->[0];
      push @{$frm->{_err}}, 'mainchar' if !$m || $m->{main} || $r && !$copy &&
        ($m->{id} == $r->{id} || $self->dbCharGet(instance => $r->{id})->[0]);
    }

    my(@traits, @vns);
    if(!$frm->{_err}) {
      # parse and normalize
      @traits = sort { $a->[0] <=> $b->[0] } map /^(\d+)-(\d+)$/&&[$1,$2], split / /, $frm->{traits};
      @vns = sort { $a->[0] <=> $b->[0] || $a->[1] <=> $b->[1] }  map [split /-/], split / /, $frm->{vns};
      $frm->{traits} = join(' ', map sprintf('%d-%d', @$_), @traits);
      $frm->{vns}    = join(' ', map sprintf('%d-%d-%d-%s', @$_), @vns);
      $frm->{ihid}   = $frm->{ihid} ?1:0;
      $frm->{ilock}  = $frm->{ilock}?1:0;
      $frm->{main_spoil} = 0 if !$frm->{main};

      # check for changes
      my $same = $id && !grep $frm->{$_} ne $b4{$_}, keys %b4;
      return $self->resRedirect("/c$id", 'post') if !$copy && $same;
      $frm->{_err} = ['nochanges'] if $copy && $same;
    }

    if(!$frm->{_err}) {
      # modify for dbCharRevisionInsert
      ($frm->{b_month}, $frm->{b_day}) = delete($frm->{bday}) =~ /^(\d{2})-(\d{2})$/ ? ($1, $2) : (0, 0);
      $frm->{main} ||= undef;
      $frm->{traits} = \@traits;
      $_->[1]||=undef for (@vns);
      $frm->{vns} = \@vns;

      my $nrev = $self->dbItemEdit(c => !$copy && $id ? $r->{cid} : undef, %$frm);
      return $self->resRedirect("/c$nrev->{iid}.$nrev->{rev}", 'post');
    }
  }

  if(!$id) {
    my $vid = $self->formValidate({ get => 'vid', required => 1, template => 'int'});
    $frm->{vns} //= "$vid->{vid}-0-0-primary" if !$vid->{_err};
  }
  $frm->{$_} //= $b4{$_} for keys %b4;
  $frm->{editsum} //= sprintf 'Reverted to revision c%d.%d', $id, $rev if !$copy && $rev;
  $frm->{editsum} = sprintf 'New character based on c%d.%d', $id, $r->{rev} if $copy;

  my $title = mt $r ? ($copy ? '_chare_title_copy' : '_chare_title_edit', $r->{name}) : '_chare_title_add';
  $self->htmlHeader(title => $title, noindex => 1);
  $self->htmlMainTabs('c', $r, $copy ? 'copy' : 'edit') if $r;
  $self->htmlEditMessage('c', $r, $title, $copy);
  $self->htmlForm({ frm => $frm, action => $r ? "/c$id/".($copy ? 'copy' : 'edit') : '/c/new', editsum => 1, upload => 1 },
  chare_geninfo => [ mt('_chare_form_generalinfo'),
    [ input  => name => mt('_chare_form_name'), short => 'name' ],
    [ input  => name => mt('_chare_form_original'), short => 'original' ],
    [ static => content => mt('_chare_form_original_note') ],
    [ text   => name => mt('_chare_form_alias'), short => 'alias', rows => 3 ],
    [ static => content => mt('_chare_form_alias_note') ],
    [ text   => name => mt('_chare_form_desc').'<br /><b class="standout">'.mt('_inenglish').'</b>', short => 'desc', rows => 6 ],
    [ select => name => mt('_chare_form_gender'),short => 'gender', options => [
       map [ $_, mt("_gender_$_") ], @{$self->{genders}} ] ],
    [ input  => name => mt('_chare_form_bday'),  short => 'bday',   width => 100, post => ' '.mt('_chare_form_bday_fmt')  ],
    [ input  => name => mt('_chare_form_bust'),  short => 's_bust', width => 50, post => ' cm' ],
    [ input  => name => mt('_chare_form_waist'), short => 's_waist',width => 50, post => ' cm' ],
    [ input  => name => mt('_chare_form_hip'),   short => 's_hip',  width => 50, post => ' cm' ],
    [ input  => name => mt('_chare_form_height'),short => 'height', width => 50, post => ' cm' ],
    [ input  => name => mt('_chare_form_weight'),short => 'weight', width => 50, post => ' kg' ],
    [ select => name => mt('_chare_form_bloodt'),short => 'bloodt', options => [
       map [ $_, mt("_bloodt_$_") ], @{$self->{blood_types}} ] ],
    [ static => content => '<br />' ],
    [ input  => name => mt('_chare_form_main'),  short => 'main', width => 50, post => ' '.mt('_chare_form_main_note') ],
    [ select => name => mt('_chare_form_main_spoil'), short => 'main_spoil', options => [
       map [$_, mt("_spoil_$_")], 0..2 ] ],
  ],

  chare_img => [ mt('_chare_image'), [ static => nolabel => 1, content => sub {
    div class => 'img';
     p mt '_chare_image_none' if !$frm->{image};
     p mt '_chare_image_processing' if $frm->{image} && $frm->{image} < 0;
     img src => imgurl(ch => $frm->{image}) if $frm->{image} && $frm->{image} > 0;
    end;

    div;
     h2 mt '_chare_image_id';
     input type => 'text', class => 'text', name => 'image', id => 'image', value => $frm->{image}||'';
     p mt '_chare_image_id_msg';
     br; br;

     h2 mt '_chare_image_upload';
     input type => 'file', class => 'text', name => 'img', id => 'img';
     p mt('_chare_image_upload_msg');
    end;
  }]],

  chare_traits => [ mt('_chare_traits'),
    [ hidden => short => 'traits' ],
    [ static => nolabel => 1, content => sub {
      h2 mt '_chare_traits_sel';
      table; tbody id => 'traits_tbl';
       Tr id => 'traits_loading'; td colspan => '3', mt('_js_loading'); end;
      end; end;
      h2 mt '_chare_traits_add';
      table; Tr;
       td class => 'tc_name'; input id => 'trait_input', type => 'text', class => 'text'; end;
       td colspan => 2, '';
      end; end 'table';
    }],
  ],

  chare_vns => [ mt('_chare_vns'),
    [ hidden => short => 'vns' ],
    [ static => nolabel => 1, content => sub {
      h2 mt '_chare_vns_sel';
      table; tbody id => 'vns_tbl';
       Tr id => 'vns_loading'; td colspan => '4', mt('_js_loading'); end;
      end; end;
      h2 mt '_chare_vns_add';
      table; Tr;
       td class => 'tc_vnadd'; input id => 'vns_input', type => 'text', class => 'text'; end;
       td colspan => 3, '';
      end; end;
    }],
  ]);
  $self->htmlFooter;
}


sub _uploadimage {
  my($self, $frm) = @_;

  if($frm->{_err} || !$self->reqPost('img')) {
    return 0 if !$frm->{image};
    push @{$frm->{_err}}, 'invalidimgid' if !-s imgpath(ch => $frm->{image});
    return $frm->{image};
  }

  # perform some elementary checks
  my $imgdata = $self->reqUploadRaw('img');
  $frm->{_err} = [ 'noimage' ] if $imgdata !~ /^(\xff\xd8|\x89\x50)/; # JPG or PNG headers
  $frm->{_err} = [ 'toolarge' ] if length($imgdata) > 1024*1024;
  return undef if $frm->{_err};

  # get image ID and save it, to be processed by Multi
  my $imgid = $self->dbCharImageId;
  my $fn = imgpath(ch => $imgid);
  $self->reqSaveUpload('img', $fn);
  chmod 0666, $fn;

  return -1*$imgid;
}


sub list {
  my($self, $fch) = @_;

  my $f = $self->formValidate(
    { get => 'p',   required => 0, default => 1, template => 'int' },
    { get => 'q',   required => 0, default => '' },
    { get => 'fil', required => 0, default => '' },
  );
  return $self->resNotFound if $f->{_err};

  my($list, $np) = $self->filFetchDB(char => $f->{fil}, {}, {
    $fch ne 'all' ? ( char => $fch ) : (),
    $f->{q} ? ( search => $f->{q} ) : (),
    results => 50,
    page => $f->{p},
    what => 'vns',
  });

  $self->htmlHeader(title => mt '_charb_title');

  my $quri = uri_escape($f->{q});
  form action => '/c/all', 'accept-charset' => 'UTF-8', method => 'get';
  div class => 'mainbox';
   h1 mt '_charb_title';
   $self->htmlSearchBox('c', $f->{q});
   p class => 'browseopts';
    for ('all', 'a'..'z', 0) {
      a href => "/c/$_?q=$quri", $_ eq $fch ? (class => 'optselected') : (), $_ eq 'all' ? mt('_char_all') : $_ ? uc $_ : '#';
    }
   end;

   a id => 'filselect', href => '#c';
    lit '<i>&#9656;</i> '.mt('_js_fil_filters').'<i></i>';
   end;
   input type => 'hidden', class => 'hidden', name => 'fil', id => 'fil', value => $f->{fil};
  end;
  end 'form';

  if(!@$list) {
    div class => 'mainbox';
     h1 mt '_charb_noresults';
     p mt '_charb_noresults_msg';
    end;
  }

  @$list && $self->charBrowseTable($list, $np, $f, "/c/$fch?q=$quri");

  $self->htmlFooter;
}


# Also used on Handler::Traits
sub charBrowseTable {
  my($self, $list, $np, $f, $uri) = @_;

  $self->htmlBrowse(
    class    => 'charb',
    items    => $list,
    options  => $f,
    nextpage => $np,
    pageurl  => $uri,
    sorturl  => $uri,
    header   => [ [ '' ], [ '' ] ],
    row      => sub {
      my($s, $n, $l) = @_;
      Tr;
       td class => 'tc1';
        cssicon "gen $l->{gender}", mt "_gender_$l->{gender}" if $l->{gender} ne 'unknown';
       end;
       td class => 'tc2';
        a href => "/c$l->{id}", title => $l->{original}||$l->{name}, shorten $l->{name}, 50;
        b class => 'grayedout';
         my $i = 1;
         my %vns;
         for (@{$l->{vns}}) {
           next if $_->{spoil} || $vns{$_->{vid}}++;
           last if $i++ > 4;
           txt ', ' if $i > 2;
           a href => "/v$_->{vid}/chars", title => $_->{vntitle}, shorten $_->{vntitle}, 30;
         }
        end;
       end;
      end;
    }
  )
}


1;

