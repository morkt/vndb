#!/usr/bin/perl

use strict;
use warnings;
use Cwd 'abs_path';
use Data::Dumper 'Dumper';
use Image::Magick;


our $ROOT;
BEGIN { ($ROOT = abs_path $0) =~ s{/util/skingen\.pl$}{}; }


if(@ARGV) {
  writeskin(readskin($_)) for (@ARGV);
} else {
  /([^\/]+)$/ && writeskin(readskin($1)) for (glob($ROOT.'/static/s/*'));
}


sub readskin { # skin name
  my $name = shift;
  my %o;
  open my $F, '<', $ROOT.'/static/s/'.$name.'/conf' or die $!;
  while(<$F>) {
    chomp;
    s{[\t\s]*//.+$}{};
    next if !/^([a-z0-9]+)[\t\s]+(.+)$/;
    $o{$1} = $2;
  }
  close $F;
  return \%o;
}


sub writeskin { # $obj
  my $o = shift;
  open my $F, '>', $ROOT.'/static/s/'.$o->{name}.'/style.css' or die $!;

  # fix image locations
  $o->{$_} && ($o->{$_} = '/s/'.$o->{name}.'/'.$o->{$_}) for (qw|imglefttop imgrighttop|);

  # get the right top image
  if($o->{imgrighttop}) {
    my $img = Image::Magick->new;
    $img->Read($ROOT.'/static'.$o->{imgrighttop});
    $o->{_bgright} = sprintf 'background: url(%s) no-repeat; width: %dpx; height: %dpx',
      $o->{imgrighttop}, $img->Get('width'), $img->Get('height');
  } else {
    $o->{_bgright} = 'display: none';
  }

  # body background
  if(!$o->{imglefttop}) {
    $o->{_bodybg} = "background-image: none; background-color: $o->{bodybg}";
  } else {
    $o->{_bodybg} = "background: $o->{bodybg} url($o->{imglefttop}) no-repeat";
  }

  # create boxbg.png
  my $img = Image::Magick->new(size => '1x1');
  $img->Read('xc:'.$o->{boxbg});
  $img->Write(filename => $ROOT.'/static/s/'.$o->{name}.'/boxbg.png');
  $o->{_boxbg} = '/s/'.$o->{name}.'/boxbg.png';

  # get the blend color
  $img = Image::Magick->new(size => '1x1');
  $img->Read('xc:'.$o->{bodybg}, 'xc:'.$o->{boxbg});
  $img = $img->Flatten();
  $o->{_blendbg} = '#'.join '', map sprintf('%02x', $_*255), $img->GetPixel(x=>1,y=>1);

  my $d = join '', (<DATA>);
  $d =~ s/\$$_\$/$o->{$_}/g for (keys %$o);
  print $F $d;
  close $F;
}


1;


__DATA__
/* main background image and color */
body {
  $_bodybg$
}


/* main text color */
body,
#maincontent .releases td.tc5 a,
#maincontent #jt_box_categories li li a {
  color: $maintext$; /* maintext */
}


/* menu link and secondary title color  */
a,
#maincontent p.browseopts a,
#maincontent h2.alttitle,
#menulist h2,
#menulist h2 a,
#maincontent p.browseopts a {
  color: $alttitle$; /* alttitle */
}
a:hover {
  border-bottom: 1px dotted $alttitle$; /* alttitle */
}


/* main link color */
#maincontent div.mainbox a {
  color: $link$; /* link */
}


/* transparent image (used in multiple layers, so has to be transparent) */
div#iv_view,
#jt_box_visual_novels span.odd,
#jt_box_producers span.odd,
#ds_box tr.selected,
.releases tr.lang td,
#screenshots tr.rel td,
#menulist div.menubox,
#maincontent div.mainbox,
table tr.odd,
.docs ul.index,
input.submit,
#menulist h2 {
  background: url($_boxbg$) repeat; /* Box BG */
}


/* bg color of the tabs */
#maincontent ul.maintabs li a {
  background-color: $tabbg$; /* tabbg */
}

/* the color you get when blending the transparent image on the body bg */
#maincontent ul.maintabs li.tabselected a,
#maincontent ul.maintabs li a:hover {
  background-color: $_blendbg$; /* blendbg */
}


/* the small image on the top-right (make sure to update the image size) */
#bgright {
  $_bgright$
}


/* site title */
#header h1, #header h1 a {
  color: $maintitle$; /* maintitle */
}


/* footer text color */
#footer, #footer a {
  color: $footer$; /* footer */
}


/* darkened/grayed-out text color */
#maincontent h1.boxtitle,
#maincontent h1.boxtitle a,
div.mainbox.discussions td.tags a,
div.thread i.edit,
div.thread i.lastmod,
div.thread i.deleted,
div.mainbox.history td.editsum,
#maincontent h1,
.docs dt b {
  color: $border$!important; /* border */
}


/* stand-out text color */
b.future, p.locked {
  color: $standout$; /* standout */
}


/* primary border color (usually the same as above) */
#maincontent div.mainbox,
#menulist div.menubox,
#menulist h2,
#maincontent ul.maintabs li a,
#maincontent ul.maintabs.bottom li a,
#maincontent p.browseopts a,
div.thread td,
div.thread td.tc1,
div.vndescription h2,
#screenshots td.scr a:hover img,
#ds_box,
#scr_table td,
#advoptions,
.docs ul.index,
div.revision div,
div.revision table,
div.revision table td,
div#iv_view {
  border-color: $border$; /* border */
}

/* same color is also used for the vote graph */
.votegraph td div {
  background-color: $border$; /* border */
}



/* secondary bg color */
table thead td, input.text, input.submit, select, textarea {
  background-color: $secbg$; /* secbg */
}

/* secondary border color */
input.text, input.submit, select, textarea {
  border: 1px solid $secborder$; /* secborder */
}


/* status colors */
b.done, ul#catselect li li.inc { color: $statok$ }  /* statok */
b.todo, ul#catselect li li.exc { color: $statnok$ }  /* statnok */
#screenshots td.scr div.nsfw img { border-color: $statnok$ } /* statnok */





/****** Not too sure what to do with these *******/



/* category levels - calculate from maintext? */
.catlvl_1 { color: #444 }
.catlvl_2 { color: #777 }
.catlvl_3 { color: #fff }


/* bg color of the dropdown search and revision tables (use an other already existing color?) */
#ds_box, div.revision div, div.revision table {
  background-color: #13273a;
}


/* warning and notice boxes - the maintext color must be readable on these... */
div.warning {
  background-color: #534;
  border: 1px solid #C00;
}
div.notice {
  background-color: #354;
  border: 1px solid #0C0;
}


/* diff colors - calculate from maintext? */
.diff_add { background-color: #354; }
.diff_del { background-color: #534; }


/* category colors on vn edit */
.catsel_1 { color: #0c0!important }
.catsel_2 { color: #cc0!important }
.catsel_3 { color: #c00!important }

