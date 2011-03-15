
package VNDB::Handler::Chars;

use strict;
use warnings;
use TUWF ':html';
use VNDB::Func;


TUWF::register(
  qr{c([1-9]\d*)(?:\.([1-9]\d*))?} => \&page,
  qr{c(?:([1-9]\d*)(?:\.([1-9]\d*))?/edit|/new)}
    => \&edit,
);


sub page {
  my($self, $id, $rev) = @_;

  my $r = $self->dbCharGet(
    id => $id,
    what => 'extended traits vns'.($rev ? ' changes' : ''),
    $rev ? ( rev => $rev ) : ()
  )->[0];
  return $self->resNotFound if !$r->{id};

  $self->htmlHeader(title => $r->{name});
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
        return $_[0] > 0 ? sprintf '<img src="%s/ch/%02d/%d.jpg" />', $self->{url_static}, $_[0]%100, $_[0]
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
   h1 $r->{name};
   h2 class => 'alttitle', $r->{original} if $r->{original};
   _chartable($self, $r);
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
     _chartable($self, $_, 1, $_ != $inst->[0]) for @$inst;
    end;
  }

  $self->htmlFooter;
}


sub _chartable {
  my($self, $r, $link, $sep) = @_;

  div class => 'chardetails'.($sep ? ' charsep' : '');

   # image
   div class => 'charimg';
    if(!$r->{image}) {
      p mt '_charp_noimg';
    } elsif($r->{image} < 0) {
      p mt '_charp_imgproc';
    } else {
      img src => sprintf('%s/ch/%02d/%d.jpg', $self->{url_static}, $r->{image}%100, $r->{image}),
        alt => $r->{name} if $r->{image};
    }
   end 'div';

   # info table
   table;
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
    my $i = 0;
    if($r->{alias}) {
      $r->{alias} =~ s/\n/, /g;
      Tr ++$i % 2 ? (class => 'odd') : ();
       td class => 'key', mt '_charp_alias';
       td $r->{alias};
      end;
    }
    if($r->{height} || $r->{s_bust} || $r->{s_waist} || $r->{s_hip}) {
      Tr ++$i % 2 ? (class => 'odd') : ();
       td class => 'key', mt '_charp_meas';
       td join ', ',
         $r->{s_bust} || $r->{s_waist} || $r->{s_hip} ? mt('_charp_meas_bwh', $r->{s_bust}||'??', $r->{s_waist}||'??', $r->{s_hip}||'??') : (),
         $r->{height} ? mt('_charp_meas_h', $r->{height}) : ();
      end;
    }
    if($r->{weight}) {
      Tr ++$i % 2 ? (class => 'odd') : ();
       td class => 'key', mt '_charp_weight';
       td "$r->{weight} kg";
      end;
    }
    if($r->{b_month} && $r->{b_day}) {
      Tr ++$i % 2 ? (class => 'odd') : ();
       td class => 'key', mt '_charp_bday';
       td sprintf '%02d-%02d', $r->{b_month}, $r->{b_day};
      end;
    }

    # traits
    # TODO: handle spoilers and 'sexual' traits
    my %groups;
    my @groups;
    for (@{$r->{traits}}) {
      my $g = $_->{group}||$_->{tid};
      push @groups, $g if !$groups{$g};
      push @{$groups{ $g }}, $_
    }
    for my $g (@groups) {
      Tr ++$i % 2 ? (class => 'odd') : ();
       td class => 'key'; a href => '/i'.($groups{$g}[0]{group}||$groups{$g}[0]{tid}), $groups{$g}[0]{groupname} || $groups{$g}[0]{name}; end;
       td;
        for (@{$groups{$g}}) {
          txt ', ' if $_->{tid} != $groups{$g}[0]{tid};
          a href => "/i$_->{tid}", $_->{name};
        }
       end;
      end;
    }

    # vns
    # TODO: handle spoilers!
    if(@{$r->{vns}}) {
      my %vns;
      push @{$vns{$_->{vid}}}, $_ for(sort { !defined($a->{rid})?1:!defined($b->{rid})?-1:$a->{rtitle} cmp $b->{rtitle} } @{$r->{vns}});
      Tr ++$i % 2 ? (class => 'odd') : ();
       td class => 'key', mt '_charp_vns';
       td;
        my $first = 0;
        for my $g (sort { $vns{$a}[0]{vntitle} cmp $vns{$b}[0]{vntitle} } keys %vns) {
          br if $first++;
          my @r = @{$vns{$g}};
          # special case: all releases, no exceptions
          if(@r == 1 && !$r[0]{rid}) {
            txt mt("_charrole_$r[0]{role}").' - ';
            a href => "/v$r[0]{vid}", $r[0]{vntitle};
            next;
          }
          # otherwise, print VN title and list releases separately
          a href => "/v$r[0]{vid}", $r[0]{vntitle};
          for(@r) {
            br;
            b class => 'grayedout', '> ';
            txt mt("_charrole_$_->{role}").' - ';
            if($_->{rid}) {
              b class => 'grayedout', "r$_->{rid}:";
              a href => "/r$_->{rid}", $_->{rtitle};
            } else {
              txt mt '_charp_vns_other';
            }
          }
        }
       end;
      end;
    }

    # description
    if($r->{desc}) {
      Tr;
       td class => 'chardesc', colspan => 2;
        h2 mt '_charp_description';
        p;
         lit bb2html $r->{desc};
        end;
       end;
      end;
    }

   end 'table';
  end;
  clearfloat;
}



