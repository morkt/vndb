
package VNDB::Handler::VNEdit;

use strict;
use warnings;
use YAWF ':html', ':xml';


YAWF::register(
  qr{v(?:([1-9]\d*)(?:\.([1-9]\d*))?/edit|/new)}
    => \&edit,
  qr{xml/vn\.xml}   => \&vnxml,
);


sub edit {
  my($self, $vid, $rev) = @_;

  my $v = $vid && $self->dbVNGet(id => $vid, what => 'extended screenshots relations anime categories changes', $rev ? (rev => $rev) : ())->[0];
  return 404 if $vid && !$v->{id};
  $rev = undef if $v->{cid} == $v->{latest};

  return $self->htmlDenied if !$self->authCan('edit')
    || $vid && ($v->{locked} && !$self->authCan('lock') || $v->{hidden} && !$self->authCan('del'));

  my %b4 = !$vid ? () : (
    (map { $_ => $v->{$_} } qw|title original desc alias length l_wp l_encubed l_renai l_vnn img_nsfw|),
    anime => join(' ', sort { $a <=> $b } map $_->{id}, @{$v->{anime}}),
    categories => join(',', map $_->[0].$_->[1], sort { $a->[0] cmp $b->[0] } @{$v->{categories}}),
    relations => join('|||', map $_->{relation}.','.$_->{id}.','.$_->{title}, sort { $a->{id} <=> $b->{id} } @{$v->{relations}}),
    screenshots => join(' ', map sprintf('%d,%d,%d', $_->{id}, $_->{nsfw}?1:0, $_->{rid}), @{$v->{screenshots}}),
  );

  my $frm;
  if($self->reqMethod eq 'POST') {
    $frm = $self->formValidate(
      { name => 'title',       maxlength => 250 },
      { name => 'original',    required => 0, maxlength => 250, default => '' },
      { name => 'alias',       required => 0, maxlength => 500, default => '' },
      { name => 'desc',        maxlength => 10240 },
      { name => 'length',      required => 0, default => 0,  enum => [ 0..$#{$self->{vn_lengths}} ] },
      { name => 'l_wp',        required => 0, default => '', maxlength => 150 },
      { name => 'l_encubed',   required => 0, default => '', maxlength => 100 },
      { name => 'l_renai',     required => 0, default => '', maxlength => 100 },
      { name => 'l_vnn',       required => 0, default => 0,  template => 'int' },
      { name => 'anime',       required => 0, default => '' },
      { name => 'categories',  required => 0, default => '', maxlength => 1000 },
      { name => 'img_nsfw',    required => 0, default => 0 },
      { name => 'relations',   required => 0, default => '', maxlength => 5000 },
      { name => 'screenshots', required => 0, default => '', maxlength => 1000 },
      { name => 'editsum',     maxlength => 5000 },
    );

    # handle image upload
    my $image = _uploadimage($self, $v, $frm);

    if(!$frm->{_err}) {
      # parse and re-sort fields that have multiple representations of the same information
      my $anime = [ grep /^[0-9]+$/, split /[ ,]+/, $frm->{anime} ];
      my $categories = [ map { [ substr($_,0,3), substr($_,3,1) ] } split /,/, $frm->{categories} ];
      my $relations = [ map { /^([0-9]+),([0-9]+),(.+)$/ && $2 != $vid ? [ $1, $2, $3 ] : () } split /\|\|\|/, $frm->{relations} ];
      my $screenshots = [ map /^[0-9]+,[01],[0-9]+$/ ? [split /,/] : (), split / +/, $frm->{screenshots} ];

      $frm->{anime} = join ' ', sort { $a <=> $b } @$anime;
      $frm->{relations} = join '|||', map $_->[0].','.$_->[1].','.$_->[2], sort { $a->[1] <=> $b->[1]} @{$relations};
      $frm->{img_nsfw} = $frm->{img_nsfw} ? 1 : 0;
      $frm->{screenshots} = join ' ', map sprintf('%d,%d,%d', $_->[0], $_->[1]?1:0, $_->[2]), sort { $a->[0] <=> $b->[0] } @$screenshots;

      # nothing changed? just redirect
      return $self->resRedirect("/v$vid", 'post')
        if $vid && !$self->reqUploadFileName('img') && !grep $frm->{$_} ne $b4{$_}, keys %b4;

      # execute the edit/add
      my %args = (
        (map { $_ => $frm->{$_} } qw|title original alias desc length l_wp l_encubed l_renai l_vnn editsum img_nsfw|),
        anime => $anime,
        categories => $categories,
        relations => $relations,
        image => $image,
        screenshots => $screenshots,
      );

      my($nvid, $nrev, $cid) = ($vid, $rev);
      ($nrev, $cid) = $self->dbVNEdit($vid, %args) if $vid;
      ($nvid, $cid) = $self->dbVNAdd(%args) if !$vid;

      # update reverse relations & relation graph
      if(!$vid && $#$relations >= 0 || $vid && $frm->{relations} ne $b4{relations}) {
        my %old = $vid ? (map { $_->{id} => $_->{relation} } @{$v->{relations}}) : ();
        my %new = map { $_->[1] => $_->[0] } @$relations;
        _updreverse($self, \%old, \%new, $nvid, $cid, $nrev);
      } elsif($vid && @$relations && $frm->{title} ne $b4{title}) {
        $self->multiCmd("relgraph $vid");
      }

      $self->multiCmd("ircnotify v$nvid.$nrev");
      $self->multiCmd('anime') if $vid && $frm->{anime} ne $b4{anime} || !$vid && $frm->{anime};

      return $self->resRedirect("/v$nvid.$nrev", 'post');
    }
  }

  !exists $frm->{$_} && ($frm->{$_} = $b4{$_}) for (keys %b4);
  $frm->{editsum} = sprintf 'Reverted to revision v%d.%d', $vid, $rev if $rev && !defined $frm->{editsum};

  $self->htmlHeader(js => 'forms', title => $vid ? "Edit $v->{title}" : 'Add a new visual novel');
  $self->htmlMainTabs('v', $v, 'edit') if $vid;
  $self->htmlEditMessage('v', $v);
  _form($self, $v, $frm);
  $self->htmlFooter;
}


sub _uploadimage {
  my($self, $v, $frm) = @_;
  return $v ? $v->{image} : 0 if $frm->{_err} || !$self->reqUploadFileName('img');

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

  # store the file and let multi handle it
  my $imgid = $self->dbVNImageId;
  my $new = sprintf '%s/static/cv/%02d/%d.jpg', $VNDB::ROOT, $imgid%100, $imgid;
  rename $tmp, $new or die $!;
  chmod 0666, $new;
  $self->multiCmd("coverimage $imgid");

  return -1*$imgid;
}


sub _form {
  my($self, $v, $frm) = @_;
  $self->htmlForm({ frm => $frm, action => $v ? "/v$v->{id}/edit" : '/v/new', editsum => 1, upload => 1 },
  'General info' => [
    [ input    => short => 'title',     name => 'Title (romaji)' ],
    [ input    => short => 'original',  name => 'Original title' ],
    [ static   => content => 'The original title of this visual novel, leave blank if it already is in the Latin alphabet.' ],
    [ textarea => short => 'alias',     name => 'Aliases', rows => 4 ],
    [ static   => content => q|
        Comma seperated list of alternative titles or abbreviations. Can include both official
        (japanese/english) titles and unofficial titles used around net.<br />
        <b>Titles that are listed in the releases do not have to be added here.</b>
      |],
    [ textarea => short => 'desc',      name => 'Description', rows => 10 ],
    [ static   => content => q|
        Short description of the main story. Please do not include spoilers, and don't forget to list
        the source in case you didn't write the description yourself. (formatting codes are allowed)
      |],
    [ select   => short => 'length',    name => 'Length', width => 300, options =>
      [ map [ $_ => $self->{vn_lengths}[$_][0].($_ ? " ($self->{vn_lengths}[$_][2])" : '') ], 0..$#{$self->{vn_lengths}} ] ],

    [ input    => short => 'l_wp',      name => 'External links', pre => 'http://en.wikipedia.org/wiki/' ],
    [ input    => short => 'l_encubed', pre => 'http://novelnews.net/tag/', post => '/' ],
    [ input    => short => 'l_renai',   pre => 'http://renai.us/game/', post => '.shtml' ],
    [ input    => short => 'l_vnn',     pre => 'http://visual-novels.net/vn/index.php?option=com_content&amp;task=view&amp;id=', width => 40 ],
    
    [ input    => short => 'anime',     name => 'Anime' ],
    [ static   => content => q|
        Whitespace seperated list of <a href="http://anidb.net/">AniDB</a> anime IDs.
        E.g. "1015 3348" will add <a href="http://anidb.net/a1015">Shingetsutan Tsukihime</a>
        and <a href="http://anidb.net/a3348">Fate/stay night</a> as related anime.<br />
        <b>Note:</b> It can take a few minutes for the anime titles to appear on the VN page.
      |],
  ],

  'Categories' => [
    [ hidden   => short => 'categories' ],
    [ static   => nolabel => 1, content => sub {
      lit 'Please read the <a href="/d1">category descriptions</a> before modifying categories!<br /><br />';
      ul;
       for my $c (qw| e g t p h l s |) {
         $c !~ /[thl]/ ? li : br;
          txt $self->{categories}{$c}[0];
          a href => "/d1#$self->{categories}{$c}[2]", class => 'help', '?';
          ul;
           for (sort keys %{$self->{categories}{$c}[1]}) {
             li;
              a href => "#", id => "cat_$c$_";
               b id => "b_$c$_", '-';
               txt ' '.$self->{categories}{$c}[1]{$_};
              end;
             end;
           }
          end;
         end if $c !~ /[gph]/;
       }
      end;
    }],
  ],

  'Image' => [
    [ static => nolabel => 1, content => sub {
      div class => 'img';
       p 'No image uploaded yet' if !$v->{image};
       p '[processing image, please return in a few minutes]' if $v->{image} < 0;
       img src => sprintf("%s/cv/%02d/%d.jpg", $self->{url_static}, $v->{image}%100, $v->{image}), alt => $v->{title} if $v->{image} > 0;
      end;
      div;

       h2 'Upload new image';
       input type => 'file', class => 'text', name => 'img', id => 'img';
       p 'Preferably the cover of the CD/DVD/package. Image must be in JPEG or PNG format'
        ." and at most 500kB. Images larger than 256x400 will automatically be resized.\n\n\n";

       h2 'NSFW';
       input type => 'checkbox', class => 'checkbox', id => 'img_nsfw', name => 'img_nsfw',
         $frm->{img_nsfw} ? (checked => 'checked') : ();
       label class => 'checkbox', for => 'img_nsfw', "Not Safe For Work.\n";
       p 'Please check this option if the image contains nudity, gore, or is otherwise not safe in a work-friendly environment.';
      end;
    }],
  ],

  'Relations' => [
    [ hidden   => short => 'relations' ],
    [ static   => nolabel => 1, content => sub {
      h2 'Selected relations';
      table;
       tbody id => 'relation_tbl';
        # to be filled using javascript
       end;
      end;

      h2 'Add relation';
      table;
       Tr id => 'relation_new';
        td class => 'tc1';
         input type => 'text', class => 'text';
        end;
        td class => 'tc2';
         txt ' is a ';
         Select;
          option value => $_, $self->{vn_relations}[$_][0] for (0..$#{$self->{vn_relations}});
         end;
         txt ' of';
        end;
        td class => 'tc3', $v->{title};
        td class => 'tc4';
         a href => '#', 'add';
        end;
       end;
      end;
    }],
  ],

  'Screenshots' => [
    [ input  => nolabel => 1, short => 'screenshots', width => 700 ],
  ]);
}


# Update reverse relations and regenerate relation graph
# Arguments: %old. %new, vid, cid, rev
#  %old,%new -> { vid2 => relation, .. }
#    from the perspective of vid
#  cid, rev are of the related edit
# !IMPORTANT!: Don't forget to update this function when
#   adding/removing fields to/from VN entries!
sub _updreverse {
  my($self, $old, $new, $vid, $cid, $rev) = @_;
  my %upd;

  # compare %old and %new
  for (keys %$old, keys %$new) {
    if(exists $$old{$_} and !exists $$new{$_}) {
      $upd{$_} = -1;
    } elsif((!exists $$old{$_} and exists $$new{$_}) || ($$old{$_} != $$new{$_})) {
      $upd{$_} = $$new{$_};
      if   ($self->{vn_relations}[$upd{$_}  ][1]) { $upd{$_}-- }
      elsif($self->{vn_relations}[$upd{$_}+1][1]) { $upd{$_}++ }
    }
  }

  return if !keys %upd;

  # edit all related VNs
  for my $i (keys %upd) {
    my $r = $self->dbVNGet(id => $i, what => 'extended relations categories anime screenshots')->[0];
    my @newrel = map $_->{id} != $vid ? [ $_->{relation}, $_->{id} ] : (), @{$r->{relations}};
    push @newrel, [ $upd{$i}, $vid ] if $upd{$i} != -1;
    $self->dbVNEdit($i,
      relations => \@newrel,
      editsum => "Reverse relation update caused by revision v$vid.$rev",
      causedby => $cid,
      uid => 1,         # Multi - hardcoded
      anime => [ map $_->{id}, @{$r->{anime}} ],
      screenshots => [ map [ $_->{id}, $_->{nsfw}, $_->{rid} ], @{$r->{screenshots}} ],
      ( map { $_ => $r->{$_} } qw| title original desc alias categories img_nsfw length l_wp l_encubed l_renai l_vnn image | )
    );
  }

  $self->multiCmd('relgraph '.join(' ', $vid, keys %upd));
}


# peforms a (simple) search and returns the results in XML format
sub vnxml {
  my $self = shift;

  my $q = $self->formValidate({ name => 'q', maxlength => 500 });
  return 404 if $q->{_err};
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


1;

