
package VNDB::Handler::VNEdit;

use strict;
use warnings;
use TUWF ':html', ':xml';
use VNDB::Func;


TUWF::register(
  qr{v(?:([1-9]\d*)(?:\.([1-9]\d*))?/edit|/new)}
    => \&edit,
  qr{xml/vn\.xml}          => \&vnxml,
  qr{xml/screenshots\.xml} => \&scrxml,
);


sub edit {
  my($self, $vid, $rev) = @_;

  my $v = $vid && $self->dbVNGet(id => $vid, what => 'extended screenshots relations anime changes', $rev ? (rev => $rev) : ())->[0];
  return $self->resNotFound if $vid && !$v->{id};
  $rev = undef if !$vid || $v->{cid} == $v->{latest};

  return $self->htmlDenied if !$self->authCan('edit')
    || $vid && ($v->{locked} && !$self->authCan('lock') || $v->{hidden} && !$self->authCan('del'));

  my $r = $v ? $self->dbReleaseGet(vid => $v->{id}) : [];

  my %b4 = !$vid ? () : (
    (map { $_ => $v->{$_} } qw|title original desc alias length l_wp l_encubed l_renai l_vnn img_nsfw ihid ilock|),
    anime => join(' ', sort { $a <=> $b } map $_->{id}, @{$v->{anime}}),
    vnrelations => join('|||', map $_->{relation}.','.$_->{id}.','.($_->{official}?1:0).','.$_->{title}, sort { $a->{id} <=> $b->{id} } @{$v->{relations}}),
    screenshots => join(' ', map sprintf('%d,%d,%d', $_->{id}, $_->{nsfw}?1:0, $_->{rid}), @{$v->{screenshots}}),
  );

  my $frm;
  if($self->reqMethod eq 'POST') {
    return if !$self->authCheckCode;
    $frm = $self->formValidate(
      { post => 'title',       maxlength => 250 },
      { post => 'original',    required => 0, maxlength => 250, default => '' },
      { post => 'alias',       required => 0, maxlength => 500, default => '' },
      { post => 'desc',        required => 0, default => '', maxlength => 10240 },
      { post => 'length',      required => 0, default => 0,  enum => $self->{vn_lengths} },
      { post => 'l_wp',        required => 0, default => '', maxlength => 150 },
      { post => 'l_encubed',   required => 0, default => '', maxlength => 100 },
      { post => 'l_renai',     required => 0, default => '', maxlength => 100 },
      { post => 'l_vnn',       required => 0, default => $b4{l_vnn}||0,  template => 'int' },
      { post => 'anime',       required => 0, default => '' },
      { post => 'previmage',   required => 0, default => 0,  template => 'int' },
      { post => 'img_nsfw',    required => 0, default => 0 },
      { post => 'vnrelations', required => 0, default => '', maxlength => 5000 },
      { post => 'screenshots', required => 0, default => '', maxlength => 1000 },
      { post => 'editsum',     required => 0, maxlength => 5000 },
      { post => 'ihid',        required  => 0 },
      { post => 'ilock',       required  => 0 },
    );

    push @{$frm->{_err}}, 'badeditsum' if !$frm->{editsum} || lc($frm->{editsum}) eq lc($frm->{desc});

    # handle image upload
    my $image = _uploadimage($self, $v, $frm);

    if(!$frm->{_err}) {
      # parse and re-sort fields that have multiple representations of the same information
      my $anime = { map +($_=>1), grep /^[0-9]+$/, split /[ ,]+/, $frm->{anime} };
      my $relations = [ map { /^([a-z]+),([0-9]+),([01]),(.+)$/ && (!$vid || $2 != $vid) ? [ $1, $2, $3, $4 ] : () } split /\|\|\|/, $frm->{vnrelations} ];
      my $screenshots = [ map /^[0-9]+,[01],[0-9]+$/ ? [split /,/] : (), split / +/, $frm->{screenshots} ];

      $frm->{ihid} = $frm->{ihid}?1:0;
      $frm->{ilock} = $frm->{ilock}?1:0;
      $relations = [] if $frm->{ihid};
      $frm->{anime} = join ' ', sort { $a <=> $b } keys %$anime;
      $frm->{vnrelations} = join '|||', map $_->[0].','.$_->[1].','.($_->[2]?1:0).','.$_->[3], sort { $a->[1] <=> $b->[1]} @{$relations};
      $frm->{img_nsfw} = $frm->{img_nsfw} ? 1 : 0;
      $frm->{screenshots} = join ' ', map sprintf('%d,%d,%d', $_->[0], $_->[1]?1:0, $_->[2]), sort { $a->[0] <=> $b->[0] } @$screenshots;

      # weed out duplicate aliases
      my %alias;
      $frm->{alias} = join "\n", grep {
        my $a = lc $_;
        $a && !$alias{$a}++ && $a ne lc($frm->{title}) && $a ne lc($frm->{original})
          && !grep $a eq lc($_->{title}) || $a eq lc($_->{original}), @$r;
      } map { s/^ +//g; s/ +$//g; $_ } split /\n/, $frm->{alias};

      # nothing changed? just redirect
      return $self->resRedirect("/v$vid", 'post')
        if $vid && !$self->reqParam('img') && $image == $v->{image}
          && !grep $frm->{$_} ne $b4{$_}, keys %b4;

      # perform the edit/add
      my $nrev = $self->dbItemEdit(v => $vid ? $v->{cid} : undef,
        (map { $_ => $frm->{$_} } qw|title original alias desc length l_wp l_encubed l_renai l_vnn editsum img_nsfw ihid ilock|),
        anime => [ keys %$anime ],
        relations => $relations,
        image => $image,
        screenshots => $screenshots,
      );

      # update reverse relations & relation graph
      if(!$vid && $#$relations >= 0 || $vid && $frm->{vnrelations} ne $b4{vnrelations}) {
        my %old = $vid ? (map +($_->{id} => [ $_->{relation}, $_->{official} ]), @{$v->{relations}}) : ();
        my %new = map +($_->[1] => [ $_->[0], $_->[2] ]), @$relations;
        _updreverse($self, \%old, \%new, $nrev->{iid}, $nrev->{rev});
      }

      return $self->resRedirect("/v$nrev->{iid}.$nrev->{rev}", 'post');
    }
  }

  !exists $frm->{$_} && ($frm->{$_} = $b4{$_}) for (keys %b4);
  $frm->{editsum} = sprintf 'Reverted to revision v%d.%d', $vid, $rev if $rev && !defined $frm->{editsum};

  my $title = $vid ? mt('_vnedit_title_edit', $v->{title}) : mt '_vnedit_title_add';
  $self->htmlHeader(title => $title, noindex => 1);
  $self->htmlMainTabs('v', $v, 'edit') if $vid;
  $self->htmlEditMessage('v', $v, $title);
  _form($self, $v, $frm, $r);
  $self->htmlFooter;
}


sub _uploadimage {
  my($self, $v, $frm) = @_;
  return $v ? $frm->{previmage} : 0 if $frm->{_err} || !$self->reqParam('img');

  # save to temporary location
  my $tmp = sprintf '%s/static/cv/00/tmp.%d.jpg', $VNDB::ROOT, $$*int(rand(1000)+1);
  $self->reqSaveUpload('img', $tmp);

  # perform some checks
  my $l;
  open(my $T, '<:raw:bytes', $tmp) || die $1;
  read $T, $l, 2;
  close($T);

  $frm->{_err} = [ 'noimage' ] if $l ne pack('H*', 'ffd8') && $l ne pack('H*', '8950');
  $frm->{_err} = [ 'toolarge' ] if -s $tmp > 512*1024;

  if($frm->{_err}) {
    unlink $tmp;
    return undef;
  }

  # get image ID and move it to the correct location
  my $imgid = $self->dbVNImageId;
  my $new = sprintf '%s/static/cv/%02d/%d.jpg', $VNDB::ROOT, $imgid%100, $imgid;
  rename $tmp, $new or die $!;
  chmod 0666, $new;

  return -1*$imgid;
}


sub _form {
  my($self, $v, $frm, $r) = @_;
  $self->htmlForm({ frm => $frm, action => $v ? "/v$v->{id}/edit" : '/v/new', editsum => 1, upload => 1 },
  vn_geninfo => [ mt('_vnedit_geninfo'),
    [ input    => short => 'title',     name => mt '_vnedit_frm_title' ],
    [ input    => short => 'original',  name => mt '_vnedit_original' ],
    [ static   => content => mt '_vnedit_original_msg' ],
    [ textarea => short => 'alias',     name => mt('_vnedit_alias'), rows => 4 ],
    [ static   => content => mt '_vnedit_alias_msg' ],
    [ textarea => short => 'desc',      name => mt('_vnedit_desc').'<br /><b class="standout">'.mt('_inenglish').'</b>', rows => 10 ],
    [ static   => content => mt '_vnedit_desc_msg' ],
    [ select   => short => 'length',    name => mt('_vnedit_length'), width => 450, options =>
      [ map [ $_ => mt '_vnlength_'.$_, 2 ], @{$self->{vn_lengths}} ] ],

    [ input    => short => 'l_wp',      name => mt('_vnedit_links'), pre => 'http://en.wikipedia.org/wiki/' ],
    [ input    => short => 'l_encubed', pre => 'http://novelnews.net/tag/', post => '/' ],
    [ input    => short => 'l_renai',   pre => 'http://renai.us/game/', post => '.shtml' ],

    [ input    => short => 'anime',     name => mt '_vnedit_anime' ],
    [ static   => content => mt '_vnedit_anime_msg' ],
  ],

  vn_img => [ mt('_vnedit_image'),
    [ hidden => short => 'previmage', value => $v ? $v->{image} : 0 ],
    [ static => nolabel => 1, content => sub {
      div class => 'img';
       p mt '_vnedit_image_none' if !$v || !$v->{image};
       p mt '_vnedit_image_processing' if $v && $v->{image} < 0;
       img src => sprintf("%s/cv/%02d/%d.jpg", $self->{url_static}, $v->{image}%100, $v->{image}), alt => $v->{title} if $v && $v->{image} > 0;
      end;
      div;

       h2 mt '_vnedit_image_upload';
       input type => 'file', class => 'text', name => 'img', id => 'img';
       p mt('_vnedit_image_upload_msg');
       br; br; br;

       h2 mt '_vnedit_image_nsfw';
       input type => 'checkbox', class => 'checkbox', id => 'img_nsfw', name => 'img_nsfw',
         $frm->{img_nsfw} ? (checked => 'checked') : ();
       label class => 'checkbox', for => 'img_nsfw', mt '_vnedit_image_nsfw_check';
       p mt '_vnedit_image_nsfw_msg';
      end;
    }],
  ],

  vn_rel => [ mt('_vnedit_rel'),
    [ hidden   => short => 'vnrelations' ],
    [ static   => nolabel => 1, content => sub {
      h2 mt '_vnedit_rel_sel';
      table;
       tbody id => 'relation_tbl';
        # to be filled using javascript
       end;
      end;

      h2 mt '_vnedit_rel_add';
      table;
       Tr id => 'relation_new';
        td class => 'tc_vn';
         input type => 'text', class => 'text';
        end;
        td class => 'tc_rel';
         txt mt('_vnedit_rel_isa').' ';
         input type => 'checkbox', id => 'official', checked => 'checked';
         label for => 'official', mt '_vnedit_rel_official';
         Select;
          option value => $_, mt "_vnrel_$_"
            for (sort { $self->{vn_relations}{$a}[0] <=> $self->{vn_relations}{$b}[0] } keys %{$self->{vn_relations}});
         end;
         txt ' '.mt '_vnedit_rel_of';
        end;
        td class => 'tc_title', $v ? $v->{title} : '';
        td class => 'tc_add';
         a href => '#', mt '_vnedit_rel_addbut';
        end;
       end;
      end;
    }],
  ],

  vn_scr => [ mt('_vnedit_scr'), !@$r ? (
    [ static => nolabel => 1, content => mt '_vnedit_scrnorel' ],
  ) : (
    [ hidden => short => 'screenshots' ],
    [ static => nolabel => 1, content => sub {
      div class => 'warning';
       lit mt '_vnedit_scrmsg';
      end;
      br;
      table;
       tbody id => 'scr_table', '';
      end;
      Select id => 'scr_rel', class => $self->{url_static};
       option value => $_->{id}, sprintf '[%s] %s (r%d)', join(',', @{$_->{languages}}), $_->{title}, $_->{id} for (@$r);
      end;
    }],
  )]

  );
}


# Update reverse relations and regenerate relation graph
# Arguments: %old. %new, vid, rev
#  %old,%new -> { vid2 => [ relation, official ], .. }
#    from the perspective of vid
#  rev is of the related edit
sub _updreverse {
  my($self, $old, $new, $vid, $rev) = @_;
  my %upd;

  # compare %old and %new
  for (keys %$old, keys %$new) {
    if(exists $$old{$_} and !exists $$new{$_}) {
      $upd{$_} = undef;
    } elsif((!exists $$old{$_} and exists $$new{$_}) || ($$old{$_}[0] ne $$new{$_}[0] || !$$old{$_}[1] != !$$new{$_}[1])) {
      $upd{$_} = [ $self->{vn_relations}{ $$new{$_}[0] }[1], $$new{$_}[1] ];
    }
  }
  return if !keys %upd;

  # edit all related VNs
  for my $i (keys %upd) {
    my $r = $self->dbVNGet(id => $i, what => 'relations')->[0];
    my @newrel = map $_->{id} != $vid ? [ $_->{relation}, $_->{id}, $_->{official} ] : (), @{$r->{relations}};
    push @newrel, [ $upd{$i}[0], $vid, $upd{$i}[1] ] if $upd{$i};
    $self->dbItemEdit(v => $r->{cid},
      relations => \@newrel,
      editsum => "Reverse relation update caused by revision v$vid.$rev",
      uid => 1, # Multi
    );
  }
}


# peforms a (simple) search and returns the results in XML format
sub vnxml {
  my $self = shift;

  my $q = $self->formValidate({ get => 'q', maxlength => 500 });
  return $self->resNotFound if $q->{_err};
  $q = $q->{q};

  my($list, $np) = $self->dbVNGet(
    $q =~ /^v([1-9]\d*)/ ? (id => $1) : (search => $q),
    results => 10,
    page => 1,
  );

  $self->resHeader('Content-type' => 'text/xml; charset=UTF-8');
  xml;
  tag 'vns', more => $np ? 'yes' : 'no', query => $q;
   for(@$list) {
     tag 'item', id => $_->{id}, $_->{title};
   }
  end;
}


# handles uploading screenshots and fetching information about them
sub scrxml {
  my $self = shift;
  return $self->htmlDenied if !$self->authCan('edit');
  $self->resHeader('Content-type' => 'text/xml; charset=UTF-8');

  # fetch information about screenshots
  if($self->reqMethod ne 'POST') {
    my $ids = $self->formValidate(
      { get => 'id', required => 1, template => 'int', multi => 1 }
    );
    return $self->resNotFound if $ids->{_err};
    my $r = $self->dbScreenshotGet($ids->{id});

    xml;
    tag 'screenshots';
     tag 'item', %$_, undef for (@$r);
    end;
    return;
  }

  # upload new screenshot
  my $num = $self->formValidate({get => 'upload', template => 'int'});
  return $self->resNotFound if $num->{_err};
  my $tmp = sprintf '%s/static/sf/00/tmp.%d.jpg', $VNDB::ROOT, $$*int(rand(1000)+1);
  $self->reqSaveUpload("scr_upl_file_$num->{upload}", $tmp);

  my $id = 0;
  $id = -2 if !-s $tmp;
  if(!$id) {
    my $l;
    open(my $T, '<:raw:bytes', $tmp) || die $1;
    read $T, $l, 2;
    close($T);
    $id = -1 if $l ne pack('H*', 'ffd8') && $l ne pack('H*', '8950');
  }

  if($id) {
    unlink $tmp;
  } else {
    $id = $self->dbScreenshotAdd;
    my $new = sprintf '%s/static/sf/%02d/%d.jpg', $VNDB::ROOT, $id%100, $id;
    rename $tmp, $new or die $!;
    chmod 0666, $new;
  }

  xml;
  # blank stylesheet because some browsers don't allow JS access otherwise
  lit qq|<?xml-stylesheet href="$self->{url_static}/f/blank.css" type="text/css" ?>|;
  tag 'image', id => $id, undef;
}


1;