sub edit {
  my($self, $id, $rev) = @_;

  my $r = $id && $self->dbCharGet(id => $id, what => 'changes extended vns traits', $rev ? (rev => $rev) : ())->[0];
  return $self->resNotFound if $id && !$r->{id};
  $rev = undef if !$r || $r->{cid} == $r->{latest};

  return $self->htmlDenied if !$self->authCan('charedit')
    || $id && ($r->{locked} && !$self->authCan('lock') || $r->{hidden} && !$self->authCan('del'));

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
    $frm->{image} = _uploadimage($self, $r, $frm);

    # validate main character
    if(!$frm->{_err} && $frm->{main}) {
      my $m = $self->dbCharGet(id => $frm->{main}, what => 'extended')->[0];
      push @{$frm->{_err}}, 'mainchar' if !$m || $m->{id} == $r->{id} || $m->{main}
        || $self->dbCharGet(instance => $r->{id})->[0];
    }

    if(!$frm->{_err}) {
      # parse and normalize
      my @traits = sort { $a->[0] <=> $b->[0] } map /^(\d+)-(\d+)$/&&[$1,$2], split / /, $frm->{traits};
      my @vns = sort { $a->[0] <=> $b->[0] || $a->[1] <=> $b->[1] }  map [split /-/], split / /, $frm->{vns};
      $frm->{traits} = join(' ', map sprintf('%d-%d', @$_), @traits);
      $frm->{vns}    = join(' ', map sprintf('%d-%d-%d-%s', @$_), @vns);
      $frm->{ihid}   = $frm->{ihid} ?1:0;
      $frm->{ilock}  = $frm->{ilock}?1:0;
      $frm->{main_spoil} = 0 if !$frm->{main};

      # check for changes
      return $self->resRedirect("/c$id", 'post')
        if $id && !grep $frm->{$_} ne $b4{$_}, keys %b4;

      # modify for dbCharRevisionInsert
      ($frm->{b_month}, $frm->{b_day}) = delete($frm->{bday}) =~ /^(\d{2})-(\d{2})$/ ? ($1, $2) : (0, 0);
      $frm->{main} ||= undef;
      $frm->{traits} = \@traits;
      $_->[1]||=undef for (@vns);
      $frm->{vns} = \@vns;

      my $nrev = $self->dbItemEdit(c => $id ? $r->{cid} : undef, %$frm);

      # TEMPORARY SOLUTION! I'll investigate more efficient solutions and incremental updates whenever I have more data
      $self->dbExec('SELECT traits_chars_calc()');

      return $self->resRedirect("/c$nrev->{iid}.$nrev->{rev}", 'post');
    }
  }

  $frm->{$_} //= $b4{$_} for keys %b4;
  $frm->{editsum} //= sprintf 'Reverted to revision c%d.%d', $id, $rev if $rev;

  my $title = mt $r ? ('_chare_title_edit', $r->{name}) : '_chare_title_add';
  $self->htmlHeader(title => $title, noindex => 1);
  $self->htmlMainTabs('c', $r, 'edit') if $r;
  $self->htmlEditMessage('c', $r, $title);
  $self->htmlForm({ frm => $frm, action => $r ? "/c$id/edit" : '/c/new', editsum => 1, upload => 1 },
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
     img src => sprintf("%s/ch/%02d/%d.jpg", $self->{url_static}, $frm->{image}%100, $frm->{image}) if $frm->{image} && $frm->{image} > 0;
    end;

    div;
     h2 mt '_chare_image_id';
     input type => 'text', class => 'text', name => 'image', id => 'image', value => $frm->{image};
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
  my($self, $c, $frm) = @_;
  return $c ? $frm->{image} : 0 if $frm->{_err} || !$self->reqPost('img');

  # perform some elementary checks
  my $imgdata = $self->reqUploadRaw('img');
  $frm->{_err} = [ 'noimage' ] if $imgdata !~ /^(\xff\xd8|\x89\x50)/; # JPG or PNG headers
  $frm->{_err} = [ 'toolarge' ] if length($imgdata) > 1024*1024;
  return undef if $frm->{_err};

  # get image ID and save it, to be processed by Multi
  my $imgid = $self->dbCharImageId;
  my $fn = sprintf '%s/static/ch/%02d/%d.jpg', $VNDB::ROOT, $imgid%100, $imgid;
  $self->reqSaveUpload('img', $fn);
  chmod 0666, $fn;

  return -1*$imgid;
}


1;

